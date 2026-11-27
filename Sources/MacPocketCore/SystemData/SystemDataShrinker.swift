import Darwin
import Foundation

public struct SystemDataShrinkProgress: Sendable, Equatable {
    public let filesDone: Int
    public let filesTotal: Int
    public let savedBytes: Int64
    public var fraction: Double { filesTotal > 0 ? min(1, Double(filesDone) / Double(filesTotal)) : 1 }
}

public struct SystemDataShrinkResult: Sendable, Equatable {
    public let beforeBytes: Int64
    public let afterBytes: Int64
    public let filesCompressed: Int
    /// Files left alone: shared with something outside the folder, cloned, too small, already compressed,
    /// fresh, not compressible.
    public let filesSkipped: Int
    public let cancelled: Bool
    public var savedBytes: Int64 { max(0, beforeBytes - afterBytes) }
}

public struct SystemDataShrinkEstimate: Sendable, Equatable {
    public let candidateFiles: Int
    public let candidateBytes: Int64
    public let sharedFiles: Int
    /// Extrapolated from compressing a sample of the real files, in a scratch folder.
    public let estimatedSavedBytes: Int64
    public let estimatedSeconds: Double
    public let sampleRatio: Double
}

public enum SystemDataShrinkError: Error, LocalizedError, Equatable {
    case notAFolder
    case busy([String])
    case notEnoughSpace
    case nothingToShrink
    case verificationFailed(String)
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAFolder: String(localized: "Küçültülecek öğe bir klasör olmalı.")
        case .busy(let tools): String(localized: "\(tools.joined(separator: ", ")) bu klasörde çalışıyor; iş bitince tekrar dene.")
        case .notEnoughSpace: String(localized: "En büyük dosyanın sıkıştırılmış kopyası için bile yeterli boş alan yok.")
        case .nothingToShrink: String(localized: "Bu klasörde sıkıştırılabilecek uygun dosya bulunmadı (hepsi küçük, zaten sıkıştırılmış, başka yerlerle paylaşımlı veya çok yeni).")
        case .verificationFailed(let detail): String(localized: "Sıkıştırılmış kopya doğrulanamadı; işlem durduruldu ve dosyalar olduğu gibi duruyor. \(detail)")
        case .toolFailed(let detail): String(localized: "Sıkıştırma aracı başarısız oldu: \(detail)")
        }
    }
}

/// "Shrink instead of delete": stores files compressed, the way macOS stores its own (transparent APFS
/// compression). Nothing is deleted and every path keeps working.
///
/// Works in place, one file at a time, so it needs room for one compressed copy, not for the whole folder.
/// Each file is compressed to a hidden sibling with `ditto --hfsCompression --noclone` (`--noclone`: without
/// it ditto clones on APFS and nothing is compressed), compared with the original, checked for changes made
/// meanwhile and only then put in place. Hard links inside the folder are kept: every name of the file is
/// repointed at the one compressed copy. Files with a link or clone outside the folder are left alone,
/// because compressing them would only duplicate their blocks.
public actor SystemDataShrinker {
    public typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) async -> (status: Int32, message: String)

    public static let minimumFileBytes: Int64 = 65_536
    public static let spaceMargin: Int64 = 200_000_000
    /// Files modified more recently than this are skipped: they are probably being written.
    public static let quietSeconds: TimeInterval = 600
    static let fullCompareLimit: Int64 = 128_000_000
    static let sampleBytes = 1_000_000
    static let temporaryMarker = ".mpshrink-"

    private let run: CommandRunner
    private let availableBytes: @Sendable (URL) -> Int64?
    private let busyTools: @Sendable (String) -> [String]
    private let now: @Sendable () -> Date
    private let concurrency: Int

    public init(run: @escaping CommandRunner = SystemDataShrinker.liveRunner,
                availableBytes: @escaping @Sendable (URL) -> Int64? = { url in
                    (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
                },
                busyTools: @escaping @Sendable (String) -> [String] = { BuildActivity.runningTools(under: $0) },
                now: @escaping @Sendable () -> Date = { Date() }, concurrency: Int = 4) {
        self.run = run
        self.availableBytes = availableBytes
        self.busyTools = busyTools
        self.now = now
        self.concurrency = max(1, concurrency)
    }

    public static let liveRunner: CommandRunner = { executable, arguments in
        do {
            let result = try await BoundedProcess.run(executable, arguments, timeout: 600)
            return (result.status, result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return (1, error.localizedDescription) }
    }

    // MARK: Planning

    struct Candidate: Sendable {
        let paths: [String]
        let inode: UInt64
        let size: Int64
        let blocksBytes: Int64
        let modified: Int64
    }

    struct Plan: Sendable {
        var candidates: [Candidate] = []
        var totalAllocated: Int64 = 0
        var skipped = 0
        var shared = 0
        var leftovers: [String] = []
    }

    /// Walks the folder once and decides, per file (per inode), whether it can be compressed.
    func plan(for root: String) async -> Plan {
        let cutoff = now().timeIntervalSince1970 - Self.quietSeconds
        return await Task.detached(priority: .utility) { Self.planSync(root: root, quietCutoff: cutoff) }.value
    }

    private struct Group { var paths: [String] = []; var links: UInt16 = 0; var size: Int64 = 0; var blocks: Int64 = 0; var modified: Int64 = 0 }

    private static func planSync(root: String, quietCutoff: TimeInterval) -> Plan {
        var groups: [FileObjectKey: Group] = [:]
        var plan = Plan()
        TreeWalker.walk(root) { entry in
            guard entry.kind == .file else { return .proceed }
            if let name = entry.path.split(separator: "/").last, name.hasPrefix("."), name.contains(temporaryMarker),
               Double(entry.modified) < quietCutoff - 3_000 { plan.leftovers.append(entry.path); return .proceed }
            let key = FileObjectKey(device: entry.device, inode: entry.inode)
            var group = groups[key] ?? Group()
            group.paths.append(entry.path)
            group.links = entry.links
            group.size = entry.logicalBytes
            group.blocks = entry.allocatedBytes
            group.modified = entry.modified
            groups[key] = group
            return .proceed
        }
        for (key, group) in groups {
            plan.totalAllocated += group.blocks
            guard group.size >= minimumFileBytes else { plan.skipped += 1; continue }
            guard group.paths.count == Int(group.links) else { plan.shared += group.paths.count; plan.skipped += 1; continue }
            guard Double(group.modified) < quietCutoff else { plan.skipped += 1; continue }
            var info = stat()
            guard lstat(group.paths[0], &info) == 0,
                  info.st_flags & (UInt32(UF_COMPRESSED) | UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) == 0 else { plan.skipped += 1; continue }
            if (cloneReferenceCount(group.paths[0]) ?? 1) > 1 { plan.shared += group.paths.count; plan.skipped += 1; continue }
            plan.candidates.append(Candidate(paths: group.paths.sorted(), inode: key.inode, size: group.size, blocksBytes: group.blocks, modified: group.modified))
        }
        plan.candidates.sort { $0.blocksBytes != $1.blocksBytes ? $0.blocksBytes > $1.blocksBytes : $0.paths[0] < $1.paths[0] }
        return plan
    }

    /// How many files share this file's data blocks through APFS cloning (1 means only this one).
    static func cloneReferenceCount(_ path: String) -> UInt32? {
        struct Reply { var length: UInt32 = 0; var count: UInt32 = 0 }
        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT)
        var reply = Reply()
        let status = getattrlist(path, &list, &reply, MemoryLayout<Reply>.size, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        return status == 0 ? reply.count : nil
    }

    // MARK: Estimate

    /// Compresses a sample of the real files in a scratch folder and extrapolates; changes nothing in the
    /// folder.
    public func estimate(folder path: String) async throws -> SystemDataShrinkEstimate {
        try validate(folder: path)
        let plan = await self.plan(for: path)
        guard !plan.candidates.isEmpty else { throw SystemDataShrinkError.nothingToShrink }
        var sample: [Candidate] = []
        var sampled: Int64 = 0
        var generator = SeededGenerator(seed: UInt64(plan.candidates.count) &* 2_654_435_761)
        for candidate in plan.candidates.shuffled(using: &generator) where sampled < 192_000_000 && sample.count < 64 {
            guard candidate.size <= 64_000_000 else { continue }
            sample.append(candidate)
            sampled += candidate.blocksBytes
        }
        if sample.isEmpty, let smallest = plan.candidates.min(by: { $0.size < $1.size }) { sample = [smallest]; sampled = smallest.blocksBytes }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "mp-shrink-estimate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let started = Date()
        var savedSample: Int64 = 0
        for (index, candidate) in sample.enumerated() {
            let destination = scratch.appending(path: "s\(index)").path
            guard await run("/usr/bin/ditto", ["--hfsCompression", "--noclone", candidate.paths[0], destination]).status == 0 else { continue }
            var after = stat()
            if lstat(destination, &after) == 0 { savedSample += max(0, candidate.blocksBytes - Int64(after.st_blocks) * 512) }
        }
        let elapsed = max(0.05, Date().timeIntervalSince(started))
        let ratio = sampled > 0 ? Double(savedSample) / Double(sampled) : 0
        let candidateBytes = plan.candidates.reduce(Int64(0)) { $0 + $1.blocksBytes }
        let throughput = Double(sampled) / elapsed * Double(concurrency)
        return SystemDataShrinkEstimate(candidateFiles: plan.candidates.count, candidateBytes: candidateBytes, sharedFiles: plan.shared,
                                        estimatedSavedBytes: Int64(Double(candidateBytes) * ratio),
                                        estimatedSeconds: throughput > 0 ? Double(candidateBytes) / throughput : 0, sampleRatio: ratio)
    }

    // MARK: Shrink

    private func validate(folder path: String) throws {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let identity = try? FileIdentity.read(folder), identity.isDirectory, !identity.isSymbolicLink,
              existingCanonicalPath(folder) == path else { throw SystemDataShrinkError.notAFolder }
    }

    /// - Parameter guardRoot: where build tools are looked for (the project); defaults to the folder's parent.
    public func shrink(folder path: String, guardRoot: String? = nil,
                       progress: @escaping @Sendable (SystemDataShrinkProgress) -> Void = { _ in }) async throws -> SystemDataShrinkResult {
        try validate(folder: path)
        let busy = busyTools(guardRoot ?? URL(fileURLWithPath: path).deletingLastPathComponent().path)
        guard busy.isEmpty else { throw SystemDataShrinkError.busy(busy) }

        let plan = await self.plan(for: path)
        for leftover in plan.leftovers { try? FileManager.default.removeItem(atPath: leftover) }
        guard !plan.candidates.isEmpty else { throw SystemDataShrinkError.nothingToShrink }
        let largest = plan.candidates.map(\.blocksBytes).max() ?? 0
        if let available = availableBytes(URL(fileURLWithPath: path)), available < largest * 2 + Self.spaceMargin { throw SystemDataShrinkError.notEnoughSpace }

        let total = plan.candidates.count
        let concurrency = self.concurrency
        let tally = await withTaskGroup(of: Outcome.self, returning: Tally.self) { group in
            var tally = Tally(skipped: plan.skipped)
            var iterator = plan.candidates.makeIterator()
            func addNext() {
                guard !Task.isCancelled, tally.problem == nil, let next = iterator.next() else { return }
                group.addTask { await self.compress(next) }
            }
            for _ in 0..<concurrency { addNext() }
            while let outcome = await group.next() {
                tally.done += 1
                switch outcome {
                case .saved(let bytes): tally.saved += bytes
                tally.compressed += 1
                case .skipped: tally.skipped += 1
                case .verificationFailed(let detail): tally.problem = tally.problem ?? detail
                case .toolFailed(let detail): tally.problem = tally.problem ?? "tool: " + detail
                }
                progress(SystemDataShrinkProgress(filesDone: tally.done, filesTotal: total, savedBytes: tally.saved))
                addNext()
            }
            tally.cancelled = Task.isCancelled
            return tally
        }
        if let problem = tally.problem {
            throw problem.hasPrefix("tool: ") ? SystemDataShrinkError.toolFailed(String(problem.dropFirst(6))) : SystemDataShrinkError.verificationFailed(problem)
        }
        return SystemDataShrinkResult(beforeBytes: plan.totalAllocated, afterBytes: max(0, plan.totalAllocated - tally.saved), filesCompressed: tally.compressed,
                                      filesSkipped: tally.skipped, cancelled: tally.cancelled)
    }

    private struct Tally: Sendable {
        var saved: Int64 = 0
        var compressed = 0
        var skipped = 0
        var done = 0
        var problem: String?
        var cancelled = false
    }

    enum Outcome: Sendable {
        case saved(Int64)
        case skipped
        case verificationFailed(String)
        case toolFailed(String)
    }

    /// One file (all the names of one inode): compress, verify, replace. Never leaves a partial file behind.
    func compress(_ candidate: Candidate) async -> Outcome {
        let source = candidate.paths[0]
        let directory = (source as NSString).deletingLastPathComponent
        let name = (source as NSString).lastPathComponent
        let token = UUID().uuidString.prefix(8)
        let temporary = directory + "/." + name + Self.temporaryMarker + token
        defer { try? FileManager.default.removeItem(atPath: temporary) }

        var before = stat()
        guard lstat(source, &before) == 0, before.st_ino == candidate.inode, Int64(before.st_size) == candidate.size,
              Int64(before.st_mtimespec.tv_sec) == candidate.modified, Int(before.st_nlink) == candidate.paths.count else { return .skipped }

        let copied = await run("/usr/bin/ditto", ["--hfsCompression", "--noclone", source, temporary])
        guard copied.status == 0 else { return FileManager.default.fileExists(atPath: source) ? .toolFailed(copied.message) : .skipped }
        var after = stat()
        guard lstat(temporary, &after) == 0, after.st_flags & UInt32(UF_COMPRESSED) != 0 else { return .skipped }   // not compressible
        let saved = Int64(before.st_blocks - after.st_blocks) * 512
        guard saved >= max(Self.minimumFileBytes, candidate.blocksBytes / 10) else { return .skipped }

        guard after.st_size == before.st_size, after.st_mode == before.st_mode, after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec else {
            return .verificationFailed("attributes of \(source)")
        }
        guard Self.contentsMatch(source, temporary, size: candidate.size) else { return .verificationFailed("content of \(source)") }

        var recheck = stat()
        guard lstat(source, &recheck) == 0, recheck.st_ino == before.st_ino, recheck.st_size == before.st_size,
              recheck.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec, recheck.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
              recheck.st_nlink == before.st_nlink else { return .skipped }   // changed while compressing: keep the original

        guard rename(temporary, source) == 0 else { return .toolFailed(String(cString: strerror(errno))) }
        // Every other name of the same file points at the new copy, so hard links inside the folder survive.
        for other in candidate.paths.dropFirst() {
            let link = (other as NSString).deletingLastPathComponent + "/." + (other as NSString).lastPathComponent + Self.temporaryMarker + "l" + token
            if Darwin.link(source, link) == 0 { if rename(link, other) != 0 { unlink(link) } }
        }
        return .saved(saved)
    }

    // MARK: Comparison

    static func contentsMatch(_ a: String, _ b: String, size: Int64) -> Bool {
        guard let left = FileHandle(forReadingAtPath: a), let right = FileHandle(forReadingAtPath: b) else { return false }
        defer { try? left.close(); try? right.close() }
        func read(_ handle: FileHandle, offset: UInt64, count: Int) -> Data? {
            try? handle.seek(toOffset: offset)
            return try? handle.read(upToCount: count)
        }
        if size <= fullCompareLimit {
            var offset: UInt64 = 0
            let chunk = 4_194_304
            while Int64(offset) < size {
                let count = Int(min(Int64(chunk), size - Int64(offset)))
                if read(left, offset: offset, count: count) != read(right, offset: offset, count: count) { return false }
                offset += UInt64(count)
            }
            return true
        }
        let window = Int64(sampleBytes)
        for offset in [0, size / 4, size / 2, size * 3 / 4, max(0, size - window)] {
            if read(left, offset: UInt64(max(0, offset)), count: sampleBytes) != read(right, offset: UInt64(max(0, offset)), count: sampleBytes) { return false }
        }
        return true
    }
}

/// A tiny deterministic generator so the estimate's sample is repeatable for the same folder.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

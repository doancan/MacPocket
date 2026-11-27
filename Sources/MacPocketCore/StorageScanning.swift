import Darwin
import Foundation

// MARK: - Scan control

/// Shared budget, cancellation and progress for one storage scan.
///
/// Walkers run synchronously on GCD threads (never on the cooperative pool), so cancellation is
/// signalled through this object instead of `Task.isCancelled`. All counters are lock-protected and
/// walkers update them in batches, so the lock is taken rarely even for millions of entries.
public final class StorageScanControl: @unchecked Sendable {
    public let deadline: Date
    public let entryLimit: Int
    private let lock = NSLock()
    private var cancelledFlag = false
    private var visited = 0
    private var bytes: Int64 = 0
    private var limitFlag = false
    private var currentName = ""
    /// Targets in flight. Parallel scans used to overwrite one label, so the UI named a finished target
    /// while another (often one blocked on a macOS privacy prompt) was still running.
    private var activeNames: [String] = []

    public init(maximumDuration: TimeInterval = 90, maximumEntries: Int = 3_000_000) {
        deadline = Date().addingTimeInterval(max(0.05, maximumDuration))
        entryLimit = max(1, maximumEntries)
    }

    public func cancel() { lock.withLock { cancelledFlag = true } }
    public var isCancelled: Bool { lock.withLock { cancelledFlag } }
    /// True once the time or entry budget ran out; results are then partial.
    public var limitReached: Bool { lock.withLock { limitFlag } }

    public struct Snapshot: Sendable, Equatable {
        public let visitedEntries: Int
        public let measuredBytes: Int64
        public let currentName: String
    }

    public var snapshot: Snapshot {
        lock.withLock {
            Snapshot(visitedEntries: visited, measuredBytes: bytes,
                     currentName: activeNames.isEmpty ? currentName : activeNames.joined(separator: ", "))
        }
    }

    public func setCurrent(_ name: String) { lock.withLock { currentName = name } }
    public func beginTarget(_ name: String) { lock.withLock { activeNames.append(name) } }
    public func endTarget(_ name: String) {
        lock.withLock { if let index = activeNames.firstIndex(of: name) { activeNames.remove(at: index) } }
    }

    /// Records a batch of work. Returns false when the walker must stop (cancelled or out of budget).
    func record(entries: Int, bytes added: Int64) -> Bool {
        lock.withLock {
            visited += entries
            bytes = bytes.addingReportingOverflow(added).overflow ? Int64.max : bytes + added
            if cancelledFlag { return false }
            if visited >= entryLimit || Date() >= deadline { limitFlag = true; return false }
            return true
        }
    }
}

/// Hard-linked files are counted once per scan, even across categories walked in parallel.
final class HardLinkRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<FileObjectKey>()
    /// Returns true the first time an object is seen.
    func insert(device: Int32, inode: UInt64) -> Bool {
        lock.withLock { seen.insert(FileObjectKey(device: device, inode: inode)).inserted }
    }
}

struct FileObjectKey: Hashable {
    let device: Int32
    let inode: UInt64
}

// MARK: - Tree walking

/// One entry as reported by fts, with the stat fields the storage tools need.
struct WalkEntry {
    enum Kind { case directory, directoryPost, file, symlink, unreadable, other }
    let kind: Kind
    let path: String
    let level: Int
    let device: Int32
    let inode: UInt64
    let links: UInt16
    let mode: UInt16
    /// Allocated size: `st_blocks * 512`. APFS clones and sparse files report what they really use.
    let allocatedBytes: Int64
    let logicalBytes: Int64
    let modified: Int64
    let error: Int32
}

enum WalkAction { case proceed, skipDescendants, stop }

/// Physical (never follows symlinks), single-device traversal built on fts(3).
enum TreeWalker {
    /// Returns false when the walk could not start (root missing or unreadable).
    @discardableResult
    static func walk(_ root: String, _ visit: (WalkEntry) -> WalkAction) -> Bool {
        guard let cPath = strdup(root) else { return false }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        let options = FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV
        guard let fts = argv.withUnsafeMutableBufferPointer({ fts_open($0.baseAddress, options, nil) }) else { return false }
        defer { fts_close(fts) }
        var rootDevice: Int32?
        // fts still delivers FTS_DP for a directory skipped in pre-order; hide it when its FTS_D was hidden.
        var hiddenDirectory: String?
        while let pointer = fts_read(fts) {
            let entry = pointer.pointee
            let kind: WalkEntry.Kind
            switch Int32(entry.fts_info) {
            case FTS_D: kind = .directory
            case FTS_DP: kind = .directoryPost
            case FTS_F: kind = .file
            case FTS_SL, FTS_SLNONE: kind = .symlink
            case FTS_DNR, FTS_ERR, FTS_NS: kind = .unreadable
            case FTS_DC: kind = .other
            default: kind = .other
            }
            let path = String(cString: entry.fts_path)
            if kind == .directoryPost, let hidden = hiddenDirectory, hidden == path {
                hiddenDirectory = nil
                continue
            }
            var info = stat()
            if let statp = entry.fts_statp, kind != .unreadable { info = statp.pointee }
            if Int(entry.fts_level) == Int(FTS_ROOTLEVEL), kind == .directory || kind == .file { rootDevice = info.st_dev }
            // fts's FTS_XDEV still reports a mount point itself; never descend into another device.
            if kind == .directory, let rootDevice, info.st_dev != rootDevice {
                fts_set(fts, pointer, Int32(FTS_SKIP))
                hiddenDirectory = path
                continue
            }
            let walkEntry = WalkEntry(kind: kind, path: path, level: Int(entry.fts_level),
                                      device: info.st_dev, inode: info.st_ino, links: info.st_nlink, mode: info.st_mode,
                                      allocatedBytes: max(0, Int64(info.st_blocks) * 512), logicalBytes: max(0, info.st_size),
                                      modified: Int64(info.st_mtimespec.tv_sec), error: entry.fts_errno)
            switch visit(walkEntry) {
            case .proceed: break
            case .skipDescendants: if kind == .directory { fts_set(fts, pointer, Int32(FTS_SKIP)) }
            case .stop: return true
            }
        }
        return true
    }
}

// MARK: - Directory size

public struct StorageMeasurement: Codable, Sendable, Equatable {
    /// Allocated bytes (blocks on disk); this is what deleting the item can free.
    public var allocatedBytes: Int64 = 0
    public var logicalBytes: Int64 = 0
    public var fileCount = 0
    public var directoryCount = 0
    public var skippedLinks = 0
    public var inaccessibleCount = 0
    /// False when the budget ran out or the walk was cancelled before finishing.
    public var complete = true
    /// Newest modification time seen anywhere in the item (seconds since 1970).
    public var newestModification: Int64 = 0
    public init() {}

    mutating func add(_ other: StorageMeasurement) {
        allocatedBytes = allocatedBytes.addingReportingOverflow(other.allocatedBytes).overflow ? Int64.max : allocatedBytes + other.allocatedBytes
        logicalBytes = logicalBytes.addingReportingOverflow(other.logicalBytes).overflow ? Int64.max : logicalBytes + other.logicalBytes
        fileCount += other.fileCount
        directoryCount += other.directoryCount
        skippedLinks += other.skippedLinks
        inaccessibleCount += other.inaccessibleCount
        complete = complete && other.complete
        newestModification = max(newestModification, other.newestModification)
    }
}

/// Recursive allocated-size measurement. Symlinks are never followed (the link itself is not
/// counted), other devices are skipped and hard links count once per registry.
enum DirectorySizer {
    static let batch = 256

    static func measure(_ path: String, control: StorageScanControl, links: HardLinkRegistry,
                        excluding excluded: Set<String> = []) -> StorageMeasurement {
        var result = StorageMeasurement()
        var pendingEntries = 0
        var pendingBytes: Int64 = 0
        var stopped = false
        let started = TreeWalker.walk(path) { entry in
            pendingEntries += 1
            if pendingEntries >= batch {
                if !control.record(entries: pendingEntries, bytes: pendingBytes) { stopped = true; pendingEntries = 0; pendingBytes = 0; return .stop }
                pendingEntries = 0
                pendingBytes = 0
            }
            switch entry.kind {
            case .directory:
                if entry.level > 0, excluded.contains(entry.path) { return .skipDescendants }
                result.directoryCount += 1
                result.allocatedBytes += entry.allocatedBytes
                pendingBytes += entry.allocatedBytes
            case .file:
                result.newestModification = max(result.newestModification, entry.modified)
                if entry.links > 1, !links.insert(device: entry.device, inode: entry.inode) { return .proceed }
                result.fileCount += 1
                result.allocatedBytes += entry.allocatedBytes
                result.logicalBytes += entry.logicalBytes
                pendingBytes += entry.allocatedBytes
            case .symlink: result.skippedLinks += 1
            case .unreadable: result.inaccessibleCount += 1
            case .directoryPost, .other: break
            }
            return .proceed
        }
        if !stopped, !control.record(entries: pendingEntries, bytes: pendingBytes) {
            // The final batch crossing the budget does not make a finished walk partial.
            if control.isCancelled { stopped = true }
        }
        if !started { result.inaccessibleCount += 1 }
        result.complete = started && !stopped && result.inaccessibleCount == 0
        return result
    }
}

// MARK: - GCD bridge

enum StorageWork {
    /// Runs blocking filesystem work on a GCD thread so it never occupies the Swift cooperative pool.
    /// Task cancellation is forwarded to the scan control.
    static func run<T: Sendable>(_ control: StorageScanControl, _ work: @escaping @Sendable () -> T) async -> T {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
            }
        } onCancel: { control.cancel() }
    }
}

// MARK: - Volume capacity

public struct VolumeCapacity: Codable, Sendable, Equatable {
    public let name: String
    public let totalBytes: Int64
    /// Free space excluding purgeable data.
    public let availableBytes: Int64
    /// Free space macOS can provide for important work, including purgeable data.
    public let importantAvailableBytes: Int64
    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var purgeableBytes: Int64 { max(0, importantAvailableBytes - availableBytes) }

    public init(name: String, totalBytes: Int64, availableBytes: Int64, importantAvailableBytes: Int64) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.importantAvailableBytes = importantAvailableBytes
    }

    public static func read(_ url: URL = URL(fileURLWithPath: NSHomeDirectory())) throws -> VolumeCapacity {
        let values = try url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                                      .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let available = Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeCapacity(name: values.volumeLocalizedName ?? "Disk",
                              totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                              availableBytes: available,
                              importantAvailableBytes: max(available, values.volumeAvailableCapacityForImportantUsage ?? 0))
    }
}

/// Canonical path of an existing item, or nil when it is missing. Never resolves the final symlink:
/// callers check `lstat` separately so a symlinked target is reported, not followed.
func existingCanonicalPath(_ url: URL) -> String? {
    guard let path = realpath(url.path, nil) else { return nil }
    defer { free(path) }
    return String(cString: path)
}

func lstatIdentity(_ path: String) -> FileIdentity? { try? FileIdentity.read(URL(fileURLWithPath: path)) }

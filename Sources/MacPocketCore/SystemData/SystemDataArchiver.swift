import Foundation

public struct SystemDataArchiveRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let originalPath: String
    public let archivePath: String
    public let originalBytes: Int64
    public let archiveBytes: Int64
    public let createdAt: Date
    public var savedBytes: Int64 { max(0, originalBytes - archiveBytes) }
}

public enum SystemDataArchiveError: Error, LocalizedError, Equatable {
    case notAFolder
    case sharedFiles
    case notEnoughSpace
    case changedWhileArchiving
    case verificationFailed(String)
    case targetExists
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAFolder: String(localized: "Arşivlenecek öğe bir klasör olmalı.")
        case .sharedFiles: String(localized: "Klasördeki dosyalar başka yerlerle sabit bağlı (örneğin pnpm deposu); arşivlenirse bu bağlar kopar.")
        case .notEnoughSpace: String(localized: "Arşiv için diskte yeterli boş alan yok.")
        case .changedWhileArchiving: String(localized: "Klasör arşivlenirken değişti; hiçbir şey silinmedi.")
        case .verificationFailed(let detail): String(localized: "Arşiv doğrulanamadı; klasör olduğu gibi duruyor. \(detail)")
        case .targetExists: String(localized: "Geri yüklenecek yerde aynı adlı bir öğe var.")
        case .toolFailed(let detail): String(localized: "Arşivleme aracı başarısız oldu: \(detail)")
        }
    }
}

/// "Shrink instead of delete" for folders that are only ever read: build output, old toolchains, archives.
///
/// The folder is packed into a compressed zip next to it, the zip is verified, the folder is checked for
/// changes made meanwhile and only then removed. Restoring unpacks it where it was. Transparent filesystem
/// compression is not available through public APIs on this macOS (`ditto --hfsCompression` clones instead of
/// compressing), so this trades a restore step for the space.
public actor SystemDataArchiver {
    public typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) async -> (status: Int32, message: String)

    public static let folderName = ".MacPocket Archives"
    public static let spaceMargin: Int64 = 200_000_000

    private let manifest: URL
    private let run: CommandRunner
    private let availableBytes: @Sendable (URL) -> Int64?
    private let trash: FileTrashService

    public init(manifest: URL = SystemDataArchiver.defaultManifest,
                run: @escaping CommandRunner = SystemDataArchiver.liveRunner,
                availableBytes: @escaping @Sendable (URL) -> Int64? = { url in
                    (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
                },
                trash: FileTrashService = FileTrashService()) {
        self.manifest = manifest
        self.run = run
        self.availableBytes = availableBytes
        self.trash = trash
    }

    public static var defaultManifest: URL {
        URL.applicationSupportDirectory.appending(path: "MacPocket", directoryHint: .isDirectory)
            .appending(path: "system-data-archives.json", directoryHint: .notDirectory)
    }

    public static let liveRunner: CommandRunner = { executable, arguments in
        do {
            let result = try await BoundedProcess.run(executable, arguments, timeout: 3_600)
            return (result.status, result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return (1, error.localizedDescription) }
    }

    // MARK: Records

    public func records() -> [SystemDataArchiveRecord] {
        guard let data = try? Data(contentsOf: manifest) else { return [] }
        return ((try? Self.decoder.decode([SystemDataArchiveRecord].self, from: data)) ?? []).filter {
            FileManager.default.fileExists(atPath: $0.archivePath)
        }
    }

    private func save(_ records: [SystemDataArchiveRecord]) throws {
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(records).write(to: manifest, options: .atomic)
    }

    // MARK: Archive

    /// - Parameter folder: a canonical absolute folder path measured by the scanner.
    public func archive(folder path: String, title: String) async throws -> SystemDataArchiveRecord {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let identity = try? FileIdentity.read(folder), identity.isDirectory, !identity.isSymbolicLink,
              existingCanonicalPath(folder) == path else { throw SystemDataArchiveError.notAFolder }
        let before = Self.fingerprint(of: path)
        guard before.hardLinked == 0 else { throw SystemDataArchiveError.sharedFiles }

        let parent = folder.deletingLastPathComponent()
        let archives = parent.appending(path: Self.folderName, directoryHint: .isDirectory)
        if let available = availableBytes(parent), available < before.bytes / 2 + Self.spaceMargin { throw SystemDataArchiveError.notEnoughSpace }
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let final = archives.appending(path: "\(folder.lastPathComponent)-\(id.prefix(8)).zip")
        let partial = final.appendingPathExtension("partial")
        func discardPartial() { try? FileManager.default.removeItem(at: partial) }

        let packed = await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", path, partial.path])
        guard packed.status == 0 else { discardPartial(); throw SystemDataArchiveError.toolFailed(packed.message) }
        let verified = await run("/usr/bin/unzip", ["-tq", partial.path])
        guard verified.status == 0 else { discardPartial(); throw SystemDataArchiveError.verificationFailed(verified.message) }
        guard Self.fingerprint(of: path) == before else { discardPartial(); throw SystemDataArchiveError.changedWhileArchiving }

        try FileManager.default.moveItem(at: partial, to: final)
        let request = FileTrashRequest(url: folder, identity: identity, root: parent)
        let results = await trash.remove([request], mode: .deletePermanently)
        if let failure = results.first?.error {
            try? FileManager.default.removeItem(at: final)
            throw SystemDataArchiveError.toolFailed(failure)
        }
        let size = (try? final.resourceValues(forKeys: [.fileAllocatedSizeKey]))?.fileAllocatedSize.map(Int64.init) ?? 0
        let record = SystemDataArchiveRecord(id: id, title: title, originalPath: path, archivePath: final.path,
                                             originalBytes: before.bytes, archiveBytes: size, createdAt: Date())
        try save(records() + [record])
        return record
    }

    // MARK: Restore and delete

    public func restore(_ record: SystemDataArchiveRecord) async throws {
        let target = URL(fileURLWithPath: record.originalPath)
        guard lstatIdentity(target.path) == nil else { throw SystemDataArchiveError.targetExists }
        let result = await run("/usr/bin/ditto", ["-x", "-k", record.archivePath, target.deletingLastPathComponent().path])
        guard result.status == 0, lstatIdentity(target.path) != nil else { throw SystemDataArchiveError.toolFailed(result.message) }
        try? FileManager.default.removeItem(atPath: record.archivePath)
        try save(records().filter { $0.id != record.id })
    }

    /// Gives the space up for good: the archive goes and the folder is not coming back.
    public func deleteArchive(_ record: SystemDataArchiveRecord) throws {
        try FileManager.default.removeItem(atPath: record.archivePath)
        try save(records().filter { $0.id != record.id })
    }

    // MARK: Fingerprint

    struct Fingerprint: Equatable {
        var files = 0
        var bytes: Int64 = 0
        var newestModification: Int64 = 0
        var hardLinked = 0
    }

    /// What must not change between packing and removing: file count, bytes and the newest modification time.
    static func fingerprint(of path: String) -> Fingerprint {
        var result = Fingerprint()
        TreeWalker.walk(path) { entry in
            switch entry.kind {
            case .file:
                result.files += 1
                result.bytes += entry.allocatedBytes
                result.newestModification = max(result.newestModification, entry.modified)
                if entry.links > 1 { result.hardLinked += 1 }
            case .symlink: result.files += 1
            default: break
            }
            return .proceed
        }
        return result
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

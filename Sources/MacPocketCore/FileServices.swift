import CryptoKit
import Darwin
import Foundation

/// Foundation may represent /private/var and /var differently while enumerating.
/// Use the filesystem's canonical path for containment and relative paths.
func canonicalFileURL(_ url: URL) throws -> URL {
    guard let path = realpath(url.path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { free(path) }
    return URL(fileURLWithPath: String(cString: path))
}

public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let mode: UInt16
    public let links: UInt16

    public static func read(_ url: URL) throws -> Self {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return Self(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                    modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                    mode: info.st_mode, links: info.st_nlink)
    }
    public var isSymbolicLink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
    public var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    public var isRegularFile: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    var objectKey: String { "\(device):\(inode)" }
}

public struct ScannedFile: Identifiable, Codable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let identity: FileIdentity
    public var bytes: Int64 { max(0, identity.size) }
    public var modifiedAt: Date { Date(timeIntervalSince1970: Double(identity.modifiedSeconds)) }
}

public struct FolderUsage: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let identity: FileIdentity
    public var bytes: Int64
    public var fileCount: Int
}

public struct FileScanOptions: Sendable {
    public var maximumEntries = 200_000
    public var maximumRetainedFiles = 8_000
    public var maximumDuration: TimeInterval = 45
    public var includeHidden = true
    public init() {}
}

public struct FileScanProgress: Sendable {
    public let visitedEntries: Int
    public let fileCount: Int
    public let bytes: Int64
}

public struct FileScanReport: Sendable {
    public let root: URL
    public let scannedAt: Date
    public let files: [ScannedFile]
    public let folders: [FolderUsage]
    public let fileCount: Int
    public let bytes: Int64
    public let skippedLinks: Int
    public let inaccessibleCount: Int
    public let issues: [String]
    public let limitReached: Bool
    public var retainedAllFiles: Bool { files.count == fileCount }
}

/// Metadata-only traversal. Symlinks are not followed and hard links count once.
public actor FileScanner {
    public init() {}
    public func scan(_ root: URL, options: FileScanOptions = .init(),
                     progress: @Sendable (FileScanProgress) async -> Void = { _ in }) async throws -> FileScanReport {
        let root = try canonicalFileURL(root.standardizedFileURL)
        let rootIdentity = try FileIdentity.read(root)
        guard rootIdentity.isDirectory else { throw FileServiceError.notDirectory }
        let started = Date()
        let maximumEntries = max(1, options.maximumEntries)
        let retainedLimit = min(50_000, max(1, options.maximumRetainedFiles))
        let deadline = started.addingTimeInterval(max(0.1, min(300, options.maximumDuration)))
        var files: [ScannedFile] = []
        var folders: [String: FolderUsage] = [:]
        var seen = Set<String>()
        var visited = 0, fileCount = 0, skippedLinks = 0
        var bytes: Int64 = 0
        var limited = false
        // DirectoryEnumerator's error callback is synchronous on this traversal.
        let errors = ScanErrors()
        let enumerationOptions: FileManager.DirectoryEnumerationOptions = options.includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: enumerationOptions, errorHandler: { url, error in
            errors.count += 1
            if errors.messages.count < 24 { errors.messages.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            return true
        }) else { throw FileServiceError.unreadable }
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if visited >= maximumEntries || Date() >= deadline { limited = true; break }
            visited += 1
            do {
                let identity = try FileIdentity.read(url)
                if identity.isSymbolicLink { skippedLinks += 1; enumerator.skipDescendants(); continue }
                if identity.device != rootIdentity.device { enumerator.skipDescendants(); continue }
                guard identity.isRegularFile, seen.insert(identity.objectKey).inserted else { continue }
                let file = ScannedFile(url: url, identity: identity)
                files.append(file)
                if files.count > retainedLimit * 2 {
                    files.sort { $0.bytes > $1.bytes }
                    files.removeLast(files.count - retainedLimit)
                }
                fileCount += 1
                bytes = bytes.addingReportingOverflow(file.bytes).overflow ? Int64.max : bytes + file.bytes
                let relative = Array(url.pathComponents.dropFirst(root.pathComponents.count))
                if relative.count > 1, let first = relative.first {
                    let folderURL = root.appendingPathComponent(first, isDirectory: true)
                    if folders[first] == nil {
                        folders[first] = FolderUsage(url: folderURL, identity: try FileIdentity.read(folderURL), bytes: 0, fileCount: 0)
                    }
                    folders[first]?.bytes += file.bytes
                    folders[first]?.fileCount += 1
                }
            } catch {
                errors.count += 1
                if errors.messages.count < 24 { errors.messages.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if visited.isMultiple(of: 128) {
                await progress(.init(visitedEntries: visited, fileCount: fileCount, bytes: bytes))
                await Task.yield()
            }
        }
        try Task.checkCancellation()
        files.sort { $0.bytes > $1.bytes }
        if files.count > retainedLimit { files.removeLast(files.count - retainedLimit) }
        await progress(.init(visitedEntries: visited, fileCount: fileCount, bytes: bytes))
        return FileScanReport(root: root, scannedAt: started, files: files,
                              folders: folders.values.sorted { $0.bytes > $1.bytes },
                              fileCount: fileCount, bytes: bytes, skippedLinks: skippedLinks,
                              inaccessibleCount: errors.count, issues: errors.messages, limitReached: limited)
    }
}

private final class ScanErrors {
    var count = 0
    var messages: [String] = []
}

public enum FileServiceError: Error, LocalizedError {
    case notDirectory, unreadable, changed, outsideScope, protectedItem, symbolicLink
    public var errorDescription: String? {
        switch self {
        case .notDirectory: "Bir klasör seçmelisin."
        case .unreadable: "Klasör okunamadı. Erişim iznini kontrol et."
        case .changed: "Öğe taramadan sonra değişti. Yeniden tarayıp seçmelisin."
        case .outsideScope: "Öğe seçilen tarama kapsamının dışında."
        case .protectedItem: "Bu sistem veya kullanıcı kök klasörü korunuyor."
        case .symbolicLink: "Bağlantı ya da bağlantı üzerinden erişilen öğe taşınmaz."
        }
    }
}

public struct FileTrashRequest: Sendable {
    public let url: URL
    public let identity: FileIdentity
    public let root: URL
    public let applicationBundle: Bool
    public init(url: URL, identity: FileIdentity, root: URL, applicationBundle: Bool = false) {
        self.url = url; self.identity = identity; self.root = root; self.applicationBundle = applicationBundle
    }

    public func validate() throws {
        guard try canonicalFileURL(url).path == url.path, try canonicalFileURL(root).path == root.path,
              !identity.isSymbolicLink else { throw FileServiceError.symbolicLink }
        let prefixes = ["/System", "/usr", "/bin", "/sbin", "/private", "/dev"]
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protected = ["/", "/Users", "/Applications", "/Library", home.path,
                         home.appendingPathComponent("Library").path,
                         home.appendingPathComponent("Library/Caches").path,
                         home.appendingPathComponent("Library/Logs").path]
        if protected.contains(url.path) || prefixes.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) {
            // Owned test fixtures under the per-user temporary directory are valid scopes.
            let temporary = try canonicalFileURL(FileManager.default.temporaryDirectory).path
            guard !protected.contains(url.path), (root.path == temporary || root.path.hasPrefix(temporary + "/")),
                  url.path.hasPrefix(root.path + "/") else {
                throw FileServiceError.protectedItem
            }
        }
        let descendant = url.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") && url.path != root.path
        let appRoot = applicationBundle && url == root && url.pathExtension == "app"
            && Bundle(url: url)?.bundleIdentifier != nil
        guard descendant || appRoot else { throw FileServiceError.outsideScope }
        guard try FileIdentity.read(url) == identity else { throw FileServiceError.changed }
    }
}

public struct FileTrashResult: Identifiable, Sendable {
    public var id: String { source.path }
    public let source: URL
    public let trashURL: URL?
    public let error: String?
}

public actor FileTrashService {
    private let move: @Sendable (URL) throws -> URL
    public init() {
        move = { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            guard let destination else { throw FileServiceError.unreadable }
            return destination as URL
        }
    }
    init(move: @escaping @Sendable (URL) throws -> URL) { self.move = move }

    /// Each item is revalidated immediately before the recoverable Trash operation.
    public func trash(_ requests: [FileTrashRequest]) async -> [FileTrashResult] {
        var results: [FileTrashResult] = []
        for request in requests {
            if Task.isCancelled { break }
            do {
                try request.validate()
                results.append(.init(source: request.url, trashURL: try move(request.url), error: nil))
            } catch { results.append(.init(source: request.url, trashURL: nil, error: error.localizedDescription)) }
            await Task.yield()
        }
        return results
    }
}

public struct DuplicateFileGroup: Identifiable, Sendable {
    public let id: String
    public let files: [ScannedFile]
    public var duplicateBytes: Int64 { (files.first?.bytes ?? 0) * Int64(max(0, files.count - 1)) }
}

public actor DuplicateFinder {
    public init() {}
    public func groups(in files: [ScannedFile], progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> [DuplicateFileGroup] {
        let candidates = Dictionary(grouping: files.filter { $0.bytes > 0 }, by: \.bytes).values.filter { $0.count > 1 }.flatMap { $0 }
        var hashes: [String: [ScannedFile]] = [:]
        for (index, file) in candidates.enumerated() {
            try Task.checkCancellation()
            guard try FileIdentity.read(file.url) == file.identity else { continue }
            let handle = try FileHandle(forReadingFrom: file.url)
            var hasher = SHA256()
            do {
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation()
                    hasher.update(data: data)
                    await Task.yield()
                }
                try handle.close()
            } catch { try? handle.close(); throw error }
            guard try FileIdentity.read(file.url) == file.identity else { continue }
            let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            hashes[hash, default: []].append(file)
            await progress(index + 1, candidates.count)
        }
        return hashes.compactMap { hash, group in
            group.count > 1 ? DuplicateFileGroup(id: hash, files: group.sorted { $0.url.path < $1.url.path }) : nil
        }.sorted { $0.duplicateBytes > $1.duplicateBytes }
    }
}

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
    /// Nil scans all regular files; filtering precedes retention and byte totals.
    public var allowedExtensions: Set<String>? = nil
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
    /// Files inside packages; counted in totals but intentionally not listed.
    public var packagedFileCount = 0
    public var retainedAllFiles: Bool { files.count + packagedFileCount == fileCount }
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
        let allowedExtensions = options.allowedExtensions.map { Set($0.map { $0.lowercased() }) }
        let maximumEntries = max(1, options.maximumEntries)
        let retainedLimit = min(50_000, max(1, options.maximumRetainedFiles))
        let deadline = started.addingTimeInterval(max(0.1, min(300, options.maximumDuration)))
        var files: [ScannedFile] = []
        var folders: [String: FolderUsage] = [:]
        var seen = Set<String>()
        var visited = 0, fileCount = 0, skippedLinks = 0
        var bytes: Int64 = 0
        var limited = false
        var packagedFileCount = 0
        // DirectoryEnumerator's error callback is synchronous on this traversal.
        let errors = ScanErrors()
        let enumerationOptions: FileManager.DirectoryEnumerationOptions = options.includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: enumerationOptions, errorHandler: { url, error in
            errors.count += 1
            if errors.messages.count < 24 { errors.messages.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            return true
        }) else { throw FileServiceError.unreadable }
        // Enumeration is depth-first, so the innermost open package is a single prefix.
        var packagePrefix: String?
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if visited >= maximumEntries || Date() >= deadline { limited = true; break }
            visited += 1
            // Reported before any `continue`, so filtered scans still show progress.
            if visited.isMultiple(of: 128) {
                await progress(.init(visitedEntries: visited, fileCount: fileCount, bytes: bytes))
                await Task.yield()
            }
            if let prefix = packagePrefix, !url.path.hasPrefix(prefix) { packagePrefix = nil }
            do {
                let identity = try FileIdentity.read(url)
                if identity.isSymbolicLink { skippedLinks += 1; enumerator.skipDescendants(); continue }
                if identity.device != rootIdentity.device { enumerator.skipDescendants(); continue }
                if identity.isDirectory, packagePrefix == nil, Self.isPackage(url) { packagePrefix = url.path + "/" }
                guard identity.isRegularFile else { continue }
                if let extensions = allowedExtensions, !extensions.contains(url.pathExtension.lowercased()) { continue }
                guard seen.insert(identity.objectKey).inserted else { continue }
                let file = ScannedFile(url: url, identity: identity)
                // Package contents (.app, .photoslibrary, ...) count toward totals but are never offered
                // individually: trashing one resource inside a bundle corrupts the whole package.
                if packagePrefix == nil {
                    files.append(file)
                    if files.count > retainedLimit * 2 {
                        files.sort { $0.bytes > $1.bytes }
                        files.removeLast(files.count - retainedLimit)
                    }
                } else { packagedFileCount += 1 }
                fileCount += 1
                bytes = bytes.addingReportingOverflow(file.bytes).overflow ? Int64.max : bytes + file.bytes
                let relative = Array(url.pathComponents.dropFirst(root.pathComponents.count))
                if relative.count > 1, let first = relative.first {
                    if folders[first] == nil {
                        let folderURL = root.appendingPathComponent(first, isDirectory: true)
                        folders[first] = FolderUsage(url: folderURL, identity: try FileIdentity.read(folderURL), bytes: 0, fileCount: 0)
                    }
                    folders[first]?.bytes += file.bytes
                    folders[first]?.fileCount += 1
                }
            } catch {
                errors.count += 1
                if errors.messages.count < 24 { errors.messages.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        try Task.checkCancellation()
        files.sort { $0.bytes > $1.bytes }
        if files.count > retainedLimit { files.removeLast(files.count - retainedLimit) }
        await progress(.init(visitedEntries: visited, fileCount: fileCount, bytes: bytes))
        return FileScanReport(root: root, scannedAt: started, files: files,
                              folders: folders.values.sorted { $0.bytes > $1.bytes },
                              fileCount: fileCount, bytes: bytes, skippedLinks: skippedLinks,
                              inaccessibleCount: errors.count, issues: errors.messages, limitReached: limited,
                              packagedFileCount: packagedFileCount)
    }

    static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }
}

private final class ScanErrors {
    var count = 0
    var messages: [String] = []
}

public enum FileServiceError: Error, LocalizedError {
    case notDirectory, unreadable, changed, outsideScope, protectedItem, symbolicLink, insidePackage
    public var errorDescription: String? {
        switch self {
        case .notDirectory: String(localized: "Bir klasör seçmelisin.")
        case .unreadable: String(localized: "Klasör okunamadı. Erişim iznini kontrol et.")
        case .changed: String(localized: "Öğe taramadan sonra değişti. Yeniden tarayıp seçmelisin.")
        case .outsideScope: String(localized: "Öğe seçilen tarama kapsamının dışında.")
        case .protectedItem: String(localized: "Bu sistem veya kullanıcı kök klasörü korunuyor.")
        case .symbolicLink: String(localized: "Bağlantı ya da bağlantı üzerinden erişilen öğe taşınmaz.")
        case .insidePackage: String(localized: "Paket içindeki tek bir öğe taşınmaz; paketin bütünlüğü bozulur.")
        }
    }
}

public struct FileTrashRequest: Sendable {
    public let url: URL
    public let identity: FileIdentity
    public let root: URL
    public let applicationBundle: Bool
    public init(url: URL, identity: FileIdentity, root: URL, applicationBundle: Bool = false) {
        self.url = url
        self.identity = identity
        self.root = root
        self.applicationBundle = applicationBundle
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
        if descendant {
            var ancestor = url.deletingLastPathComponent()
            while ancestor.path.count > root.path.count, ancestor.path.hasPrefix(root.path) {
                if FileScanner.isPackage(ancestor) { throw FileServiceError.insidePackage }
                ancestor = ancestor.deletingLastPathComponent()
            }
        }
        guard try FileIdentity.read(url) == identity else { throw FileServiceError.changed }
    }
}

public struct FileTrashResult: Identifiable, Sendable {
    public var id: String { source.path }
    public let source: URL
    /// Where the item went in the Trash; nil when it was deleted permanently or the removal failed.
    public let trashURL: URL?
    public let error: String?
    public let mode: RemovalMode
    /// The removal failed only for lack of permission; an administrator retry would be allowed to delete it.
    public let permissionDenied: Bool
    public var succeeded: Bool { error == nil }
    public init(source: URL, trashURL: URL?, error: String?, mode: RemovalMode = .moveToTrash, permissionDenied: Bool = false) {
        self.source = source
        self.trashURL = trashURL
        self.error = error
        self.mode = mode
        self.permissionDenied = permissionDenied
    }
}

/// Removes validated items, either recoverably (Trash) or for good.
public actor FileTrashService {
    private let move: @Sendable (URL) throws -> URL
    private let delete: @Sendable (URL) throws -> Void
    private let administrator: AdministratorRemover

    public init() {
        move = { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            guard let destination else { throw FileServiceError.unreadable }
            return destination as URL
        }
        delete = { try FileManager.default.removeItem(at: $0) }
        administrator = AdministratorRemover()
    }
    init(move: @escaping @Sendable (URL) throws -> URL,
         delete: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         administrator: AdministratorRemover = AdministratorRemover()) {
        self.move = move
        self.delete = delete
        self.administrator = administrator
    }

    /// Each item is revalidated immediately before the recoverable Trash operation.
    public func trash(_ requests: [FileTrashRequest]) async -> [FileTrashResult] {
        await remove(requests, mode: .moveToTrash)
    }

    /// Each item is revalidated immediately before it is removed. With `administratorPrompt`, items that fail
    /// only for lack of permission are retried together as root after one password prompt. Only permanent
    /// deletion is ever retried that way: the Trash stays recoverable or fails.
    public func remove(_ requests: [FileTrashRequest], mode: RemovalMode,
                       administratorPrompt: String? = nil, launchdLabels: [String] = []) async -> [FileTrashResult] {
        var results: [FileTrashResult] = []
        var needsAdministrator: [FileTrashRequest] = []
        for request in requests {
            if Task.isCancelled { break }
            do {
                try request.validate()
                switch mode {
                case .moveToTrash:
                    results.append(.init(source: request.url, trashURL: try move(request.url), error: nil, mode: mode))
                case .deletePermanently:
                    try delete(request.url)
                    results.append(.init(source: request.url, trashURL: nil, error: nil, mode: mode))
                }
            } catch {
                let denied = FileRemovalClassifier.isPermissionFailure(error)
                if administratorPrompt != nil, mode == .deletePermanently, denied {
                    needsAdministrator.append(request)
                } else {
                    results.append(.init(source: request.url, trashURL: nil, error: error.localizedDescription, mode: mode,
                                         permissionDenied: denied))
                }
            }
            await Task.yield()
        }
        if let administratorPrompt, !needsAdministrator.isEmpty {
            results += await removeAsAdministrator(needsAdministrator, prompt: administratorPrompt, launchdLabels: launchdLabels)
        }
        return results
    }

    private func removeAsAdministrator(_ requests: [FileTrashRequest], prompt: String, launchdLabels: [String]) async -> [FileTrashResult] {
        // Identity may have changed while the first pass ran; only still-valid items reach the root shell.
        var valid: [FileTrashRequest] = []
        var results: [FileTrashResult] = []
        for request in requests {
            do { try request.validate(); valid.append(request) }
            catch { results.append(.init(source: request.url, trashURL: nil, error: error.localizedDescription, mode: .deletePermanently)) }
        }
        guard !valid.isEmpty else { return results }
        do {
            let outcome = try await administrator.remove(valid.map(\.url), launchdLabels: launchdLabels, prompt: prompt)
            let remaining = Set(outcome.remaining.map(\.path))
            let reason = outcome.diagnostic.flatMap { $0.isEmpty ? nil : $0 } ?? FileRemovalError.stillExists.localizedDescription
            results += valid.map { request in
                remaining.contains(request.url.path)
                    ? .init(source: request.url, trashURL: nil, error: FileRemovalError.administratorFailed(reason).localizedDescription, mode: .deletePermanently)
                    : .init(source: request.url, trashURL: nil, error: nil, mode: .deletePermanently)
            }
        } catch {
            results += valid.map { .init(source: $0.url, trashURL: nil, error: error.localizedDescription, mode: .deletePermanently) }
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
            // One unreadable, vanished or cloud-only file must not discard the whole comparison.
            if let hash = try await Self.hash(file) { hashes[hash, default: []].append(file) }
            await progress(index + 1, candidates.count)
        }
        return hashes.compactMap { hash, group in
            group.count > 1 ? DuplicateFileGroup(id: hash, files: group.sorted { $0.url.path < $1.url.path }) : nil
        }.sorted { $0.duplicateBytes > $1.duplicateBytes }
    }

    /// Nil when the file changed, is unreadable, or is an iCloud placeholder (reading would download it).
    private static func hash(_ file: ScannedFile) async throws -> String? {
        var info = stat()
        guard lstat(file.url.path, &info) == 0, info.st_flags & datalessFlag == 0,
              (try? FileIdentity.read(file.url)) == file.identity,
              let handle = try? FileHandle(forReadingFrom: file.url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
                await Task.yield()
            }
        } catch is CancellationError { throw CancellationError() }
        catch { return nil }
        guard (try? FileIdentity.read(file.url)) == file.identity else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// SF_DATALESS from <sys/stat.h>; not exported to Swift.
    private static let datalessFlag: UInt32 = 0x4000_0000
}

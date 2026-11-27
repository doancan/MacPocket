import Darwin
import Foundation

/// Write beside the destination, then commit with an exclusive rename. A concurrent same-name file is
/// preserved.
public enum ScreenshotFileWriter {
    public static func write(_ data: Data, folder: URL, date: Date, prefix: String, format: ScreenshotFormat) throws -> URL {
        try Task.checkCancellation()
        guard folder.isFileURL, !prefix.isEmpty, !prefix.contains("/"), !prefix.contains("\0"), prefix.utf8.count <= 128 else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".MacPocket-\(UUID().uuidString).tmp")
        let descriptor = temporary.withUnsafeFileSystemRepresentation { path in path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) } ?? -1 }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var opened = true
        defer { if opened { Darwin.close(descriptor) }; try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard Darwin.close(descriptor) == 0 else { opened = false; throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        opened = false
        for _ in 0..<100 {
            try Task.checkCancellation()
            let destination = ScreenshotFiles.url(in: folder, at: date, prefix: prefix, format: format) { FileManager.default.fileExists(atPath: $0.path) }
            let result = temporary.withUnsafeFileSystemRepresentation { from in
                destination.withUnsafeFileSystemRepresentation { to in
                    guard let from, let to else { return Int32(-1) }
                    return renameatx_np(AT_FDCWD, from, AT_FDCWD, to, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return destination }
            if errno != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

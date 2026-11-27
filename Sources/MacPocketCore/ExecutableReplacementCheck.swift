import Foundation

/// Notices when the executable a long-running process was started from has been replaced on disk.
///
/// launchd starts the privileged helper on demand and never stops it, so after an app update it would keep
/// running the old code — and the old code-signing requirement for its clients — until the Mac restarts.
/// Comparing the file's identity catches both a delete-and-copy reinstall and an update that moves the old
/// bundle away.
public struct ExecutableReplacementCheck: Sendable {
    public let url: URL
    private let original: FileIdentity

    public init(url: URL) throws {
        self.url = url
        original = try FileIdentity.read(url)
    }

    public static func currentProcess() throws -> Self {
        let path = ProcessMonitor.executablePath(pid: getpid())
        guard !path.isEmpty else { throw POSIXError(.ENOENT) }
        return try Self(url: URL(fileURLWithPath: path))
    }

    /// A file that can no longer be read counts as replaced: the bundle it belonged to is gone.
    public var isReplaced: Bool {
        guard let current = try? FileIdentity.read(url) else { return true }
        return current != original
    }
}

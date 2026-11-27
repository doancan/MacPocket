import Foundation

public struct CodexAuth: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String?
    public let expiresAt: Date?

    public init(accessToken: String, accountID: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.expiresAt = expiresAt
    }
}

public protocol CodexAuthReader: Sendable {
    func readCodexAuth() throws -> CodexAuth
}

public struct FileCodexAuthReader: CodexAuthReader {
    private let fileURL: URL

    public init(fileURL: URL = FileCodexAuthReader.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL { defaultURL(environment: ProcessInfo.processInfo.environment) }

    public static func defaultURL(environment: [String: String]) -> URL {
        let home = environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        return home.appendingPathComponent("auth.json")
    }

    public func readCodexAuth() throws -> CodexAuth {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { throw TokenReaderError.notFound }
        // Only a small regular file: a named pipe would block the read and a huge file would fill memory.
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size <= Self.maximumSize,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { throw TokenReaderError.accessDenied }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumSize + 1), data.count <= Self.maximumSize else {
            throw TokenReaderError.accessDenied
        }
        return try CodexCredentials.parse(data)
    }

    static let maximumSize = 256 * 1024
}

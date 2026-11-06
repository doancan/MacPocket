import Foundation
import Security
import LocalAuthentication
import CryptoKit
import UsageCore

public struct ClaudeKeychainEntry: Identifiable, Equatable, Sendable {
    public let service: String
    public let account: String
    public var id: String { service + ":" + account }
}

public enum AIUsageCredentials {
    /// Only attributes are requested; no passwords/tokens and no authentication UI.
    public static func claudeEntries() -> [ClaudeKeychainEntry] {
        #if DEBUG
        if AIUsageFixtures.requested { return [] }
        #endif
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let entries = result as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let service = entry[kSecAttrService as String] as? String,
                  service.hasPrefix("Claude Code-credentials"),
                  let account = entry[kSecAttrAccount as String] as? String else { return nil }
            return ClaudeKeychainEntry(service: service, account: account)
        }.sorted { $0.service < $1.service }
    }

    public static func claudeServiceCandidate(directory: String) -> String {
        let digest = SHA256.hash(data: Data(directory.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + digest.prefix(8)
    }

    /// The service is bound only to the directory-specific namespace seen in metadata. A changed CLI
    /// naming convention never falls back to a different account's keychain entry.
    struct ProfileReader: TokenReader {
        let directory: String
        let service: String?
        func readClaudeToken() throws -> ClaudeToken {
            if let service {
                do { return try SecurityCLITokenReader(service: service, run: boundedSecurityRead).readClaudeToken() }
                catch TokenReaderError.notFound { /* macOS can fall back to a profile credential file. */ }
            } else {
                let candidate = AIUsageCredentials.claudeServiceCandidate(directory: directory)
                if AIUsageCredentials.claudeEntries().contains(where: { $0.service == candidate }) {
                    return try SecurityCLITokenReader(service: candidate, run: boundedSecurityRead).readClaudeToken()
                }
            }
            return try ClaudeFileReader(fileURL: URL(fileURLWithPath: directory).appending(path: ".credentials.json")).readClaudeToken()
        }
    }

    public struct ClaudeFileReader: TokenReader {
        public let fileURL: URL
        public init(fileURL: URL) { self.fileURL = fileURL }
        public func readClaudeToken() throws -> ClaudeToken {
            let data = try readPrivateFile(fileURL)
            struct Credential: Decodable { struct OAuth: Decodable { let accessToken: String; let expiresAt: Double? }; let claudeAiOauth: OAuth }
            guard let decoded = try? JSONDecoder().decode(Credential.self, from: data),
                  !decoded.claudeAiOauth.accessToken.isEmpty else { throw TokenReaderError.malformed }
            return ClaudeToken(accessToken: decoded.claudeAiOauth.accessToken,
                expiresAt: decoded.claudeAiOauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) })
        }
    }

    static func readPrivateFile(_ url: URL) throws -> Data {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard FileManager.default.fileExists(atPath: url.path) else { throw TokenReaderError.notFound }
        guard values?.isRegularFile == true, let size = values?.fileSize, size <= 256 * 1024,
              let handle = try? FileHandle(forReadingFrom: url) else { throw TokenReaderError.accessDenied }
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 256 * 1024 + 1), data.count <= 256 * 1024 else { throw TokenReaderError.malformed }
        return data
    }

    static let boundedSecurityRead: SecurityCLITokenReader.Runner = { executable, arguments in
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning, process.processIdentifier > 1 { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        defer { watchdog.cancel() }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 16 * 1024), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 256 * 1024 { process.terminate(); throw TokenReaderError.malformed }
        }
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}

public enum AIUsageProviderFactory {
    public static func make(_ account: AIUsageAccount, warning: Double, critical: Double) -> any UsageProvider {
        let http = AIUsageHTTPClient()
        switch account.source {
        case .claudeKeychain(let service, let user):
            return ClaudeUsageProvider(tokenReader: SecurityCLITokenReader(service: service, account: user, run: AIUsageCredentials.boundedSecurityRead),
                httpClient: http, baseURL: URL(string: "https://api.anthropic.com")!, warningThreshold: warning, criticalThreshold: critical)
        case .claudeProfile(let directory, let service):
            return ClaudeUsageProvider(tokenReader: AIUsageCredentials.ProfileReader(directory: directory, service: service),
                httpClient: http, baseURL: URL(string: "https://api.anthropic.com")!, warningThreshold: warning, criticalThreshold: critical)
        case .codexFile(let path):
            return OpenAIUsageProvider(authReader: FileCodexAuthReader(fileURL: URL(fileURLWithPath: path)),
                httpClient: http, baseURL: URL(string: "https://chatgpt.com")!, warningThreshold: warning, criticalThreshold: critical)
        case .grokFile(let path):
            let url = URL(fileURLWithPath: path)
            return XAIUsageProvider(authReader: FileGrokAuthReader(fileURL: url), httpClient: http,
                versionURL: url.deletingLastPathComponent().appending(path: "version.json"), warningThreshold: warning, criticalThreshold: critical)
        }
    }
}

public final class AIUsageHTTPClient: NSObject, UsageHTTPClient, URLSessionTaskDelegate, @unchecked Sendable {
    public static let allowedURLs: Set<String> = ["https://api.anthropic.com/api/oauth/usage", "https://chatgpt.com/backend-api/wham/usage", "https://cli-chat-proxy.grok.com/v1/billing?format=credits"]
    private func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil; c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCredentialStorage = nil
        c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 30
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }
    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard Self.allowedURLs.contains(url.absoluteString) else { throw URLError(.unsupportedURL) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { bytes.task.cancel(); throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 512 * 1024 else { bytes.task.cancel(); throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, response)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? { nil }
}

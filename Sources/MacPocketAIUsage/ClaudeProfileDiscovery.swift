import Foundation

public struct ClaudeProfileFolder: Identifiable, Equatable, Sendable {
    public let directory: URL
    public let name: String
    public let isDefault: Bool
    public var id: String { directory.path }
}

public struct ClaudeProfileSearchResult: Sendable {
    public var folders: [ClaudeProfileFolder]
    public var incomplete: Bool
}

/// Searches a few bounded, local locations using filenames and directory attributes only.
/// Never opens credentials, launches a shell or recursively searches the home directory.
public enum ClaudeProfileDiscovery {
    public static func folderURL(_ text: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = path == "~" ? home.path : path.hasPrefix("~/") ? home.appending(path: String(path.dropFirst(2))).path : path
        guard AIUsageSource.claudeProfile(directory: expanded, service: nil).isValid else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            accounts: [AIUsageAccount] = []) -> ClaudeProfileSearchResult {
        let fm = FileManager.default, defaultFolder = home.appending(path: ".claude")
        var found: [String: ClaudeProfileFolder] = [:], incomplete = false
        let markers = [".credentials.json", "settings.json", ".claude.json", "history.jsonl", "projects"]
        func isDirectory(_ url: URL) -> Bool {
            var directory: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
        func add(_ url: URL, name: String? = nil) {
            guard !Task.isCancelled, isDirectory(url) else { return }
            let key = canonical(url), isDefault = key == canonical(defaultFolder)
            guard found[key] == nil else { return }
            found[key] = ClaudeProfileFolder(directory: url.standardizedFileURL,
                name: name ?? (isDefault ? String(localized: "Varsayılan Claude Code oturumu") : url.lastPathComponent), isDefault: isDefault)
        }
        func children(_ root: URL) -> [URL] {
            guard !Task.isCancelled, isDirectory(root) else { return [] }
            do { return Array(try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
                .sorted { $0.path < $1.path }.prefix(256)) }
            catch { incomplete = true; return [] }
        }
        // Preserve actual configured paths (and their keychain namespace), even when symlinked.
        if let path = environment["CLAUDE_CONFIG_DIR"], let url = folderURL(path, home: home) { add(url) }
        for account in accounts {
            if case .claudeProfile(let directory, _) = account.source { add(URL(fileURLWithPath: directory), name: account.name) }
        }
        add(defaultFolder)
        for url in children(home) where url.lastPathComponent.lowercased().hasPrefix(".claude") {
            if markers.contains(where: { fm.fileExists(atPath: url.appending(path: $0).path) }) { add(url) }
            if url.lastPathComponent.lowercased().contains("profiles") {
                for child in children(url) where markers.contains(where: { fm.fileExists(atPath: child.appending(path: $0).path) }) { add(child) }
            }
        }
        let profiles = home.appending(path: "Library/Application Support/MacPocket/AIUsage/ClaudeProfiles")
        for url in children(profiles) { add(url) }
        let sorted = found.values.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return $0.directory.path < $1.directory.path
        }
        return ClaudeProfileSearchResult(folders: Array(sorted.prefix(64)), incomplete: incomplete || sorted.count > 64)
    }

    /// The CLI's default session uses the unsuffixed keychain entry; a custom profile never does.
    public static func source(for folder: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              entries: [ClaudeKeychainEntry], username: String = NSUserName()) -> AIUsageSource {
        let expected = AIUsageCredentials.claudeServiceCandidate(directory: folder.path)
        if entries.contains(where: { $0.service == expected }) { return .claudeProfile(directory: folder.path, service: expected) }
        if folder.resolvingSymlinksInPath() == home.appending(path: ".claude").resolvingSymlinksInPath() {
            if let entry = entries.first(where: { $0.service == "Claude Code-credentials" && $0.account == username }) {
                return .claudeKeychain(service: entry.service, account: entry.account)
            }
            if !FileManager.default.fileExists(atPath: folder.appending(path: ".credentials.json").path) {
                return .claudeKeychain(service: "Claude Code-credentials", account: username)
            }
        }
        return .claudeProfile(directory: folder.path, service: nil)
    }
}

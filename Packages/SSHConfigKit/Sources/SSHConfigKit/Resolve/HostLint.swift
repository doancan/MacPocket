import Foundation

public enum HostIssue: Equatable, Sendable {
    /// The IdentityFile value as written.
    case missingIdentityFile(String)
    /// Several blocks name this alias; ssh uses the first block's values and later ones only add what is
    /// missing.
    case duplicateAlias(alias: String, isFirst: Bool)
    /// Another block names this alias differing only in letter case; ssh treats them as different hosts.
    case duplicateAliasCaseOnly(alias: String)
    case unencryptedKey(String)
    /// The private key can be read by other users; ssh refuses to use such a key.
    case keyPermissionsTooOpen(String)
    /// The private key sits in a folder a cloud service syncs (iCloud Drive, Dropbox, …), so it leaves this Mac.
    case keyInSyncedFolder(String)
}

/// Problems a person would want to see next to a host. File access is injected so tests never
/// touch the disk; the app passes FileManager and KeyFileInspector.
public struct HostLint: Sendable {
    private let home: URL
    private let fileExists: @Sendable (URL) -> Bool
    private let encryption: @Sendable (URL) -> KeyEncryption
    private let permissions: @Sendable (URL) -> UInt16?

    /// `permissions` returns the file's mode bits (`0o600`), nil when unknown; it defaults to "unknown" so
    /// callers that do not care about permissions (and tests) stay unchanged.
    public init(home: URL, fileExists: @escaping @Sendable (URL) -> Bool, encryption: @escaping @Sendable (URL) -> KeyEncryption,
                permissions: @escaping @Sendable (URL) -> UInt16? = { _ in nil }) {
        self.home = home
        self.fileExists = fileExists
        self.encryption = encryption
        self.permissions = permissions
    }

    /// Folders whose contents a cloud service uploads. Path-only: no disk access.
    public static func isSyncedFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Library/Mobile Documents/") || path.contains("/Library/CloudStorage/")
    }

    private static func plainNames(of entry: HostEntry) -> [String] {
        entry.patterns.filter { !$0.hasPrefix("!") && !$0.contains("*") && !$0.contains("?") }
    }

    /// Non-pattern names (ASCII-lowercased) that appear in more than one Host block: the "likely mistake"
    /// count.
    public static func duplicateCounts(document: ConfigDocument, included: [IncludedHost]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in document.hosts + included.map(\.entry) {
            for name in Set(plainNames(of: entry).map(\.asciiLowercased)) { counts[name, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }
    }

    /// Non-pattern names, exactly as written, that appear in more than one Host block (what ssh really
    /// merges).
    public static func exactDuplicateCounts(document: ConfigDocument, included: [IncludedHost]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in document.hosts + included.map(\.entry) {
            for name in Set(plainNames(of: entry)) { counts[name, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }
    }

    /// For each exact non-wildcard name, the `headerLine` of the first root-file block naming it.
    public static func firstBlocks(document: ConfigDocument) -> [String: Int] {
        var first: [String: Int] = [:]
        for entry in document.hosts {
            for name in plainNames(of: entry) where first[name] == nil {
                first[name] = entry.headerLine
            }
        }
        return first
    }

    /// `entry` must be a root-file block. `duplicates` are the ASCII-folded counts, `exactDuplicates` the
    /// counts of names exactly as written and `firstBlocks` the exact-name map, from the static helpers
    /// above. A name another block repeats exactly gets first/later; a name only case variants share gets the
    /// case-only issue.
    public func issues(for entry: HostEntry, duplicates: [String: Int], exactDuplicates: [String: Int],
                       firstBlocks: [String: Int]) -> [HostIssue] {
        var result: [HostIssue] = []
        var seen: Set<String> = []
        for name in Self.plainNames(of: entry) {
            guard duplicates[name.asciiLowercased] != nil, seen.insert(name).inserted else { continue }
            if exactDuplicates[name] != nil {
                result.append(.duplicateAlias(alias: name, isFirst: firstBlocks[name] == entry.headerLine))
            } else {
                result.append(.duplicateAliasCaseOnly(alias: name))
            }
        }
        for value in entry.values(for: "IdentityFile") {
            if value.asciiLowercased == "none" { continue }
            guard let url = KeyUsage.resolve(value, home: home) else { continue }
            if !fileExists(url) {
                result.append(.missingIdentityFile(value))
            } else {
                let kind = encryption(url)
                if kind == .unencrypted { result.append(.unencryptedKey(value)) }
                // Only files that really are private keys: a mistyped IdentityFile must not get key advice.
                if kind != .unknown {
                    if let mode = permissions(url), mode & 0o077 != 0 { result.append(.keyPermissionsTooOpen(value)) }
                    if Self.isSyncedFolder(url.resolvingSymlinksInPath()) || Self.isSyncedFolder(url) { result.append(.keyInSyncedFolder(value)) }
                }
            }
        }
        return result
    }
}

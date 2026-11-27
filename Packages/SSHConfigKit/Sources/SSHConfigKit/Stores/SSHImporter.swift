import Foundation

/// One private key found in the folder being imported and what importing it will do.
public struct ImportKey: Identifiable, Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        /// Copied under its own name.
        case copy
        /// The destination already holds a byte-identical key: nothing to copy, hosts keep the name.
        case alreadyPresent
        /// The name is taken by a different key: copied under `name` instead and the hosts are rewritten.
        case renamed(to: String)
    }

    public let source: URL
    public let publicSource: URL?
    public let disposition: Disposition
    public var id: String { source.path }
    public var name: String { source.lastPathComponent }
}

/// A host block that will be added to the active configuration.
public struct ImportHost: Identifiable, Equatable, Sendable {
    public let draft: HostDraft
    public let group: String?
    /// The file it came from when it is not the root config (an `Include`d file); it is flattened on import.
    public let origin: URL?
    public var id: String { draft.patterns.joined(separator: " ") }
}

/// What importing a folder or config file would do, computed without touching anything.
public struct SSHImportPlan: Equatable, Sendable {
    public var hosts: [ImportHost] = []
    public var skippedHosts: [String] = []
    public var keys: [ImportKey] = []
    /// Things the user should know: unreadable files, iCloud files that are not downloaded yet, Match blocks.
    public var warnings: [ImportWarning] = []
    public let sourceConfig: URL?
    public let sourceDirectory: URL

    public var isEmpty: Bool { hosts.isEmpty && keys.allSatisfy { $0.disposition == .alreadyPresent } }
}

public enum ImportWarning: Equatable, Sendable {
    case noConfigFound
    case unreadable(String)
    case notDownloaded(String)
    case notUTF8(String)
    case matchBlocksSkipped(Int)
    case missingKey(host: String, path: String)
}

public struct ImportResult: Equatable, Sendable {
    public var copiedKeys: [String] = []
    public var addedHosts: [String] = []
}

/// Brings hosts and keys from another Mac's `~/.ssh` (or any folder or config file, for example one kept in
/// iCloud Drive) into this one. Planning only reads; applying copies keys with the permissions ssh requires,
/// never overwrites an existing file, and leaves the host edits to the caller so they go through the normal
/// diff, validation and backup of a save.
public struct SSHImporter: Sendable {
    private let home: URL
    private let destination: URL

    /// - Parameters:
    ///   - home: the user's home; `~` in imported IdentityFile values resolves here.
    ///   - destination: the directory keys are copied into (`~/.ssh`).
    public init(home: URL, destination: URL) {
        self.home = home
        self.destination = destination
    }

    // MARK: Planning

    /// - Parameters:
    ///   - source: a folder (a copy of `.ssh`) or a config file.
    ///   - document: the active configuration; aliases it or its `Include`s already define are skipped.
    ///   - existingAliases: aliases from the active configuration's included files.
    public func plan(source: URL, into document: ConfigDocument, existingAliases: Set<String> = []) -> SSHImportPlan {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: source.path, isDirectory: &isDirectory)
        let directory = isDirectory.boolValue ? source : source.deletingLastPathComponent()
        let configFile: URL? = isDirectory.boolValue ? Self.configFile(in: directory) : source
        var plan = SSHImportPlan(sourceConfig: configFile, sourceDirectory: directory)
        var warnings: [ImportWarning] = []

        let cloudPlaceholders = Self.cloudPlaceholders(in: directory)
        warnings += cloudPlaceholders.map { .notDownloaded($0) }

        // Keys first: hosts are rewritten against what the key plan decided.
        plan.keys = discoverKeys(in: directory, warnings: &warnings)

        let known = Set(document.hosts.flatMap(\.patterns)).union(existingAliases)
        var seen = Set<String>()
        if let configFile {
            switch Self.readText(configFile) {
            case .success(let text):
                let root = ConfigDocument(parsing: text)
                let resolver = IncludeResolver(homeDirectory: home, relativeBase: directory)
                var entries = root.hosts.map { SourceHost(entry: $0, group: root.group(ofHostAt: $0.headerLine), origin: nil) }
                for included in resolver.includedHosts(of: root, rootFile: configFile) {
                    entries.append(SourceHost(entry: included.entry, group: nil, origin: included.file))
                }
                warnings.append(contentsOf: Self.matchWarning(root))
                for source in entries where !source.entry.isPattern {
                    let (entry, group, origin) = (source.entry, source.group, source.origin)
                    let alias = entry.patterns.joined(separator: " ")
                    guard !known.contains(entry.alias), seen.insert(alias).inserted else {
                        plan.skippedHosts.append(alias)
                        continue
                    }
                    let draft = HostDraft(patterns: entry.patterns, directives: rewrittenDirectives(of: entry, keys: plan.keys, warnings: &warnings))
                    plan.hosts.append(ImportHost(draft: draft, group: group, origin: origin))
                }
            case .failure(.unreadable):
                warnings.append(.unreadable(configFile.path))
            case .failure(.notUTF8):
                warnings.append(.notUTF8(configFile.path))
            }
        } else if plan.keys.isEmpty {
            warnings.append(.noConfigFound)
        }
        plan.warnings = warnings
        return plan
    }

    static func configFile(in directory: URL) -> URL? {
        for name in ["config", "ssh_config", "config.txt"] {
            let url = directory.appending(path: name)
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return url }
        }
        let nested = directory.appending(path: ".ssh/config")
        if (try? nested.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return nested }
        return nil
    }

    private struct SourceHost {
        let entry: HostEntry
        let group: String?
        let origin: URL?
    }

    private enum ReadFailure: Error { case unreadable, notUTF8 }

    private static func readText(_ url: URL) -> Result<String, ReadFailure> {
        guard let data = try? RegularFile.read(url, limit: 4 << 20) else { return .failure(.unreadable) }
        guard let text = String(validating: data, as: UTF8.self) else { return .failure(.notUTF8) }
        return .success(text)
    }

    private static func matchWarning(_ document: ConfigDocument) -> [ImportWarning] {
        document.matches.isEmpty ? [] : [.matchBlocksSkipped(document.matches.count)]
    }

    /// `~/Library/Mobile Documents` files not yet downloaded appear as hidden `.name.icloud` stubs.
    static func cloudPlaceholders(in directory: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasPrefix(".") && $0.hasSuffix(".icloud") }
            .map { String($0.dropFirst().dropLast(".icloud".count)) }.sorted()
    }

    private func discoverKeys(in directory: URL, warnings: inout [ImportWarning]) -> [ImportKey] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        let visible = names.filter { !$0.hasPrefix(".") }.sorted()
        let set = Set(visible)
        var keys: [ImportKey] = []
        var taken = Set<String>()
        for name in visible where !name.hasSuffix(".pub") && !Self.nonKeyNames.contains(name) {
            let url = directory.appending(path: name)
            guard let head = try? KeyFileInspector.readHead(of: url), KeyFileInspector.isPrivateKeyHeader(head) else { continue }
            let publicURL = set.contains(name + ".pub") ? directory.appending(path: name + ".pub") : nil
            let disposition = disposition(for: url, name: name, taken: &taken)
            keys.append(ImportKey(source: url, publicSource: publicURL, disposition: disposition))
        }
        return keys
    }

    private static let nonKeyNames: Set<String> = ["config", "known_hosts", "authorized_keys", "environment"]

    private func disposition(for source: URL, name: String, taken: inout Set<String>) -> ImportKey.Disposition {
        let fm = FileManager.default
        let target = destination.appending(path: name)
        if fm.fileExists(atPath: target.path) {
            if let a = try? RegularFile.read(source, limit: nil), let b = try? RegularFile.read(target, limit: nil), a == b {
                taken.insert(name)
                return .alreadyPresent
            }
            var candidate = 2
            var alternative = "\(name)_\(candidate)"
            while fm.fileExists(atPath: destination.appending(path: alternative).path)
                    || fm.fileExists(atPath: destination.appending(path: alternative + ".pub").path) || taken.contains(alternative) {
                candidate += 1
                alternative = "\(name)_\(candidate)"
            }
            taken.insert(alternative)
            return .renamed(to: alternative)
        }
        if taken.contains(name) { return .alreadyPresent }
        taken.insert(name)
        return .copy
    }

    /// IdentityFile values that name an imported key are pointed at the copy in the destination; values that
    /// name nothing we have are kept and reported.
    private func rewrittenDirectives(of entry: HostEntry, keys: [ImportKey], warnings: inout [ImportWarning]) -> [DraftDirective] {
        let byName = Dictionary(keys.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return entry.directives.map { directive in
            guard directive.key.asciiLowercased == "identityfile" else { return DraftDirective(key: directive.key, value: directive.value) }
            let name = (directive.value as NSString).lastPathComponent
            guard let key = byName[name] else {
                if !FileManager.default.fileExists(atPath: expand(directive.value).path) {
                    warnings.append(.missingKey(host: entry.alias, path: directive.value))
                }
                return DraftDirective(key: directive.key, value: directive.value)
            }
            let finalName: String
            if case .renamed(let to) = key.disposition { finalName = to } else { finalName = name }
            return DraftDirective(key: directive.key, value: displayPath(destination.appending(path: finalName)))
        }
    }

    private func expand(_ value: String) -> URL {
        KeyUsage.resolve(value, home: home) ?? URL(filePath: value)
    }

    private func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        return path.hasPrefix(base + "/") ? "~" + path.dropFirst(base.count) : path
    }

    // MARK: Applying

    /// Copies the keys of `plan`. Throws on the first failure; keys already copied stay (they are inert files).
    public func copyKeys(of plan: SSHImportPlan) throws -> [String] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        var copied: [String] = []
        for key in plan.keys {
            let name: String
            switch key.disposition {
            case .alreadyPresent: continue
            case .copy: name = key.name
            case .renamed(let to): name = to
            }
            let target = destination.appending(path: name)
            try write(source: key.source, to: target, mode: 0o600)
            if let pub = key.publicSource {
                let publicTarget = destination.appending(path: name + ".pub")
                if !fm.fileExists(atPath: publicTarget.path) { try write(source: pub, to: publicTarget, mode: 0o644) }
            }
            copied.append(name)
        }
        return copied
    }

    /// Creates `target` exclusively (never replaces) with the final mode from the start, so a private key is
    /// never readable by others, even for a moment.
    private func write(source: URL, to target: URL, mode: mode_t) throws {
        let data = try RegularFile.read(source, limit: nil)
        let fd = open(target.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    /// Adds the planned hosts (and their groups) to `document`; returns the aliases added.
    @discardableResult
    public static func addHosts(of plan: SSHImportPlan, to document: inout ConfigDocument) throws -> [String] {
        var added: [String] = []
        for host in plan.hosts {
            let header = try document.addHost(host.draft)
            if let group = host.group, !group.isEmpty { try document.setGroup(ofHostAt: header, to: group) }
            added.append(host.id)
        }
        return added
    }
}

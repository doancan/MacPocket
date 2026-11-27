import Foundation

/// What it takes for the system's own `ssh` (Terminal, VS Code Remote-SSH, git) to see a configuration the app
/// edits somewhere else, for example in iCloud Drive: a line in `~/.ssh/config` that includes it, and the
/// known_hosts entries it is missing.
public struct SystemLinkPlan: Equatable, Sendable {
    /// `~/.ssh/config` as it is now and as it would be; nil when the system config already reaches the file.
    public var configChange: (old: String, new: String)?
    public var configTarget: URL
    /// known_hosts lines of the app's file that `~/.ssh/known_hosts` lacks, in file order.
    public var knownHostsToAdd: [String] = []
    public var knownHostsTarget: URL
    /// Plain-language findings that are not changes: `~/.ssh` itself is a symlink, a target is not a regular file.
    public var notes: [SystemLinkNote] = []

    public var isNoop: Bool { configChange == nil && knownHostsToAdd.isEmpty }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configChange?.old == rhs.configChange?.old && lhs.configChange?.new == rhs.configChange?.new
            && lhs.configTarget == rhs.configTarget && lhs.knownHostsToAdd == rhs.knownHostsToAdd
            && lhs.knownHostsTarget == rhs.knownHostsTarget && lhs.notes == rhs.notes
    }
}

public enum SystemLinkNote: Error, Equatable, Sendable {
    /// `~/.ssh` is a symlink to this folder; writes land there.
    case sshDirectoryIsSymlink(String)
    /// `~/.ssh/config` is a symlink to this file; the include is written into the real file.
    case configIsSymlink(String)
    case unreadable(String)
    case notUTF8(String)
}

public struct SystemLinker: Sendable {
    private let home: URL
    private let writer: SafeFileWriter

    public init(home: URL, backups: BackupManager?) {
        self.home = home
        writer = SafeFileWriter(backups: backups)
    }

    private var systemConfig: URL { home.appending(path: ".ssh/config") }
    private var systemKnownHosts: URL { home.appending(path: ".ssh/known_hosts") }

    /// - Parameters:
    ///   - config: the configuration the app edits.
    ///   - knownHosts: the known_hosts file the app edits.
    public func plan(config: URL, knownHosts: URL) -> SystemLinkPlan {
        var plan = SystemLinkPlan(configTarget: systemConfig, knownHostsTarget: systemKnownHosts)
        plan.notes += symlinkNotes()

        if !KeyUsage.sameFile(config, systemConfig) {
            switch Self.read(systemConfig) {
            case .success(let old):
                let document = ConfigDocument(parsing: old)
                if !includes(document, file: config) {
                    plan.configChange = (old, withInclude(of: config, in: old))
                }
            case .failure(let note): plan.notes.append(note)
            }
        }

        if !KeyUsage.sameFile(knownHosts, systemKnownHosts) {
            switch (Self.read(knownHosts), Self.read(systemKnownHosts)) {
            case (.success(let theirs), .success(let ours)):
                let have = Set(ours.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) })
                var seen = Set<String>()
                plan.knownHostsToAdd = theirs.split(whereSeparator: { $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") && !have.contains($0) && seen.insert($0).inserted }
            case (.failure(let note), _), (_, .failure(let note)): plan.notes.append(note)
            }
        }
        return plan
    }

    /// Writes the plan through the safe writer: backup first, then an atomic replace. Each file is checked for
    /// concurrent changes against what the plan read.
    public func apply(_ plan: SystemLinkPlan) throws {
        let fm = FileManager.default
        let directory = home.appending(path: ".ssh")
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if let change = plan.configChange {
            try writer.write(change.new, to: plan.configTarget, expected: Self.fingerprint(of: change.old, at: plan.configTarget),
                             backupKind: "system-config")
        }
        if !plan.knownHostsToAdd.isEmpty {
            let old = (try? String(contentsOf: plan.knownHostsTarget, encoding: .utf8)) ?? ""
            let separator = old.isEmpty || old.hasSuffix("\n") ? "" : "\n"
            let new = old + separator + plan.knownHostsToAdd.joined(separator: "\n") + "\n"
            try writer.write(new, to: plan.knownHostsTarget, expected: Self.fingerprint(of: old, at: plan.knownHostsTarget),
                             backupKind: "system-known-hosts")
        }
    }

    /// The fingerprint a read of `text` had: nil when the file does not exist (nothing to conflict with).
    private static func fingerprint(of text: String, at url: URL) -> FileFingerprint? {
        FileManager.default.fileExists(atPath: url.path) ? FileFingerprint(data: Data(text.utf8)) : nil
    }

    // MARK: Pieces

    private func includeValue(for file: URL) -> String {
        let path = file.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        return path.hasPrefix(base + "/") ? "~" + path.dropFirst(base.count) : path
    }

    private func includes(_ document: ConfigDocument, file: URL) -> Bool {
        let resolver = IncludeResolver(homeDirectory: home)
        return document.includes.contains { include in
            include.paths.contains { pattern in
                resolver.resolvedFiles(for: pattern).contains { KeyUsage.sameFile($0, file) }
            }
        }
    }

    /// The include goes first: ssh keeps the first value it finds, so the shared file wins over later defaults.
    private func withInclude(of file: URL, in old: String) -> String {
        let line = "Include " + LineTokenizer.quotedIfNeeded(includeValue(for: file))
        let header = "# Added by MacPocket so ssh reads the configuration it manages."
        return header + "\n" + line + "\n" + (old.isEmpty ? "" : "\n" + old)
    }

    private func symlinkNotes() -> [SystemLinkNote] {
        let fm = FileManager.default
        var notes: [SystemLinkNote] = []
        let directory = home.appending(path: ".ssh")
        if let target = try? fm.destinationOfSymbolicLink(atPath: directory.path) { notes.append(.sshDirectoryIsSymlink(target)) }
        if let target = try? fm.destinationOfSymbolicLink(atPath: systemConfig.path) { notes.append(.configIsSymlink(target)) }
        return notes
    }

    private static func read(_ url: URL) -> Result<String, SystemLinkNote> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success("") }
        guard let data = try? RegularFile.read(url, limit: 8 << 20) else { return .failure(.unreadable(url.path)) }
        guard let text = String(validating: data, as: UTF8.self) else { return .failure(.notUTF8(url.path)) }
        return .success(text)
    }
}

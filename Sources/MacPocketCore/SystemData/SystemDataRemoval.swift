import Foundation

// MARK: - Preview

/// What a removal would do, in the words of the commands themselves, shown before anything runs.
public struct SystemDataRemovalPreview: Sendable, Equatable {
    public struct Line: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let sizeBytes: Int64
        public let safety: SystemDataSafety
        public let regeneration: SystemDataRegeneration
        /// One verbatim operation per entry, e.g. `rm -rf '/Users/me/Library/Caches/Homebrew'`.
        public let operations: [String]
        public let warning: String?
        public let requiresAdministrator: Bool
    }

    public let lines: [Line]
    public let mode: RemovalMode

    public var totalBytes: Int64 { lines.reduce(0) { $0 + $1.sizeBytes } }
    /// What would need the network to come back.
    public var networkBytes: Int64 { lines.filter { $0.regeneration.needsNetwork }.reduce(0) { $0 + $1.sizeBytes } }
    public var requiresAdministrator: Bool { lines.contains(where: \.requiresAdministrator) }
    public var administratorLineCount: Int { lines.filter(\.requiresAdministrator).count }

    /// The whole plan as plain text, for the pasteboard.
    public var copyText: String {
        lines.map { line in
            ([String(format: "# %@ (%@, %@)", line.title, ByteCountFormatter.string(fromByteCount: line.sizeBytes, countStyle: .file), line.safety.rawValue)]
                + line.operations).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

public enum SystemDataRemovalPlanner {
    /// Items MacPocket may remove; manual items are dropped here so they can never reach the confirmation.
    public static func preview(items: [SystemDataItem], mode: RemovalMode,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> SystemDataRemovalPreview {
        let lines = items.filter(\.isRemovable).map { item -> SystemDataRemovalPreview.Line in
            let (operations, admin) = operations(for: item, mode: mode, home: home.path, temporary: temporaryDirectory.path)
            return .init(id: item.id, title: item.title, sizeBytes: item.sizeBytes, safety: item.safety, regeneration: item.regeneration,
                         operations: operations, warning: item.warning, requiresAdministrator: admin)
        }
        return SystemDataRemovalPreview(lines: lines, mode: mode)
    }

    static func operations(for item: SystemDataItem, mode: RemovalMode, home: String, temporary: String) -> ([String], Bool) {
        func needsAdmin(_ path: String) -> Bool {
            !(path == home || path.hasPrefix(home + "/") || path == temporary || path.hasPrefix(temporary + "/"))
        }
        /// `glob` appends an unquoted `/*` so the shell would expand it, as the permanent-delete line shows.
        func remove(_ path: String, glob: Bool = false) -> String {
            let prefix = needsAdmin(path) ? String(localized: "Yönetici olarak: ") : ""
            if mode == .moveToTrash { return prefix + String(localized: "Çöp’e taşı: \(path)\(glob ? "/*" : "")") }
            return prefix + "rm -rf -- " + SystemDataCommand.quoted(path) + (glob ? "/*" : "")
        }
        switch item.action {
        case .removeFolder:
            return (item.paths.map { remove($0) }, item.paths.contains(where: needsAdmin))
        case .removeContents:
            return (item.paths.map { remove($0, glob: true) }, item.paths.contains(where: needsAdmin))
        case .removeContentsOlderThan(let days):
            return (item.paths.map { String(localized: "\($0) içinde \(days) günden eski öğeleri sil") }, item.paths.contains(where: needsAdmin))
        case .run(let command):
            let note = command.administratorFallback ? ["# " + String(localized: "Yalnızca bu başarısız olursa yönetici parolası istenir.")] : []
            return ([command.displayLine] + note, command.asAdministrator)
        case .manual(let hint):
            return ([hint], false)
        }
    }
}

// MARK: - Execution

public struct SystemDataRemovalOutcome: Sendable, Equatable, Identifiable {
    public var id: String { itemID }
    public let itemID: String
    public let title: String
    public let sizeBytes: Int64
    public let error: String?
    public var succeeded: Bool { error == nil }
}

public enum SystemDataRemovalError: Error, LocalizedError, Equatable {
    case appRunning(String)
    case commandFailed(String)
    case notRemovable

    public var errorDescription: String? {
        switch self {
        case .appRunning(let name): String(localized: "\(name) açık; önce uygulamayı kapat.")
        case .commandFailed(let detail): String(localized: "Komut başarısız oldu: \(detail)")
        case .notRemovable: String(localized: "Bu öğeyi MacPocket kaldırmaz.")
        }
    }
}

public actor SystemDataRemover {
    public typealias CommandResult = (status: Int32, message: String)
    public typealias CommandRunner = @Sendable (SystemDataCommand, _ administratorPrompt: String) async -> CommandResult

    private let trash: FileTrashService
    private let runCommand: CommandRunner
    private let isRunning: @Sendable (String) -> String?
    private let now: @Sendable () -> Date

    /// - Parameter runningAppName: the display name when the app with this bundle identifier is running, otherwise nil.
    public init(trash: FileTrashService = FileTrashService(),
                runCommand: @escaping CommandRunner = SystemDataRemover.liveRunner,
                runningAppName: @escaping @Sendable (String) -> String? = { _ in nil },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.trash = trash; self.runCommand = runCommand; self.isRunning = runningAppName; self.now = now
    }

    public static let liveRunner: CommandRunner = { command, prompt in
        guard command.executable.hasPrefix("/"), !command.executable.contains("\0"), !command.arguments.contains(where: { $0.contains("\0") }) else {
            return (1, "invalid command")
        }
        do {
            let result: BoundedProcess.Result
            if command.asAdministrator {
                result = try await BoundedProcess.run("/usr/bin/osascript", ["-e", administratorScript(for: command, prompt: prompt)], timeout: 900)
            } else {
                result = try await BoundedProcess.run(command.executable, command.arguments, timeout: 900)
            }
            let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return (result.status, message.isEmpty ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : message)
        } catch { return (1, error.localizedDescription) }
    }

    /// The AppleScript that runs `command` as root after one password prompt. Every word is shell-quoted and the whole
    /// line AppleScript-quoted, so a path or argument can never become a second command.
    static func administratorScript(for command: SystemDataCommand, prompt: String) -> String {
        let line = ([command.executable] + command.arguments).map(AdministratorRemover.shellQuoted).joined(separator: " ")
        return "do shell script \(AdministratorRemover.appleScriptQuoted(line)) with prompt \(AdministratorRemover.appleScriptQuoted(prompt)) with administrator privileges"
    }

    /// Removes the items. Files of all items go through one validated pass so a single administrator prompt covers
    /// them; commands run one by one. An item never fails the others.
    /// - Parameter administratorPrompt: the text of the password dialog. Nil means "never ask": items that need root fail
    ///   instead (what tests and unattended runs want).
    public func remove(_ items: [SystemDataItem], mode: RemovalMode, administratorPrompt: String?,
                       progress: @Sendable (SystemDataRemovalOutcome) -> Void = { _ in }) async -> [SystemDataRemovalOutcome] {
        var outcomes: [String: SystemDataRemovalOutcome] = [:]
        func finish(_ item: SystemDataItem, error: String?) {
            let outcome = SystemDataRemovalOutcome(itemID: item.id, title: item.title, sizeBytes: item.sizeBytes, error: error)
            outcomes[item.id] = outcome; progress(outcome)
        }

        var fileRequests: [(item: SystemDataItem, requests: [FileTrashRequest])] = []
        var commandItems: [(SystemDataItem, SystemDataCommand)] = []
        for item in items {
            guard item.isRemovable else { finish(item, error: SystemDataRemovalError.notRemovable.localizedDescription); continue }
            if let name = item.busyBundleIDs.lazy.compactMap(isRunning).first {
                finish(item, error: SystemDataRemovalError.appRunning(name).localizedDescription); continue
            }
            switch item.action {
            case .run(let command): commandItems.append((item, command))
            case .manual: finish(item, error: SystemDataRemovalError.notRemovable.localizedDescription)
            case .removeFolder, .removeContents, .removeContentsOlderThan:
                fileRequests.append((item, Self.requests(for: item, now: now())))
            }
        }

        let allRequests = fileRequests.flatMap(\.requests)
        let results = allRequests.isEmpty ? [] : await trash.remove(allRequests, mode: mode, administratorPrompt: administratorPrompt)
        let failures = Dictionary(results.compactMap { result in result.error.map { (result.source.path, $0) } }, uniquingKeysWith: { first, _ in first })
        for (item, requests) in fileRequests {
            let failed = requests.compactMap { failures[$0.url.path] }
            finish(item, error: failed.first)
        }

        for (item, command) in commandItems {
            var result: CommandResult
            if command.asAdministrator, administratorPrompt == nil {
                result = (1, "administrator permission is not available")   // never started: nothing may ask for a password
            } else {
                result = await runCommand(command, administratorPrompt ?? "")
                if result.status != 0, command.administratorFallback, !command.asAdministrator, let prompt = administratorPrompt {
                    result = await runCommand(command.elevated, prompt)
                }
            }
            // A cancelled password dialog is a decision, not a failure of the tool.
            let declined = result.message.contains(AdministratorRemover.cancelledMarker)
            finish(item, error: result.status == 0 ? nil
                : declined ? FileRemovalError.administratorDeclined.localizedDescription
                : SystemDataRemovalError.commandFailed(result.message.isEmpty ? "exit \(result.status)" : result.message).localizedDescription)
        }
        return items.compactMap { outcomes[$0.id] }
    }

    static func requests(for item: SystemDataItem, now: Date) -> [FileTrashRequest] {
        var requests: [FileTrashRequest] = []
        for path in item.paths {
            let url = URL(fileURLWithPath: path)
            switch item.action {
            case .removeFolder:
                guard let identity = try? FileIdentity.read(url), !identity.isSymbolicLink else { continue }
                requests.append(FileTrashRequest(url: url, identity: identity, root: url.deletingLastPathComponent()))
            case .removeContents, .removeContentsOlderThan:
                var cutoff: TimeInterval?
                if case .removeContentsOlderThan(let days) = item.action { cutoff = now.timeIntervalSince1970 - Double(days) * 86_400 }
                for name in ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted() {
                    let child = url.appending(path: name)
                    guard let identity = try? FileIdentity.read(child), !identity.isSymbolicLink else { continue }
                    if let cutoff, newestModification(of: child.path, identity: identity) >= cutoff { continue }
                    requests.append(FileTrashRequest(url: child, identity: identity, root: url))
                }
            default: break
            }
        }
        return requests
    }

    /// Newest change inside a child, so a folder with a fresh file inside is never treated as old.
    static func newestModification(of path: String, identity: FileIdentity) -> TimeInterval {
        var newest = Double(identity.modifiedSeconds)
        guard identity.isDirectory else { return newest }
        TreeWalker.walk(path) { entry in
            if entry.kind == .file || entry.kind == .directory { newest = max(newest, Double(entry.modified)) }
            return .proceed
        }
        return newest
    }
}

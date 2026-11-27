import Foundation

/// What happens to a validated item. Cleaning caches frees space only when it is deleted for good;
/// the Trash keeps the bytes on disk until it is emptied.
public enum RemovalMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case deletePermanently, moveToTrash

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .deletePermanently: String(localized: "Kalıcı Olarak Sil")
        case .moveToTrash: String(localized: "Çöp’e Taşı")
        }
    }

    public var isRecoverable: Bool { self == .moveToTrash }
}

/// The user's choice, remembered across launches. Permanent deletion is the default because the
/// Trash does not give the space back.
public enum RemovalModePreference {
    public static let storageKey = "MacPocket.removal.mode"

    public static func load(_ defaults: UserDefaults = .standard) -> RemovalMode {
        defaults.string(forKey: storageKey).flatMap(RemovalMode.init(rawValue:)) ?? .deletePermanently
    }

    public static func save(_ mode: RemovalMode, _ defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: storageKey)
    }
}

public enum FileRemovalError: Error, LocalizedError, Equatable {
    case administratorRequired
    case administratorDeclined
    case administratorFailed(String)
    case stillExists

    public var errorDescription: String? {
        switch self {
        case .administratorRequired: String(localized: "Bu öğeyi silmek için yönetici izni gerekiyor.")
        case .administratorDeclined: String(localized: "Yönetici izni verilmedi; öğe silinmedi.")
        case .administratorFailed(let detail): String(localized: "Yönetici yetkisiyle silme tamamlanamadı: \(detail)")
        case .stillExists: String(localized: "Silme tamamlandı görünüyor ancak öğe hâlâ duruyor.")
        }
    }
}

enum FileRemovalClassifier {
    /// Deleting something the user does not own (an App Store app, a root-owned helper) or that carries
    /// an immutable flag fails with a permission error; only those are worth an administrator retry.
    static func isPermissionFailure(_ error: Error) -> Bool {
        if let removal = error as? FileRemovalError, removal == .administratorRequired { return true }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError { return true }
        if nsError.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(nsError.code) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError { return isPermissionFailure(underlying) }
        return false
    }
}

/// Removes files as root after one system password prompt (`do shell script … with administrator
/// privileges`). Only validated, canonical absolute paths are accepted; they are quoted for the shell
/// and then for AppleScript, and the process is started without a shell of our own.
public struct AdministratorRemover: Sendable {
    public typealias Runner = @Sendable (_ arguments: [String]) async throws -> BoundedProcess.Result
    private let run: Runner

    /// Long enough for the user to type a password, short enough that a forgotten dialog does not hang the
    /// app.
    static let timeout: TimeInterval = 180
    /// osascript reports a cancelled authorization dialog as "User canceled. (-128)"; the parentheses keep a
    /// path that merely contains -128 from being mistaken for it.
    static let cancelledMarker = "(-128)"

    public init() {
        run = { arguments in try await BoundedProcess.run("/usr/bin/osascript", arguments, timeout: Self.timeout) }
    }
    init(run: @escaping Runner) { self.run = run }

    public struct Outcome: Sendable {
        /// Paths that still exist after the attempt; everything else is gone.
        public let remaining: [URL]
        public let diagnostic: String?
    }

    /// Throws only when nothing could run: an unsafe target, a declined password prompt or a tool that failed to start.
    /// A partly successful run (`rm` deletes what it can) is reported through `Outcome.remaining`.
    /// - Parameter launchdLabels: system-domain jobs stopped before their files go away.
    public func remove(_ urls: [URL], launchdLabels: [String] = [], prompt: String) async throws -> Outcome {
        guard !urls.isEmpty else { return Outcome(remaining: [], diagnostic: nil) }
        for url in urls where !Self.isSafeTarget(url) { throw FileServiceError.protectedItem }
        let arguments = ["-e", Self.script(paths: urls.map(\.path), launchdLabels: launchdLabels, prompt: prompt)]
        let result: BoundedProcess.Result
        do { result = try await run(arguments) }
        catch {
            // The privileged rm may have run before the timeout or cancellation, so report what is left.
            let remaining = urls.filter { lstatIdentity($0.path) != nil }
            guard remaining.count < urls.count else { throw FileRemovalError.administratorFailed(error.localizedDescription) }
            return Outcome(remaining: remaining, diagnostic: error.localizedDescription)
        }
        let diagnostic = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status != 0, diagnostic.contains(Self.cancelledMarker) { throw FileRemovalError.administratorDeclined }
        let remaining = urls.filter { lstatIdentity($0.path) != nil }
        return Outcome(remaining: remaining, diagnostic: result.status == 0 ? nil : diagnostic)
    }

    static func isSafeTarget(_ url: URL) -> Bool {
        let path = url.path
        guard path.hasPrefix("/"), path.count > 1, !path.contains("\0"), !path.split(separator: "/").contains("..") else { return false }
        return existingCanonicalPath(url) == path && !isProtected(path)
    }

    /// Roots and system trees that are never removed with administrator rights, whoever the caller is.
    /// Mirrors `FileTrashRequest.validate`, so this type is safe on its own and not only behind that check.
    private static func isProtected(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots: Set<String> = ["/", "/Users", "/Applications", "/Library", "/System", "/usr", "/bin", "/sbin", "/private", "/dev",
                                  home, home + "/Library", home + "/Library/Caches", home + "/Library/Logs"]
        if roots.contains(path) { return true }
        let trees = ["/System", "/usr", "/bin", "/sbin", "/private", "/dev"]
        guard trees.contains(where: { path.hasPrefix($0 + "/") }) else { return false }
        // Owned fixtures live under the per-user temporary directory, which is below /private.
        guard let temporary = existingCanonicalPath(FileManager.default.temporaryDirectory) else { return true }
        return !path.hasPrefix(temporary + "/")
    }

    static func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func script(paths: [String], launchdLabels: [String], prompt: String) -> String {
        var commands = launchdLabels.filter(Self.isValidLaunchdLabel).map {
            "/bin/launchctl bootout \(shellQuoted("system/" + $0)) >/dev/null 2>&1 || true"
        }
        commands.append("/bin/rm -rf -- " + paths.map(shellQuoted).joined(separator: " "))
        return "do shell script \(appleScriptQuoted(commands.joined(separator: "; "))) with prompt \(appleScriptQuoted(prompt)) with administrator privileges"
    }

    static func isValidLaunchdLabel(_ label: String) -> Bool {
        !label.isEmpty && label.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }
}

public enum LaunchdJobs {
    /// Stops a per-user job before its property list is deleted; a job that is not loaded is not an error.
    public static func stopUserAgent(label: String, uid: uid_t = getuid()) async {
        guard AdministratorRemover.isValidLaunchdLabel(label) else { return }
        _ = try? await BoundedProcess.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"], timeout: 10)
    }
}

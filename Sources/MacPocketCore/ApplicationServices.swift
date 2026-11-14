import Foundation

public enum ApplicationChannel: String, Codable, Sendable {
    case system = "macOS", appStore = "App Store", setapp = "Setapp", sparkle = "Uygulama içi", unknown = "Üretici"

    /// Display name; the raw value is the stable identifier.
    public var localizedTitle: String {
        switch self {
        case .system: String(localized: "macOS")
        case .appStore: String(localized: "App Store")
        case .setapp: String(localized: "Setapp")
        case .sparkle: String(localized: "Uygulama içi")
        case .unknown: String(localized: "Üretici")
        }
    }
}

public struct InstalledApplication: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let build: String
    public let channel: ApplicationChannel
    public let identity: FileIdentity
    public var protected: Bool { channel == .system || bundleID.hasPrefix("com.apple.") || bundleID == "com.doancan.MacPocket" }
}

public actor ApplicationInventory {
    public init() {}
    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/System/Applications")]
    }
    public func scan(roots: [URL]? = nil) async throws -> [InstalledApplication] {
        let roots = roots ?? Self.defaultRoots
        var applications: [InstalledApplication] = []
        var seen = Set<String>()
        for suppliedRoot in roots {
            guard let root = try? canonicalFileURL(suppliedRoot) else { continue }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            var count = 0
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                count += 1
                if count > 20_000 { break }
                if enumerator.level > 4 { enumerator.skipDescendants(); continue }
                guard let identity = try? FileIdentity.read(url) else { continue }
                if identity.isSymbolicLink { enumerator.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app", identity.isDirectory else { continue }
                enumerator.skipDescendants()
                guard seen.insert(identity.objectKey).inserted, let application = Self.read(url) else { continue }
                applications.append(application)
                if count.isMultiple(of: 64) { await Task.yield() }
            }
        }
        return applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func read(_ url: URL) -> InstalledApplication? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty,
              let identity = try? FileIdentity.read(url) else { return nil }
        let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let channel: ApplicationChannel
        if url.path.hasPrefix("/System/") { channel = .system }
        else if url.pathComponents.contains("Setapp") || id.hasSuffix("-setapp") { channel = .setapp }
        else if FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path) { channel = .appStore }
        else if plist["SUFeedURL"] != nil || FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Sparkle.framework").path) { channel = .sparkle }
        else { channel = .unknown }
        return .init(url: url, name: name, bundleID: id,
                     version: plist["CFBundleShortVersionString"] as? String ?? "—",
                     build: plist["CFBundleVersion"] as? String ?? "—", channel: channel, identity: identity)
    }
}

public struct UninstallCandidate: Identifiable, Sendable {
    public var id: String { request.url.path }
    public let title: String
    public let containsUserData: Bool
    public let request: FileTrashRequest
    /// Lives in /Library rather than the user's Library: removing it asks for an administrator password.
    public var isSystemLevel = false
    /// Found by the app's exact name rather than its bundle identifier.
    public var matchedByName = false
    /// launchd job that must be stopped before its property list is removed.
    public var launchdLabel: String?
}

public struct UninstallPlan: Identifiable, Sendable {
    public var id: String { application.id }
    public let application: InstalledApplication
    public let candidates: [UninstallCandidate]
    public let createdAt: Date
    public let home: URL
    /// The machine-wide Library that was searched; nil when only the user's Library was.
    public var systemLibrary: URL?
    /// Bundle identifiers of the other installed applications the search steered clear of.
    public var siblingIDs: Set<String> = []

    /// "Remove everything": the app and every leftover found, user data included.
    public var completeSelection: Set<String> { Set(candidates.map(\.id)) }
    public var requiresAdministrator: Bool { candidates.contains(where: \.isSystemLevel) }
}

public enum UninstallPlanner {
    public static let defaultSystemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)

    public static func validateApplication(_ application: InstalledApplication) throws {
        guard !application.protected else { throw FileServiceError.protectedItem }
        guard application.url.pathExtension.lowercased() == "app", application.identity.isDirectory,
              !application.identity.isSymbolicLink else { throw FileServiceError.outsideScope }
        guard try FileIdentity.read(application.url) == application.identity,
              ApplicationInventory.read(application.url)?.bundleID == application.bundleID else { throw FileServiceError.changed }
    }

    private struct Rule {
        let folder: String
        let title: String
        let userData: Bool
        let matches: (String) -> Bool
    }

    /// Bundle identifiers are case-insensitive on disk; `name` and `id` are lowercased before comparison.
    private static func rules(id: String, system: Bool) -> [Rule] {
        let id = id.lowercased()
        func exact(_ name: String) -> Bool { name == id }
        func family(_ name: String) -> Bool { name == id || name.hasPrefix(id + ".") }
        func plist(_ name: String) -> Bool { name.hasSuffix(".plist") && (name == id + ".plist" || name.hasPrefix(id + ".")) }
        if system {
            return [
                Rule(folder: "LaunchDaemons", title: String(localized: "Sistem arka plan hizmeti"), userData: false, matches: plist),
                Rule(folder: "LaunchAgents", title: String(localized: "Sistem başlangıç öğesi"), userData: false, matches: plist),
                Rule(folder: "PrivilegedHelperTools", title: String(localized: "Ayrıcalıklı yardımcı"), userData: false, matches: family),
                Rule(folder: "Application Support", title: String(localized: "Ortak uygulama verileri"), userData: true, matches: exact),
                Rule(folder: "Preferences", title: String(localized: "Ortak tercihler"), userData: true,
                     matches: { $0 == id + ".plist" }),
                Rule(folder: "Caches", title: String(localized: "Ortak önbellek"), userData: false, matches: family),
            ]
        }
        return [
            Rule(folder: "Caches", title: String(localized: "Önbellek"), userData: false, matches: family),
            Rule(folder: "Logs", title: String(localized: "Günlükler"), userData: false, matches: family),
            Rule(folder: "HTTPStorages", title: String(localized: "HTTP verileri"), userData: true, matches: family),
            Rule(folder: "Preferences", title: String(localized: "Tercihler"), userData: true, matches: plist),
            Rule(folder: "Preferences/ByHost", title: String(localized: "Bu Mac’e özel tercihler"), userData: true, matches: plist),
            Rule(folder: "Application Support", title: String(localized: "Uygulama verileri"), userData: true, matches: exact),
            Rule(folder: "Saved Application State", title: String(localized: "Kaydedilmiş durum"), userData: true,
                 matches: { $0 == id + ".savedstate" }),
            Rule(folder: "WebKit", title: String(localized: "Web verileri"), userData: true, matches: family),
            Rule(folder: "Containers", title: String(localized: "Uygulama kapsayıcısı"), userData: true, matches: family),
            Rule(folder: "Group Containers", title: String(localized: "Grup kapsayıcısı"), userData: true,
                 matches: { $0 == "group." + id || $0.hasSuffix("." + id) }),
            Rule(folder: "Application Scripts", title: String(localized: "Uygulama betikleri"), userData: false, matches: family),
            Rule(folder: "Cookies", title: String(localized: "Çerezler"), userData: true, matches: { $0 == id + ".binarycookies" }),
            Rule(folder: "LaunchAgents", title: String(localized: "Başlangıç öğesi"), userData: false, matches: plist),
        ]
    }

    /// Folders that apps name after themselves instead of their bundle identifier.
    private static let nameKeyedFolders: [(folder: String, title: String, userData: Bool)] = [
        ("Application Support", String(localized: "Uygulama verileri (ada göre)"), true),
        ("Caches", String(localized: "Önbellek (ada göre)"), false),
        ("Logs", String(localized: "Günlükler (ada göre)"), false),
    ]

    /// Names too generic to prove ownership.
    private static let minimumNameLength = 4

    /// Everything that provably belongs to the application: exact bundle identifier families in the user's
    /// Library and, when `systemLibrary` is given, in /Library; plus folders named exactly like the app.
    /// Vendor-wide folders (a shared prefix such as `com.vendor`) are never inferred. `siblingIDs` are the other
    /// installed applications' identifiers: an app named `com.x.Editor` must not take the data of an installed
    /// `com.x.Editor.beta` with it just because the names share a prefix.
    public static func plan(_ application: InstalledApplication, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            systemLibrary: URL? = defaultSystemLibrary, siblingIDs: Set<String> = []) throws -> UninstallPlan {
        try validateApplication(application)
        let id = application.bundleID
        guard id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              !id.contains("..") else { throw FileServiceError.outsideScope }
        var candidates = [UninstallCandidate(title: String(localized: "Uygulama"), containsUserData: false,
            request: .init(url: application.url, identity: application.identity, root: application.url, applicationBundle: true))]
        var seen = Set([application.url.path])
        func add(_ url: URL, root: URL, title: String, userData: Bool, system: Bool, byName: Bool = false) {
            guard let identity = lstatIdentity(url.path), !identity.isSymbolicLink, seen.insert(url.path).inserted else { return }
            candidates.append(.init(title: title, containsUserData: userData,
                                    request: .init(url: url, identity: identity, root: root),
                                    isSystemLevel: system, matchedByName: byName,
                                    launchdLabel: launchdLabel(url, folder: root, system: system)))
        }
        let library = try canonicalFileURL(home).appendingPathComponent("Library", isDirectory: true)
        // Only identifiers nested under this one can collide with its prefix matches; unrelated or ancestor
        // identifiers must never hide this application's own data.
        let siblings = Set(siblingIDs.map { $0.lowercased() }.filter { $0.hasPrefix(id.lowercased() + ".") })
        scan(library, rules: rules(id: id, system: false), siblings: siblings) { add($0, root: library, title: $1, userData: $2, system: false) }
        if let systemLibrary, let canonical = try? canonicalFileURL(systemLibrary) {
            scan(canonical, rules: rules(id: id, system: true), siblings: siblings) { add($0, root: canonical, title: $1, userData: $2, system: true) }
        }
        for name in nameCandidates(application) {
            for (folder, title, userData) in nameKeyedFolders {
                let url = library.appendingPathComponent(folder).appendingPathComponent(name)
                add(url, root: library, title: title, userData: userData, system: false, byName: true)
            }
        }
        return .init(application: application, candidates: candidates, createdAt: Date(), home: home,
                     systemLibrary: systemLibrary, siblingIDs: siblingIDs)
    }

    private static func nameCandidates(_ application: InstalledApplication) -> [String] {
        let names = [application.name, application.url.deletingPathExtension().lastPathComponent]
        var unique: [String] = []
        for name in names where name.count >= minimumNameLength && !name.contains("/") && !unique.contains(name) { unique.append(name) }
        return unique
    }

    /// True when `name` (lowercased) is the data of another installed application: its identifier or a family member of it.
    private static func belongsToSibling(_ name: String, siblings: Set<String>) -> Bool {
        siblings.contains { name == $0 || name.hasPrefix($0 + ".") || name.hasSuffix("." + $0) }
    }

    private static func scan(_ library: URL, rules: [Rule], siblings: Set<String>, found: (URL, String, Bool) -> Void) {
        for rule in rules {
            let directory = library.appendingPathComponent(rule.folder, isDirectory: true)
            guard let identity = lstatIdentity(directory.path), identity.isDirectory, !identity.isSymbolicLink,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names.sorted() where rule.matches(name.lowercased()) && !belongsToSibling(name.lowercased(), siblings: siblings) {
                found(directory.appendingPathComponent(name), rule.title, rule.userData)
            }
        }
    }

    private static func launchdLabel(_ url: URL, folder: URL, system: Bool) -> String? {
        guard url.pathExtension == "plist", url.deletingLastPathComponent().lastPathComponent.hasPrefix("Launch"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String, AdministratorRemover.isValidLaunchdLabel(label) else { return nil }
        return label
    }
}

public enum UninstallProcessScope {
    /// Executable containment is component-bounded. Names, bundle-ID prefixes and parent PIDs are not ownership proof.
    public static func contains(_ executable: String, applicationURL: URL) -> Bool {
        guard executable.hasPrefix("/"), applicationURL.isFileURL,
              applicationURL.standardizedFileURL.pathExtension.lowercased() == "app" else { return false }
        let root = applicationURL.standardizedFileURL.resolvingSymlinksInPath().path
        let path = URL(fileURLWithPath: executable).standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(root + "/")
    }
}

public struct HomebrewCask: Identifiable, Sendable, Equatable {
    public var id: String { token }
    public let token: String
    public let name: String
    public let installedVersion: String
    public let currentVersion: String
    public let applicationNames: [String]
    public let outdated: Bool
    public let pinned: Bool
}

public enum HomebrewError: Error, LocalizedError {
    case unavailable, failed(String), malformed, invalidToken, notInstalled
    public var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Homebrew bulunamadı. Homebrew güncellemeleri bu Mac'te kullanılamıyor.")
        case .failed(let output): String(localized: "Homebrew işlemi tamamlanamadı: \(output.suffix(2000))")
        case .malformed: String(localized: "Homebrew yanıtı okunamadı.")
        case .invalidToken: String(localized: "Geçersiz uygulama kimliği.")
        case .notInstalled: String(localized: "Bu uygulama Homebrew'ün kurulu listesinde bulunmuyor.")
        }
    }
}

public actor HomebrewApplications {
    public init() {}
    public func installed() async throws -> [HomebrewCask] {
        let output = try await command(["info", "--cask", "--installed", "--json=v2"], timeout: 60)
        return try Self.decodeInstalled(output)
    }
    public func updates() async throws -> [HomebrewCask] {
        let output = try await command(["outdated", "--cask", "--json=v2"], timeout: 60)
        return try Self.decodeUpdates(output)
    }
    public func upgrade(_ token: String) async throws -> String {
        guard Self.validToken(token) else { throw HomebrewError.invalidToken }
        let applications = try await installed()
        guard applications.contains(where: { $0.token == token && !$0.pinned }) else { throw HomebrewError.notInstalled }
        return try await command(["upgrade", "--cask", token], timeout: 600)
    }
    public func uninstall(_ token: String) async throws -> String {
        guard Self.validToken(token) else { throw HomebrewError.invalidToken }
        guard try await installed().contains(where: { $0.token == token }) else { throw HomebrewError.notInstalled }
        return try await command(["uninstall", "--cask", token], timeout: 600)
    }

    static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.range(of: #"^[a-z0-9][a-z0-9+_.@-]*$"#, options: .regularExpression) != nil
            && !token.contains("..")
    }
    static func decodeUpdates(_ output: String) throws -> [HomebrewCask] {
        let object = try jsonObject(output)
        guard let casks = object["casks"] as? [[String: Any]] else { throw HomebrewError.malformed }
        return casks.compactMap { item in
            guard let token = item["name"] as? String, validToken(token),
                  let current = item["current_version"] as? String,
                  let versions = item["installed_versions"] as? [String] else { return nil }
            return .init(token: token, name: token, installedVersion: versions.joined(separator: ", "),
                         currentVersion: current, applicationNames: [], outdated: true, pinned: item["pinned"] as? Bool ?? false)
        }
    }
    static func decodeInstalled(_ output: String) throws -> [HomebrewCask] {
        let object = try jsonObject(output)
        guard let casks = object["casks"] as? [[String: Any]] else { throw HomebrewError.malformed }
        return casks.compactMap { item in
            guard let token = item["token"] as? String, validToken(token) else { return nil }
            let artifacts = item["artifacts"] as? [[String: Any]] ?? []
            let names = artifacts.flatMap { $0["app"] as? [Any] ?? [] }.compactMap { $0 as? String }.filter { $0.hasSuffix(".app") }
            return .init(token: token, name: (item["name"] as? [String])?.first ?? token,
                         installedVersion: item["installed"] as? String ?? "—",
                         currentVersion: item["version"] as? String ?? "—", applicationNames: names,
                         outdated: item["outdated"] as? Bool ?? false, pinned: item["pinned"] as? Bool ?? false)
        }
    }
    private static func jsonObject(_ output: String) throws -> [String: Any] {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end,
              let object = try JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any] else {
            throw HomebrewError.malformed
        }
        return object
    }

    private func command(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        guard let executable = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw HomebrewError.unavailable }
        // stderr stays separate so JSON on stdout parses; a long upgrade is never killed for being chatty,
        // and cancellation interrupts brew first so it can stop its own child processes.
        let runner = SystemDiagnosticCommandRunner(executable: executable, arguments: arguments, timeout: timeout, outputLimit: 4_194_304,
            environment: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                          "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                          "TMPDIR": FileManager.default.temporaryDirectory.path,
                          "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
                          "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_ENV_HINTS": "1"],
            separateErrorOutput: true, stopOnOutputLimit: false, interruptGracePeriod: 10)
        let result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { try runner.execute() }.value
        } onCancel: { runner.cancel() }
        guard result.exitCode == 0 else {
            throw HomebrewError.failed([result.errorOutput, result.output].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        return result.output
    }
}

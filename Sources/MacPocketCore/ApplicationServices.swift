import Foundation

public enum ApplicationChannel: String, Codable, Sendable {
    case system = "macOS", appStore = "App Store", setapp = "Setapp", sparkle = "Uygulama içi", unknown = "Üretici"
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
}

public struct UninstallPlan: Identifiable, Sendable {
    public var id: String { application.id }
    public let application: InstalledApplication
    public let candidates: [UninstallCandidate]
    public let createdAt: Date
}

public enum UninstallPlanner {
    /// Exact bundle identifiers only. Shared vendor/App Group directories are never inferred.
    public static func plan(_ application: InstalledApplication, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> UninstallPlan {
        guard !application.protected else { throw FileServiceError.protectedItem }
        guard try FileIdentity.read(application.url) == application.identity else { throw FileServiceError.changed }
        let id = application.bundleID
        guard id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              !id.contains("..") else { throw FileServiceError.outsideScope }
        var candidates = [UninstallCandidate(title: "Uygulama", containsUserData: false,
            request: .init(url: application.url, identity: application.identity, root: application.url, applicationBundle: true))]
        let library = try canonicalFileURL(home).appendingPathComponent("Library", isDirectory: true)
        let locations: [(String, String, Bool)] = [
            ("Caches/" + id, "Önbellek", false),
            ("Logs/" + id, "Günlükler", false),
            ("Preferences/" + id + ".plist", "Tercihler", true),
            ("Application Support/" + id, "Uygulama verileri", true),
            ("Saved Application State/" + id + ".savedState", "Kaydedilmiş durum", true),
            ("WebKit/" + id, "Web verileri", true),
            ("HTTPStorages/" + id, "HTTP verileri", true),
            ("Containers/" + id, "Uygulama kapsayıcısı", true),
        ]
        for (path, title, userData) in locations {
            let url = library.appendingPathComponent(path)
            guard let identity = try? FileIdentity.read(url), !identity.isSymbolicLink else { continue }
            candidates.append(.init(title: title, containsUserData: userData,
                                    request: .init(url: url, identity: identity, root: library)))
        }
        return .init(application: application, candidates: candidates, createdAt: Date())
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
        case .unavailable: "Homebrew bulunamadı. Homebrew güncellemeleri bu Mac'te kullanılamıyor."
        case .failed(let output): "Homebrew işlemi tamamlanamadı: \(output.suffix(2000))"
        case .malformed: "Homebrew yanıtı okunamadı."
        case .invalidToken: "Geçersiz uygulama kimliği."
        case .notInstalled: "Bu uygulama Homebrew'ün kurulu listesinde bulunmuyor."
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
        let runner = SystemDiagnosticCommandRunner(executable: executable, arguments: arguments, timeout: timeout, outputLimit: 4_194_304,
            environment: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                          "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                          "TMPDIR": FileManager.default.temporaryDirectory.path,
                          "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
                          "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_ENV_HINTS": "1"])
        let result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { try runner.execute() }.value
        } onCancel: { runner.cancel() }
        guard result.exitCode == 0 else { throw HomebrewError.failed(result.output) }
        return result.output
    }
}

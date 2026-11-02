import Foundation

/// Where a launchd plist lives; decides who may change it.
public enum StartupScope: String, Sendable {
    /// ~/Library/LaunchAgents: the user's own, changeable without a password.
    case userAgent
    /// /Library/LaunchAgents and /Library/LaunchDaemons: installed for every user, changing them needs an administrator.
    case globalAgent, globalDaemon
}

public enum StartupClass: String, Sendable, CaseIterable, Identifiable {
    case direct, systemManaged, readOnly
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .direct: String(localized: "Doğrudan yönetilebilir")
        case .systemManaged: String(localized: "Yönetici gerektirir")
        case .readOnly: String(localized: "Apple’a ait")
        }
    }

    public var detail: String {
        switch self {
        case .direct: String(localized: "Kendi kullanıcı klasöründeki öğeler.")
        case .systemManaged: String(localized: "Tüm kullanıcılar için kurulmuş; değiştirmek yönetici onayı ister.")
        case .readOnly: String(localized: "macOS bileşenleri; değiştirilmez.")
        }
    }
}

public struct StartupItem: Identifiable, Sendable, Equatable {
    public var id: String { plistURL.path }
    public let label: String
    public let plistURL: URL
    public let scope: StartupScope
    public let kind: StartupClass
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public let isEnabled: Bool

    /// The app that ships the job, taken from the program path (`/Applications/Foo.app/…` → "Foo").
    public var appName: String? {
        guard let program else { return nil }
        let parts = program.split(separator: "/")
        return parts.first { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
    }
}

/// launchd jobs that start by themselves (login or boot). Reading only: nothing here changes a job.
public enum StartupItems {
    public static func directories(home: URL) -> [(URL, StartupScope)] {
        [(home.appendingPathComponent("Library/LaunchAgents", isDirectory: true), .userAgent),
         (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), .globalAgent),
         (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), .globalDaemon)]
    }

    public static func parse(_ data: Data, url: URL, scope: StartupScope, disabledLabels: Set<String>) -> StartupItem? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let label = plist["Label"] as? String, !label.isEmpty else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let keepsAlive: Bool = switch plist["KeepAlive"] {
        case let flag as Bool: flag
        case is [String: Any]: true
        default: false
        }
        let kind: StartupClass = label.hasPrefix("com.apple.") ? .readOnly : (scope == .userAgent ? .direct : .systemManaged)
        let disabledInPlist = plist["Disabled"] as? Bool ?? false
        return StartupItem(label: label, plistURL: url, scope: scope, kind: kind, program: program,
                           runsAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepsAlive: keepsAlive,
                           isEnabled: !disabledInPlist && !disabledLabels.contains(label))
    }

    /// Labels `launchctl print-disabled` reports as off (`"label" => disabled`).
    public static func parseDisabled(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"")))
            if !label.isEmpty { labels.insert(label) }
        }
        return labels
    }

    public static func scan(directories: [(URL, StartupScope)], disabledLabels: Set<String>) -> [StartupItem] {
        var items: [StartupItem] = []
        for (directory, scope) in directories {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let url = directory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let item = parse(data, url: url, scope: scope, disabledLabels: disabledLabels) else { continue }
                items.append(item)
            }
        }
        let order = Dictionary(uniqueKeysWithValues: StartupClass.allCases.enumerated().map { ($1, $0) })
        return items.sorted { lhs, rhs in
            let (l, r) = (order[lhs.kind, default: 0], order[rhs.kind, default: 0])
            return l == r ? lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending : l < r
        }
    }

    public struct Snapshot: Sendable {
        public let items: [StartupItem]
        /// False when launchctl could not be read: enabled/disabled is then only what the plists themselves say.
        public let stateKnown: Bool
    }

    public static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser, uid: uid_t = getuid()) async -> Snapshot {
        var disabled = Set<String>()
        var known = true
        do {
            let result = try await BoundedProcess.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"], timeout: 5)
            if result.status == 0 { disabled = parseDisabled(result.output) } else { known = false }
        } catch {
            known = false
        }
        let knownDisabled = disabled
        let items = await Task.detached { scan(directories: directories(home: home), disabledLabels: knownDisabled) }.value
        return Snapshot(items: items, stateKnown: known)
    }
}

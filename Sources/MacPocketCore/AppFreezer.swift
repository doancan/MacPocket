import Foundation

/// Pauses (SIGSTOP) chosen apps while they sit in the background and resumes them (SIGCONT) when they come
/// to the front: a backgrounded browser or chat app stops burning CPU and battery until it's used again.
public struct AppFreezeRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    /// Minutes in the background before freezing.
    public var delayMinutes: Int

    public init(bundleID: String, delayMinutes: Int = 5) {
        self.bundleID = bundleID; self.delayMinutes = delayMinutes
    }

    public static let delayChoices = [1, 5, 15, 30, 60]
}

public struct AppFreezerSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var rules: [AppFreezeRule] = []
    public static let storageKey = "MacPocket.freezer.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> AppFreezerSettings {
        guard let data = defaults.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(AppFreezerSettings.self, from: data) else { return AppFreezerSettings() }
        // Rules for apps that must never be paused are dropped even if a file says otherwise.
        settings.rules.removeAll { !AppFreezer.canFreeze($0.bundleID) }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum AppFreezer {
    /// Apps whose pause would stall the session, the Dock, the desktop or MacPocket itself.
    static let neverFreeze: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver", "com.apple.controlcenter",
        "com.apple.notificationcenterui", "com.apple.WindowManager", "com.apple.Spotlight", "com.apple.SecurityAgent",
        "com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.Terminal", "com.doancan.MacPocket",
    ]

    public static func canFreeze(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && !neverFreeze.contains(bundleID)
    }

    /// A running app as the freezer sees it.
    public struct AppState: Equatable, Sendable {
        public let bundleID: String
        public let isFrontmost: Bool
        /// When the app last left the front; nil if never seen in front since launch (counts from launch).
        public let backgroundSince: Date
        public let isFrozen: Bool

        public init(bundleID: String, isFrontmost: Bool, backgroundSince: Date, isFrozen: Bool) {
            self.bundleID = bundleID; self.isFrontmost = isFrontmost; self.backgroundSince = backgroundSince; self.isFrozen = isFrozen
        }
    }

    public enum Decision: Equatable, Sendable { case freeze, thaw }

    /// What to do with one app now. Frozen apps that came to the front, lost their rule or the feature turned
    /// off are thawed; ruled background apps past their delay are frozen.
    public static func decide(_ app: AppState, settings: AppFreezerSettings, now: Date) -> Decision? {
        let rule = settings.rules.first { $0.bundleID == app.bundleID }
        if app.isFrozen {
            return app.isFrontmost || !settings.enabled || rule == nil || !canFreeze(app.bundleID) ? .thaw : nil
        }
        guard settings.enabled, let rule, canFreeze(app.bundleID), !app.isFrontmost else { return nil }
        return now.timeIntervalSince(app.backgroundSince) >= Double(rule.delayMinutes) * 60 ? .freeze : nil
    }
}

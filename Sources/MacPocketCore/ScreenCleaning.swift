import Foundation

/// A flat colour to wipe against: white shows dust best, black shows fingerprints.
public enum CleaningColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case black, white, gray
    public var id: String { rawValue }

    public var isDark: Bool { self != .white }
    public var usesDarkText: Bool { !isDark }
}

public struct ScreenCleaningSettings: Codable, Equatable, Sendable {
    public static let storageKey = "MacPocket.screenCleaning.settings"

    public var color = CleaningColor.black
    /// Also drops keyboard and mouse input system-wide while cleaning (needs Accessibility access). Off by
    /// default.
    public var locksInput = false

    public init() {}

    public static func load(from defaults: UserDefaults) -> ScreenCleaningSettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ScreenCleaningSettings.self, from: $0) } ?? ScreenCleaningSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// What a locked cleaning session does with a keyboard event: everything is dropped, and Esc ends the
/// session.
public enum CleaningInputPolicy {
    public enum Decision: Equatable, Sendable { case drop, exit }

    public static let escapeKeyCode: Int64 = 53

    public static func decision(isKeyDown: Bool, keyCode: Int64) -> Decision {
        isKeyDown && keyCode == escapeKeyCode ? .exit : .drop
    }
}

import Foundation

/// "Turn the display off when idle, but keep the Mac awake." Applies only while a MacPocket keep-awake
/// session (manual or automatic) holds the system and does not also hold the display.
public struct IdleDisplayOffSettings: Codable, Equatable, Sendable {
    public static let allowedMinutes = [1, 2, 5, 10, 15, 30]
    public static let defaultMinutes = 5
    public static let key = "MacPocket.power.idleDisplayOff"

    public var enabled = false
    public var minutes = IdleDisplayOffSettings.defaultMinutes
    public init() {}

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(to defaults: UserDefaults) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) } }

    public var thresholdSeconds: TimeInterval {
        Double(Self.allowedMinutes.contains(minutes) ? minutes : Self.defaultMinutes) * 60
    }
}

/// Pure decision: fires once per idle period and re-arms as soon as the user touches the keyboard or mouse
/// again.
public struct IdleDisplayOffPolicy: Sendable {
    private var firedThisIdlePeriod = false
    public init() {}

    /// - Parameter idleSeconds: time since the last keyboard/mouse event, nil when it cannot be read.
    public mutating func shouldSleepDisplay(_ settings: IdleDisplayOffSettings, idleSeconds: TimeInterval?,
                                            session: AwakeSession?) -> Bool {
        guard settings.enabled, let session, session.active, !session.keepDisplayAwake,
              let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 else {
            firedThisIdlePeriod = false
            return false
        }
        guard idleSeconds >= settings.thresholdSeconds else { firedThisIdlePeriod = false; return false }
        guard !firedThisIdlePeriod else { return false }
        firedThisIdlePeriod = true
        return true
    }
}

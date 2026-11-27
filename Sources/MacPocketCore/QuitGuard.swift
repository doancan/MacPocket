import Foundation

/// How a guarded shortcut must be pressed before it reaches the app.
public enum QuitGuardMode: String, Codable, CaseIterable, Sendable {
    case off
    /// Keep the shortcut held for `holdDuration`.
    case hold
    /// Press it twice within `doublePressInterval`.
    case doublePress
}

public enum GuardedShortcut: String, Codable, CaseIterable, Sendable {
    case quit, closeWindow

    /// Virtual key code (kVK_ANSI_Q = 12, kVK_ANSI_W = 13), pressed with ⌘ alone.
    public var keyCode: UInt16 { self == .quit ? 12 : 13 }
    public var symbol: String { self == .quit ? "⌘Q" : "⌘W" }
}

public struct QuitGuardSettings: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, CaseIterable, Sendable {
        /// Every app except `apps`.
        case allExcept
        /// Only `apps`.
        case only
    }

    /// Off until the user picks a mode: changing what ⌘Q does must be a choice, not an update side effect.
    public var quitMode: QuitGuardMode = .off
    public var closeMode: QuitGuardMode = .off
    public var holdDuration: Double = 0.6
    public var doublePressInterval: Double = 0.5
    public var scope: Scope = .allExcept
    public var apps: [String] = ["com.apple.finder"]

    public static let holdRange: ClosedRange<Double> = 0.3...2
    public static let doublePressRange: ClosedRange<Double> = 0.25...1.2
    public static let storageKey = "MacPocket.quitGuard.settings"

    public init() {}

    public func mode(for shortcut: GuardedShortcut) -> QuitGuardMode { shortcut == .quit ? quitMode : closeMode }

    public var isActive: Bool { quitMode != .off || closeMode != .off }

    public func protects(_ bundleID: String?) -> Bool {
        guard let bundleID else { return scope == .allExcept }
        return scope == .allExcept ? !apps.contains(bundleID) : apps.contains(bundleID)
    }

    public static func load(from defaults: UserDefaults) -> QuitGuardSettings {
        guard let data = defaults.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(QuitGuardSettings.self, from: data) else { return QuitGuardSettings() }
        settings.holdDuration = min(max(settings.holdDuration, holdRange.lowerBound), holdRange.upperBound)
        settings.doublePressInterval = min(max(settings.doublePressInterval, doublePressRange.lowerBound), doublePressRange.upperBound)
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Decides what happens to each press of a guarded shortcut. Pure: the event tap feeds it key events and
/// timer ticks and carries out the returned effects.
public struct QuitGuard: Sendable {
    public enum Event: Equatable, Sendable {
        case keyDown(GuardedShortcut, isRepeat: Bool, at: TimeInterval)
        /// The key or ⌘ was released.
        case released(at: TimeInterval)
        case tick(at: TimeInterval)
    }

    public enum Effect: Equatable, Sendable {
        /// Let the original event through.
        case pass
        /// Drop the original event.
        case swallow
        /// Send the shortcut to the app now (the guard is satisfied).
        case fire(GuardedShortcut)
        /// Show the hint; `progress` is 0…1 while holding, nil for "press again".
        case hint(GuardedShortcut, mode: QuitGuardMode, progress: Double?)
        case hideHint
    }

    private var holding: (shortcut: GuardedShortcut, since: TimeInterval)?
    private var lastPress: (shortcut: GuardedShortcut, at: TimeInterval)?

    public init() {}

    public var isHolding: Bool { holding != nil }

    public mutating func handle(_ event: Event, mode: (GuardedShortcut) -> QuitGuardMode,
                                holdDuration: Double, doublePressInterval: Double) -> [Effect] {
        switch event {
        case let .keyDown(shortcut, isRepeat, time):
            switch mode(shortcut) {
            case .off:
                return [.pass]
            case .hold:
                // Auto-repeat while held is swallowed; only the first press starts the clock.
                if isRepeat || holding?.shortcut == shortcut { return [.swallow] }
                holding = (shortcut, time)
                return [.swallow, .hint(shortcut, mode: .hold, progress: 0)]
            case .doublePress:
                if isRepeat { return [.swallow] }
                if let last = lastPress, last.shortcut == shortcut, time - last.at <= doublePressInterval {
                    lastPress = nil
                    return [.hideHint, .pass]
                }
                lastPress = (shortcut, time)
                return [.swallow, .hint(shortcut, mode: .doublePress, progress: nil)]
            }
        case .released:
            guard holding != nil else { return [] }
            holding = nil
            return [.hideHint]
        case let .tick(time):
            if let current = holding {
                let progress = (time - current.since) / holdDuration
                if progress >= 1 {
                    holding = nil
                    return [.hideHint, .fire(current.shortcut)]
                }
                return [.hint(current.shortcut, mode: .hold, progress: progress)]
            }
            if let last = lastPress, time - last.at > doublePressInterval {
                lastPress = nil
                return [.hideHint]
            }
            return []
        }
    }
}

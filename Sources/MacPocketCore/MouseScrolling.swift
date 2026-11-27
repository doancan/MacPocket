import Foundation

/// Mouse-wheel behaviour, applied only to notched wheels: trackpads and Magic Mouse send continuous events
/// and are never touched, so the system's natural scrolling keeps working for them.
public struct MouseScrollSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var reverseVertical = false
    public var reverseHorizontal = false
    /// Every notch scrolls the same distance, however fast the wheel spins.
    public var linear = true
    public var linesPerNotch = 3
    /// Spread each notch over a short glide instead of a jump.
    public var smooth = false
    public var smoothDurationMilliseconds = 180
    /// Multiplies the distance of each notch.
    public var speed = 1.0
    public var excludedBundleIDs: [String] = []

    public static let linesRange = 1...10
    public static let speedRange = 0.5...3.0
    public static let durationRange = 80...400
    /// Points per line, as the system scrolls a line of text.
    public static let pointsPerLine = 10.0
    public static let storageKey = "MacPocket.mouseScroll.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> MouseScrollSettings {
        guard let data = defaults.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(MouseScrollSettings.self, from: data) else { return MouseScrollSettings() }
        settings.linesPerNotch = min(max(settings.linesPerNotch, linesRange.lowerBound), linesRange.upperBound)
        settings.speed = min(max(settings.speed, speedRange.lowerBound), speedRange.upperBound)
        settings.smoothDurationMilliseconds = min(max(settings.smoothDurationMilliseconds, durationRange.lowerBound), durationRange.upperBound)
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum MouseScrollTransform {
    /// What to do with one wheel event.
    public enum Plan: Equatable, Sendable {
        case pass
        /// Rewrite the event's line deltas (vertical, horizontal).
        case lines(vertical: Int32, horizontal: Int32)
        /// Drop the event and glide this many points instead.
        case glide(vertical: Double, horizontal: Double)
    }

    /// `vertical` and `horizontal` are the event's line deltas (positive: up / left as the system reports
    /// them).
    public static func plan(vertical: Int32, horizontal: Int32, isContinuous: Bool, settings: MouseScrollSettings) -> Plan {
        guard settings.enabled, !isContinuous, vertical != 0 || horizontal != 0 else { return .pass }
        func adjust(_ delta: Int32, reversed: Bool) -> Double {
            guard delta != 0 else { return 0 }
            let sign: Double = (delta > 0) != reversed ? 1 : -1
            let magnitude = settings.linear ? Double(min(10, max(1, settings.linesPerNotch))) : abs(Double(delta))
            let speed = settings.speed.isFinite ? min(3, max(0.5, settings.speed)) : 1
            // Bound every downstream line→point conversion, including malformed HID packets.
            return sign * min(10_000, magnitude * speed)
        }
        let lines = (adjust(vertical, reversed: settings.reverseVertical), adjust(horizontal, reversed: settings.reverseHorizontal))
        if settings.smooth {
            return .glide(vertical: lines.0 * MouseScrollSettings.pointsPerLine, horizontal: lines.1 * MouseScrollSettings.pointsPerLine)
        }
        let rounded = (Int32(lines.0.rounded()), Int32(lines.1.rounded()))
        // A small speed must still move at least one line per notch.
        func atLeastOne(_ value: Int32, _ source: Double) -> Int32 { value == 0 && source != 0 ? (source > 0 ? 1 : -1) : value }
        return .lines(vertical: atLeastOne(rounded.0, lines.0), horizontal: atLeastOne(rounded.1, lines.1))
    }
}

/// Spreads queued scroll distance over frames with an ease-out curve. New notches add to what's left, so fast
/// spinning accelerates naturally instead of queueing slow glides.
public struct SmoothScroller: Sendable {
    public private(set) var remaining: (vertical: Double, horizontal: Double) = (0, 0)
    private var framesLeft = 0

    public init() {}

    public var isIdle: Bool { framesLeft == 0 }

    public mutating func add(vertical: Double, horizontal: Double, frames: Int) {
        guard vertical.isFinite, horizontal.isFinite else { return }
        remaining.vertical = min(1_000_000, max(-1_000_000, remaining.vertical + vertical))
        remaining.horizontal = min(1_000_000, max(-1_000_000, remaining.horizontal + horizontal))
        framesLeft = min(240, max(1, frames))
    }

    /// The distance for the next frame; ease-out: a third of what's left, everything on the last frame.
    public mutating func nextFrame() -> (vertical: Double, horizontal: Double) {
        guard framesLeft > 0 else { return (0, 0) }
        let share = framesLeft == 1 ? 1 : max(1.0 / Double(framesLeft), 1.0 / 3.0)
        let step = (remaining.vertical * share, remaining.horizontal * share)
        remaining.vertical -= step.0
        remaining.horizontal -= step.1
        framesLeft -= 1
        if framesLeft == 0 { remaining = (0, 0) }
        return step
    }
}

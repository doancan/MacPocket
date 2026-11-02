import Foundation

/// The user's macOS Night Shift settings, as captured before MacPocket takes over.
public struct NightShiftState: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var strength: Double
    /// 0 = no macOS schedule, 1 = sunset to sunrise, 2 = custom schedule.
    public var mode: Int

    public init(enabled: Bool, strength: Double, mode: Int) {
        self.enabled = enabled
        self.strength = strength
        self.mode = mode
    }
}

public protocol NightShiftControlling: AnyObject {
    var isAvailable: Bool { get }
    func snapshot() -> NightShiftState?
    /// Drives Night Shift directly; implementations turn off the macOS schedule so it does not fight back.
    func apply(enabled: Bool, strength: Double)
    func restore(_ state: NightShiftState)
}

public enum NightShiftStrength {
    /// Maps a colour temperature to Night Shift strength: 6500 K → 0, 1900 K → 1, clamped.
    public static func from(kelvin: Double) -> Double {
        min(max((6500 - kelvin) / (6500 - 1900), 0), 1)
    }
}

/// Drives Night Shift while remembering the user's previous state, persisted so a crash
/// mid-session can be undone on the next launch.
public final class NightShiftSession {
    private let client: NightShiftControlling
    private let load: () -> NightShiftState?
    private let save: (NightShiftState?) -> Void
    private var previous: NightShiftState?

    public init(client: NightShiftControlling, load: @escaping () -> NightShiftState?, save: @escaping (NightShiftState?) -> Void) {
        self.client = client
        self.load = load
        self.save = save
    }

    /// Call once at launch, before anything else drives Night Shift.
    public func recoverIfNeeded() {
        guard previous == nil, let leftover = load() else { return }
        client.restore(leftover)
        save(nil)
    }

    public func activate(strength: Double) {
        guard client.isAvailable else { return }
        if previous == nil {
            if let persisted = load() {
                // A snapshot left by a crashed run is the user's real previous state.
                previous = persisted
            } else if let current = client.snapshot() {
                previous = current
                save(current)
            } else {
                return
            }
        }
        client.apply(enabled: true, strength: strength)
    }

    public func deactivate() {
        guard let state = previous ?? load() else { return }
        client.restore(state)
        previous = nil
        save(nil)
    }
}

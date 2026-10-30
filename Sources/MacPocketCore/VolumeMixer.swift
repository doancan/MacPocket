import Foundation

/// Per-app volume: 0…1.5 (above 1 boosts quiet apps), with mute. Apps at 100 % and unmuted are left alone, so
/// nothing is tapped unless the user changed something.
public struct VolumeMixerSettings: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var volume: Double
        public var muted: Bool

        public init(volume: Double = 1, muted: Bool = false) {
            self.volume = min(max(volume, 0), VolumeMixerSettings.maximumVolume)
            self.muted = muted
        }

        public var gain: Float { muted ? 0 : Float(volume) }
        public var isNeutral: Bool { !muted && abs(volume - 1) < 0.005 }
    }

    public static let maximumVolume = 1.5
    public static let storageKey = "MacPocket.mixer.settings"

    /// By bundle ID, so a setting survives relaunching the app.
    public var entries: [String: Entry] = [:]

    public init() {}

    public func entry(for bundleID: String) -> Entry { entries[bundleID] ?? Entry() }

    public static func load(from defaults: UserDefaults) -> VolumeMixerSettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(VolumeMixerSettings.self, from: $0) } ?? VolumeMixerSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Real-time gain for the audio thread: no allocation, no locks. Boosted samples are soft-limited instead of
/// hard-clipped, so going above 100 % doesn't crackle.
public enum AudioGain {
    /// Copies `input` to `output` scaled by `gain`. Extra output samples are silenced.
    public static func apply(gain: Float, input: UnsafeBufferPointer<Float>, output: UnsafeMutableBufferPointer<Float>) {
        let count = min(input.count, output.count)
        if gain == 1 {
            for index in 0..<count { output[index] = input[index] }
        } else if gain <= 1 {
            for index in 0..<count { output[index] = input[index] * gain }
        } else {
            for index in 0..<count { output[index] = limit(input[index] * gain) }
        }
        if output.count > count {
            for index in count..<output.count { output[index] = 0 }
        }
    }

    /// Linear up to 0.8, then a smooth knee that never exceeds ±1.
    @inline(__always)
    public static func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > 0.8 else { return sample }
        let over = magnitude - 0.8
        let squeezed = 0.8 + 0.2 * (over / (over + 0.2))
        return sample < 0 ? -squeezed : squeezed
    }
}

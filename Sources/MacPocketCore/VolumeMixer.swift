import Foundation

/// Per-app gain and preferred output. Native audio is untouched when both gain and route are neutral.
public struct VolumeMixerSettings: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var volume: Double
        public var muted: Bool
        /// Nil follows the system. A missing preferred device temporarily falls back to the system output.
        public var outputUID: String?
        public var outputName: String?

        public init(volume: Double = 1, muted: Bool = false, outputUID: String? = nil, outputName: String? = nil) {
            self.volume = volume.isFinite ? min(max(volume, 0), VolumeMixerSettings.maximumVolume) : 1
            self.muted = muted
            self.outputUID = outputUID.flatMap { $0.isEmpty || $0.utf8.count > 1024 ? nil : $0 }
            self.outputName = self.outputUID == nil ? nil : outputName.map { String($0.prefix(256)) }
        }

        private enum CodingKeys: String, CodingKey { case volume, muted, outputUID, outputName }
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(volume: try values.decodeIfPresent(Double.self, forKey: .volume) ?? 1,
                      muted: try values.decodeIfPresent(Bool.self, forKey: .muted) ?? false,
                      outputUID: try values.decodeIfPresent(String.self, forKey: .outputUID),
                      outputName: try values.decodeIfPresent(String.self, forKey: .outputName))
        }

        public var gain: Float { muted ? 0 : Float(volume.isFinite ? min(max(volume, 0), VolumeMixerSettings.maximumVolume) : 1) }
        public var isNeutralGain: Bool { !muted && volume.isFinite && abs(volume - 1) < 0.005 }
        public var isNeutral: Bool { isNeutralGain && outputUID == nil }
    }

    public static let maximumVolume = 1.5
    public static let storageKey = "MacPocket.mixer.settings"

    /// By bundle ID, so a setting survives relaunching the app.
    public var entries: [String: Entry] = [:]

    public init() {}

    public func entry(for bundleID: String) -> Entry { entries[bundleID] ?? Entry() }

    /// True when at least one app needs a tap, so the mixer has to keep watching for audio apps.
    public var hasActiveEntries: Bool { entries.values.contains { !$0.isNeutral } }

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
        guard sample.isFinite else { return 0 }
        let magnitude = abs(sample)
        guard magnitude > 0.8 else { return sample }
        let over = magnitude - 0.8
        let squeezed = 0.8 + 0.2 * (over / (over + 0.2))
        return sample < 0 ? -squeezed : squeezed
    }
}

public struct MixerOutputResolution: Equatable, Sendable {
    public let effectiveUID: String?
    public let preferredUnavailable: Bool
    public let needsTap: Bool
    public static func resolve(entry: VolumeMixerSettings.Entry, devices: [AudioOutputDevice], defaultUID: String?) -> Self {
        let preferred = entry.outputUID.flatMap { uid in devices.first { $0.uid == uid }?.uid }
        let fallback = defaultUID.flatMap { uid in devices.first { $0.uid == uid }?.uid }
        let effective = preferred ?? fallback
        return Self(effectiveUID: effective, preferredUnavailable: entry.outputUID != nil && preferred == nil,
                    needsTap: effective != nil && !entry.isNeutral)
    }
}

/// One build owns one row token. Late completions cannot clear or replace a newer build.
public struct MixerBuildRegistry: Sendable {
    private var next: UInt64 = 0
    private var tokens: [String: UInt64] = [:]
    public init() {}
    public var count: Int { tokens.count }
    public mutating func begin(_ id: String) -> UInt64? {
        guard tokens[id] == nil else { return nil }
        next &+= 1; tokens[id] = next; return next
    }
    public func owns(_ id: String, token: UInt64) -> Bool { tokens[id] == token }
    @discardableResult public mutating func finish(_ id: String, token: UInt64) -> Bool {
        guard owns(id, token: token) else { return false }
        tokens[id] = nil; return true
    }
    public mutating func invalidate(_ id: String) { tokens[id] = nil }
    public mutating func invalidateAll() { tokens = [:] }
}

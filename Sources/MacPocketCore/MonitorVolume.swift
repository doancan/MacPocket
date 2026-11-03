import Foundation

/// A volume key press. Like the brightness keys, they arrive either as system-defined media events or, from some
/// keyboards, as ordinary key events with their own key codes.
public enum VolumeKey: Equatable, Sendable {
    case up, down, mute

    /// Ordinary key event: kVK_VolumeUp 72, kVK_VolumeDown 73, kVK_Mute 74.
    public init?(keyCode: Int64) {
        switch keyCode {
        case 72: self = .up
        case 73: self = .down
        case 74: self = .mute
        default: return nil
        }
    }

    /// System-defined event of subtype 8: NX_KEYTYPE_SOUND_UP 0, NX_KEYTYPE_SOUND_DOWN 1, NX_KEYTYPE_MUTE 7.
    public init?(systemDefinedSubtype subtype: Int, data1: Int) {
        guard subtype == 8 else { return nil }
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 0: self = .up
        case 1: self = .down
        case 7: self = .mute
        default: return nil
        }
    }
}

/// A monitor speaker's volume as the keys see it. Mute keeps the level, so unmuting returns to it.
public struct MonitorVolumeState: Equatable, Sendable {
    public var level: Double
    public var muted: Bool

    public init(level: Double, muted: Bool = false) {
        self.level = min(1, max(0, level))
        self.muted = muted
    }

    /// What the speaker should play at: silent while muted.
    public var effectiveLevel: Double { muted ? 0 : level }

    /// As on a Mac's own speakers: mute toggles, and up or down also unmute and step from the kept level.
    public mutating func apply(_ key: VolumeKey, fine: Bool) {
        switch key {
        case .mute:
            muted.toggle()
        case .up, .down:
            muted = false
            level = BrightnessStep.next(from: level, up: key == .up, step: fine ? BrightnessStep.fine : BrightnessStep.normal)
        }
    }
}

/// Decides when MacPocket, not macOS, answers the volume keys, and which screen is the speaker.
public enum MonitorVolumeRouting {
    /// Only a monitor's speakers (HDMI or DisplayPort) whose volume macOS cannot change itself.
    public static func controlsOutput(kind: AudioOutputDevice.Kind, systemVolumeSettable: Bool) -> Bool {
        kind == .display && !systemVolumeSettable
    }

    /// The screen whose name matches the audio device's name: exactly (ignoring case) first, otherwise the one
    /// name containing the other. Nil when no screen or more than one screen matches loosely.
    public static func display(forAudioDevice audioName: String, screens: [(id: UInt32, name: String)]) -> UInt32? {
        let wanted = audioName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return nil }
        if let exact = screens.first(where: { $0.name.lowercased() == wanted }) { return exact.id }
        let loose = screens.filter { screen in
            let name = screen.name.lowercased()
            return !name.isEmpty && (name.contains(wanted) || wanted.contains(name))
        }
        return loose.count == 1 ? loose[0].id : nil
    }

    /// DDC/CI audio mute (VCP 0x8D) replies 1 for muted and 2 for unmuted; anything else means unsupported.
    public static func muteState(fromReply value: UInt16?) -> Bool? {
        switch value {
        case 1: true
        case 2: false
        default: nil
        }
    }
}

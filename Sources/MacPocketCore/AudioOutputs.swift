import CoreAudio
import Foundation

public struct AudioOutputDevice: Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case builtIn, headphones, bluetooth, usb, display, airPlay, virtual, other }

    public var id: String { uid }
    public let objectID: AudioObjectID
    /// Stable across reboots and reconnections, unlike the object ID.
    public let uid: String
    public let name: String
    public let kind: Kind

    public init(objectID: AudioObjectID, uid: String, name: String, kind: Kind) {
        self.objectID = objectID; self.uid = uid; self.name = name; self.kind = kind
    }

    /// Personal outputs: leaving them for speakers is the moment to turn the volume down.
    public var isPersonal: Bool { kind == .headphones || kind == .bluetooth }
}

public struct AudioOutputSettings: Codable, Equatable, Sendable {
    /// Devices the shortcut cycles through, by UID; empty cycles through all of them.
    public var cycle: [String] = []
    public var shortcut: KeyCombo? = KeyCombo(keyCode: 0, modifiers: [.control, .option, .shift]) // ⌃⌥⇧A
    /// When personal audio disconnects and sound falls back to speakers, set this volume (nil: leave it).
    public var speakerVolumeAfterHeadphones: Double? = 0.25
    public static let storageKey = "MacPocket.audio.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> AudioOutputSettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(AudioOutputSettings.self, from: $0) } ?? AudioOutputSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum AudioOutputRules {
    /// The device after `current` among those in the cycle that are connected now, wrapping around.
    public static func next(after current: String?, devices: [AudioOutputDevice], cycle: [String]) -> AudioOutputDevice? {
        let candidates = cycle.isEmpty ? devices : cycle.compactMap { uid in devices.first { $0.uid == uid } }
        guard !candidates.isEmpty else { return nil }
        guard let current, let index = candidates.firstIndex(where: { $0.uid == current }) else { return candidates.first }
        return candidates[(index + 1) % candidates.count]
    }

    /// The volume to set when the default output changes from `old` to `new`; nil leaves it alone.
    public static func volumeAfterSwitch(from old: AudioOutputDevice?, to new: AudioOutputDevice?, settings: AudioOutputSettings) -> Double? {
        guard let level = settings.speakerVolumeAfterHeadphones, let old, let new, old.isPersonal, !new.isPersonal else { return nil }
        return level
    }
}

/// Reads and changes the system output through Core Audio.
public enum AudioOutputSystem {
    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    public static func outputDevices() -> [AudioOutputDevice] {
        var listAddress = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputStreams(id), let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioOutputDevice(objectID: id, uid: uid, name: name, kind: kind(id, name: name))
        }
    }

    public static var defaultOutput: AudioObjectID? {
        var outputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddress, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    @discardableResult
    public static func setDefaultOutput(_ id: AudioObjectID) -> Bool {
        var outputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddress, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }

    /// Output volume 0…1 (the main element, or the first two channels when there is no main control).
    public static func volume(of id: AudioObjectID) -> Double? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var volumeAddress = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(id, &volumeAddress), AudioObjectGetPropertyData(id, &volumeAddress, 0, nil, &size, &value) == noErr {
                return Double(value)
            }
        }
        return nil
    }

    @discardableResult
    public static func setVolume(_ level: Double, of id: AudioObjectID) -> Bool {
        var changed = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var volumeAddress = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectHasProperty(id, &volumeAddress), AudioObjectIsPropertySettable(id, &volumeAddress, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = Float32(min(max(level, 0), 1))
            if AudioObjectSetPropertyData(id, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr { changed = true }
            if element == kAudioObjectPropertyElementMain && changed { break }
        }
        return changed
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var streamsAddress = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var stringAddress = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &stringAddress, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func kind(_ id: AudioObjectID, name: String) -> AudioOutputDevice.Kind {
        var transportAddress = address(kAudioDevicePropertyTransportType)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &size, &transport)
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
        case kAudioDeviceTransportTypeBuiltIn:
            // The built-in jack shows up as a built-in device whose data source is headphones.
            return jackIsHeadphones(id) ? .headphones : .builtIn
        default: return .other
        }
    }

    private static func jackIsHeadphones(_ id: AudioObjectID) -> Bool {
        var sourceAddress = address(kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
        var source = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &sourceAddress), AudioObjectGetPropertyData(id, &sourceAddress, 0, nil, &size, &source) == noErr else { return false }
        return source == 0x6864_706E // 'hdpn'
    }
}

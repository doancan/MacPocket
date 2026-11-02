import CoreAudio
import CoreMediaIO
import Foundation

public enum PrivacyDevice: String, Codable, CaseIterable, Sendable {
    case microphone, camera
}

/// One app (or, when macOS doesn't say which, nobody) using a microphone or camera right now.
/// Identity is device + bundle ID; the name is only for display.
public struct PrivacyActivity: Hashable, Identifiable, Sendable {
    public let device: PrivacyDevice
    /// Nil when the owner is unknown: macOS names no app for the camera.
    public let bundleID: String?
    public let appName: String?

    public init(device: PrivacyDevice, bundleID: String?, appName: String?) {
        self.device = device; self.bundleID = bundleID; self.appName = appName
    }

    public var id: String { device.rawValue + "/" + (bundleID ?? "") }

    public static func == (lhs: PrivacyActivity, rhs: PrivacyActivity) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public static let storageKey = "MacPocket.privacy.settings"

    /// Off until the user turns it on: watching and notifying are opt-in.
    public var isEnabled = false
    /// Apps that never trigger a notification, by bundle ID, with the name shown in the list.
    public var ignoredApps: [String: String] = [:]

    public init() {}

    public static func load(from defaults: UserDefaults) -> PrivacySettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(PrivacySettings.self, from: $0) } ?? PrivacySettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Turns successive readings into "just started" events: what is new since the last reading, minus ignored apps and
/// anything that already alerted within the cooldown (a call app that restarts its capture shouldn't buzz twice).
public struct PrivacyChangeTracker: Sendable {
    public let cooldown: TimeInterval
    private var previous: Set<PrivacyActivity> = []
    private var lastAlerted: [String: Date] = [:]

    public init(cooldown: TimeInterval = 30) { self.cooldown = cooldown }

    public mutating func update(current: Set<PrivacyActivity>, ignoredApps: Set<String>, now: Date) -> [PrivacyActivity] {
        let started = current.subtracting(previous)
        previous = current
        let due = started.filter { activity in
            if let bundleID = activity.bundleID, ignoredApps.contains(bundleID) { return false }
            guard let last = lastAlerted[activity.id] else { return true }
            return now < last || now.timeIntervalSince(last) >= cooldown
        }
        for activity in due { lastAlerted[activity.id] = now }
        return due.sorted { $0.id < $1.id }
    }
}

public struct RunningAppInfo: Sendable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String

    public init(pid: pid_t, bundleID: String, name: String) {
        self.pid = pid; self.bundleID = bundleID; self.name = name
    }
}

public enum PrivacyAppOwner {
    /// The app a Core Audio process belongs to: same PID, else the app whose bundle ID prefixes the helper's
    /// (`com.google.Chrome.helper…` → Chrome). Prefix match needs the dot, so `…Chromium` is not Chrome's helper.
    public static func resolve(pid: pid_t, processBundleID: String, apps: [RunningAppInfo]) -> RunningAppInfo? {
        if let app = apps.first(where: { $0.pid == pid }) { return app }
        guard !processBundleID.isEmpty else { return nil }
        return apps.filter { processBundleID.hasPrefix($0.bundleID + ".") }.max { $0.bundleID.count < $1.bundleID.count }
    }
}

/// Reads who is using the microphone and camera. Neither needs a permission: these are the same "running
/// somewhere" flags macOS uses for its own indicators. Blocking Core Audio calls: run off the main thread.
public enum PrivacyProbe {
    public static func activities(apps: [RunningAppInfo], ownPID: pid_t = getpid()) -> Set<PrivacyActivity> {
        var result = microphoneActivities(apps: apps, ownPID: ownPID)
        if cameraIsRunning() { result.insert(PrivacyActivity(device: .camera, bundleID: nil, appName: nil)) }
        return result
    }

    // MARK: Microphone

    static func microphoneActivities(apps: [RunningAppInfo], ownPID: pid_t) -> Set<PrivacyActivity> {
        guard let processes = audioProcessObjects() else { return deviceLevelMicrophone(ownApp: false) }
        var result = Set<PrivacyActivity>()
        for object in processes {
            guard (value(object, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0) != 0,
                  let pid = value(object, kAudioProcessPropertyPID, as: pid_t.self), pid != ownPID else { continue }
            let processBundle = string(object, kAudioProcessPropertyBundleID) ?? ""
            if let owner = PrivacyAppOwner.resolve(pid: pid, processBundleID: processBundle, apps: apps) {
                result.insert(PrivacyActivity(device: .microphone, bundleID: owner.bundleID, appName: owner.name))
            } else if !processBundle.isEmpty {
                result.insert(PrivacyActivity(device: .microphone, bundleID: processBundle, appName: nil))
            } else {
                result.insert(PrivacyActivity(device: .microphone, bundleID: nil, appName: nil))
            }
        }
        return result
    }

    /// Fallback when the per-process list cannot be read: only "an input device is running", owner unknown.
    private static func deviceLevelMicrophone(ownApp: Bool) -> Set<PrivacyActivity> {
        guard !ownApp, inputDeviceIsRunning() else { return [] }
        return [PrivacyActivity(device: .microphone, bundleID: nil, appName: nil)]
    }

    private static func audioProcessObjects() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        return objects
    }

    private static func inputDeviceIsRunning() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return false }
            return (value(device, kAudioDevicePropertyDeviceIsRunningSomewhere, as: UInt32.self) ?? 0) != 0
        }
    }

    // MARK: Camera

    static func cameraIsRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var flag: UInt32 = 0
            var flagUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &flagUsed, &flag)
            return status == noErr && flag != 0
        }
    }

    // MARK: Core Audio property helpers

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

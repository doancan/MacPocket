import AppKit
import CoreAudio
import MacPocketCore

struct MixerProcess: Equatable, Sendable {
    let object: AudioObjectID
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    init(object: AudioObjectID, pid: pid_t, startSeconds: UInt64 = 0, startMicroseconds: UInt64 = 0) {
        self.object = object
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }
}

struct AudioApp: Identifiable, Equatable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let processes: [MixerProcess]
    let launchTime: TimeInterval
    let playing: Bool
    let sourceDevices: [AudioObjectID]
    var processObjects: [AudioObjectID] { processes.map(\.object) }
}

struct MixerDeviceState: Equatable, Sendable {
    let device: AudioOutputDevice
    let sampleRate: Double
    let channels: UInt32
    let formats: [UInt64]
}

/// Captured on the main actor; Core Audio never reads NSRunningApplication from a worker queue.
struct MixerRunningApp: Sendable {
    let pid: pid_t
    let bundleID: String
    let name: String
    let launchTime: TimeInterval

    @MainActor static func snapshot() -> [Self] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, app.processIdentifier != getpid() else { return nil }
            return Self(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? id,
                        launchTime: app.launchDate?.timeIntervalSince1970 ?? 0)
        }.sorted { $0.bundleID.count > $1.bundleID.count }
    }
}

struct MixerInventory: Sendable {
    let apps: [AudioApp]
    let devices: [MixerDeviceState]
    let defaultUID: String?

    /// All device/process property reads happen off the UI thread, including reads triggered by device
    /// listeners.
    static func read(running: [MixerRunningApp]) throws -> Self {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let objects: [AudioObjectID] = array(system, kAudioHardwarePropertyProcessObjectList) else {
            throw InventoryError.unavailable
        }
        let devices = AudioOutputSystem.outputDevices().filter {
            value($0.objectID, kAudioDevicePropertyDeviceIsAlive, as: UInt32.self) != 0
        }.map { device in
            let rate = value(device.objectID, kAudioDevicePropertyNominalSampleRate, as: Float64.self) ?? 0
            let streams: [AudioObjectID] = array(device.objectID, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput) ?? []
            var channels: UInt32 = 0
            var formats: [UInt64] = []
            for stream in streams {
                guard let format = value(stream, kAudioStreamPropertyVirtualFormat, as: AudioStreamBasicDescription.self) else { continue }
                channels += format.mChannelsPerFrame
                formats += [UInt64(stream), format.mSampleRate.bitPattern, UInt64(format.mFormatID), UInt64(format.mFormatFlags),
                            UInt64(format.mChannelsPerFrame), UInt64(format.mBytesPerFrame), UInt64(format.mBitsPerChannel)]
            }
            return MixerDeviceState(device: device, sampleRate: rate, channels: channels, formats: formats)
        }.sorted { $0.device.name.localizedStandardCompare($1.device.name) == .orderedAscending }
        let defaultID = AudioOutputSystem.defaultOutput
        var grouped: [String: (MixerRunningApp, [MixerProcess], Bool, Set<AudioObjectID>)] = [:]
        for object in objects {
            guard let pid = value(object, kAudioProcessPropertyPID, as: pid_t.self), pid > 0, pid != getpid(),
                  let identity = processIdentity(pid) else { continue }
            let bundle = string(object, kAudioProcessPropertyBundleID) ?? ""
            // Exact process first; longest app prefix next. Helpers cannot be assigned to a shorter sibling
            // prefix.
            guard let owner = running.first(where: { $0.pid == pid })
                    ?? running.first(where: { bundle == $0.bundleID || bundle.hasPrefix($0.bundleID + ".") }) else { continue }
            let playing = value(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            let sourceDevices: [AudioObjectID] = array(object, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput) ?? []
            var row = grouped[owner.bundleID] ?? (owner, [], false, [])
            row.1.append(.init(object: object, pid: pid, startSeconds: identity.0, startMicroseconds: identity.1))
            row.2 = row.2 || playing
            row.3.formUnion(sourceDevices)
            grouped[owner.bundleID] = row
        }
        let apps = grouped.map { id, row in
            AudioApp(bundleID: id, name: row.0.name, processes: row.1.sorted { $0.object < $1.object },
                     launchTime: row.0.launchTime, playing: row.2, sourceDevices: row.3.sorted())
        }.sorted { ($0.playing ? 0 : 1, $0.name) < ($1.playing ? 0 : 1, $1.name) }
        return Self(apps: apps, devices: devices, defaultUID: devices.first { $0.device.objectID == defaultID }?.device.uid)
    }

    static func processesStillMatch(_ processes: [MixerProcess]) -> Bool {
        !processes.isEmpty && processes.allSatisfy {
            guard value($0.object, kAudioProcessPropertyPID, as: pid_t.self) == $0.pid,
                  let identity = processIdentity($0.pid) else { return false }
            return identity.0 == $0.startSeconds && identity.1 == $0.startMicroseconds
        }
    }

    private static func processIdentity(_ pid: pid_t) -> (UInt64, UInt64)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return (info.pbi_start_tvsec, info.pbi_start_tvusec)
    }

    enum InventoryError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Ses uygulamaları okunamadı. Yenileyerek tekrar dene.") }
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr, size == MemoryLayout<T>.size else { return nil }
        return pointer.pointee
    }

    private static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [T]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size <= 1_048_576, Int(size).isMultiple(of: MemoryLayout<T>.stride) else { return nil }
        guard size > 0 else { return [] }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        let capacity = size
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr, size <= capacity,
              Int(size).isMultiple(of: MemoryLayout<T>.stride) else { return nil }
        return Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: T.self), count: Int(size) / MemoryLayout<T>.stride))
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var text: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &text) == noErr, let text else { return nil }
        return text.takeRetainedValue() as String
    }
}

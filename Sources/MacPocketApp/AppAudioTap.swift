import AVFoundation
import CoreAudio
import MacPocketCore
import Synchronization

/// Native capture and output have separate clocks. The ring handles drift; AVAudioEngine handles nominal
/// sample-rate/channel conversion. All setup/teardown is serialized off the main thread by the mixer.
protocol MixerAudioPath: AnyObject, Sendable {
    var gain: AudioRenderGain { get }
    var needsRebuild: Bool { get }
    var progress: (capture: UInt64, output: UInt64)? { get }
    func invalidate()
}

final class MixerBuildCancellation: Sendable {
    private let flag = Atomic<Bool>(false)
    var isCancelled: Bool { flag.load(ordering: .acquiring) }
    func cancel() { flag.store(true, ordering: .releasing) }
    func check() throws { if isCancelled { throw CancellationError() } }
}

final class AppAudioTap: MixerAudioPath, @unchecked Sendable {
    enum Stage: Sendable {
        case tap, format, captureDevice, captureStart, outputDevice, outputStart
        var localizedTitle: String {
            switch self {
            case .tap: String(localized: "Uygulama sesini yakalama")
            case .format: String(localized: "Ses biçimi")
            case .captureDevice: String(localized: "Yakalama aygıtı")
            case .captureStart: String(localized: "Ses yakalamayı başlatma")
            case .outputDevice: String(localized: "Çıkış aygıtı")
            case .outputStart: String(localized: "Sesi çalma")
            }
        }
    }
    struct Failure: Error, LocalizedError {
        let stage: Stage
        let status: OSStatus
        var errorDescription: String? { String(localized: "Ses yolu kurulamadı: \(stage.localizedTitle) (\(status)).") }
    }
    private final class Health: Sendable { let changed = Atomic<Bool>(false) }
    let gain: AudioRenderGain
    private(set) var ring: AudioFrameRing?
    private let health = Health()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var observer: NSObjectProtocol?
    private let captureQueue = DispatchQueue(label: "MacPocket.mixer.capture", qos: .userInteractive)
    var needsRebuild: Bool { health.changed.load(ordering: .relaxed) }
    var progress: (capture: UInt64, output: UInt64)? { ring.map { ($0.counters.capture, $0.counters.output) } }

    init(processes: [MixerProcess], outputUID: String, gain: AudioRenderGain,
         cancellation: MixerBuildCancellation, compensation: Float = 1) throws {
        self.gain = gain
        do {
            try cancellation.check()
            guard MixerInventory.processesStillMatch(processes) else { throw Failure(stage: .tap, status: kAudioHardwareBadObjectError) }
            let description = CATapDescription(stereoMixdownOfProcesses: processes.map(\.object))
            description.uuid = UUID()
            description.name = "MacPocket"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            var status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr else { throw Failure(stage: .tap, status: status) }
            try cancellation.check()
            var format = try Self.property(tapID, selector: kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
            guard AudioFrameRing.supportsPCM(format) else {
                throw Failure(stage: .format, status: kAudioFormatUnsupportedDataFormatError)
            }
            let tapUID = try Self.string(tapID, selector: kAudioTapPropertyUID)
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MacPocket Capture",
                kAudioAggregateDeviceUIDKey: "MacPocket.capture.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
            ]
            status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
            guard status == noErr else { throw Failure(stage: .captureDevice, status: status) }
            // The actual aggregate input format governs its callback, rather than assuming the tap layout.
            format = try Self.property(aggregateID, selector: kAudioDevicePropertyStreamFormat, scope: kAudioDevicePropertyScopeInput,
                                       as: AudioStreamBasicDescription.self)
            guard AudioFrameRing.supportsPCM(format),
                  let canonical = AVAudioFormat(standardFormatWithSampleRate: format.mSampleRate, channels: 2) else {
                throw Failure(stage: .format, status: kAudioFormatUnsupportedDataFormatError)
            }
            let ring = AudioFrameRing(sampleRate: format.mSampleRate)
            self.ring = ring
            let engine = AVAudioEngine()
            self.engine = engine
            guard let outputID = AudioOutputSystem.outputDevices().first(where: { $0.uid == outputUID })?.objectID else {
                throw Failure(stage: .outputDevice, status: kAudioHardwareBadDeviceError)
            }
            try engine.outputNode.withAudioUnit { unit in
                guard let unit else { throw Failure(stage: .outputDevice, status: kAudioHardwareBadDeviceError) }
                var device = outputID
                let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                 &device, UInt32(MemoryLayout<AudioObjectID>.size))
                guard status == noErr else { throw Failure(stage: .outputDevice, status: status) }
                var actual = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
                let readStatus = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actual, &size)
                guard readStatus == noErr, actual == outputID else { throw Failure(stage: .outputDevice, status: kAudioHardwareBadDeviceError) }
            }
            let source = AVAudioSourceNode(format: canonical) { _, _, frames, output in
                let buffers = UnsafeMutableAudioBufferListPointer(output)
                for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
                guard buffers.count == 2, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                      let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                let count = min(Int(frames), Int(buffers[0].mDataByteSize) / 4, Int(buffers[1].mDataByteSize) / 4)
                ring.read(left: UnsafeMutableBufferPointer(start: l, count: count), right: UnsafeMutableBufferPointer(start: r, count: count),
                          gain: gain.value, compensation: compensation)
                return noErr
            }
            self.source = source
            engine.attach(source)
            do { try engine.connectNode(source, to: engine.mainMixerNode, format: canonical) }
            catch { throw Failure(stage: .outputStart, status: OSStatus((error as NSError).code)) }
            engine.mainMixerNode.outputVolume = 1
            engine.prepare()
            try cancellation.check()
            do { try engine.start() } catch { throw Failure(stage: .outputStart, status: OSStatus((error as NSError).code)) }
            let captureFormat = format
            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, captureQueue) { _, input, _, _, _ in
                ring.writePCM(input, format: captureFormat)
            }
            guard status == noErr else { throw Failure(stage: .captureStart, status: status) }
            // Only now may the original process be muted: a live output engine already exists.
            try cancellation.check()
            guard MixerInventory.processesStillMatch(processes) else { throw Failure(stage: .tap, status: kAudioHardwareBadObjectError) }
            status = AudioDeviceStart(aggregateID, procID)
            guard status == noErr else { throw Failure(stage: .captureStart, status: status) }
            try cancellation.check()
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [health] _ in
                health.changed.store(true, ordering: .relaxed)
            }
        } catch { invalidate()
        throw error }
    }


    deinit { invalidate() }
    func invalidate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        // Stop capture first so mutedWhenTapped releases the original application even if output teardown
        // stalls.
        if aggregateID != kAudioObjectUnknown {
            if let procID { AudioDeviceStop(aggregateID, procID); AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        engine?.stop()
        if let source { engine?.detach(source) }
        engine = nil
        source = nil
        ring = nil
    }

    private static func property<T>(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as type: T.Type) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        guard status == noErr, size == MemoryLayout<T>.size else { throw Failure(stage: .format, status: status) }
        return pointer.pointee
    }
    private static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { throw Failure(stage: .format, status: status) }
        return value.takeRetainedValue() as String
    }
}

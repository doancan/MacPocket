import AppKit
import AudioToolbox
import CoreAudio
import MacPocketCore
import SwiftUI

/// Gain shared with the real-time audio thread; written on main, read per buffer. A torn read of a Float is
/// harmless here (one buffer at the old or new gain).
final class GainBox: @unchecked Sendable {
    nonisolated(unsafe) var value: Float
    init(_ value: Float) { self.value = value }
}

/// One app's audio, captured with a Core Audio process tap (its own output muted while tapped) and played to the
/// current output through a private aggregate device with the chosen gain. Private objects disappear with
/// MacPocket's process, so the app's normal sound returns even after a crash.
/// Created and invalidated only on `VolumeMixerService`'s setup queue; `gain` is the one thing touched elsewhere.
final class AppAudioTap: @unchecked Sendable {
    struct Failure: Error, LocalizedError {
        let step: String
        let status: OSStatus
        var errorDescription: String? { String(localized: "Ses yakalanamadı (\(step): \(status)).") }
    }

    let gain: GainBox
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "MacPocket.mixer.io", qos: .userInteractive)

    init(processObjects: [AudioObjectID], outputUID: String, gain: Float) throws {
        self.gain = GainBox(gain)
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Failure(step: "tap", status: status) }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacPocket Mixer",
            kAudioAggregateDeviceUIDKey: "MacPocket.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { invalidate(); throw Failure(step: "aggregate", status: status) }
        let gainBox = self.gain
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            Self.render(input, output, gain: gainBox.value)
        }
        guard status == noErr else { invalidate(); throw Failure(step: "ioproc", status: status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { invalidate(); throw Failure(step: "start", status: status) }
    }

    deinit { invalidate() }

    func invalidate() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Real-time: tap input → output with gain. Same buffer layout is copied buffer by buffer; one interleaved
    /// input buffer feeding several mono output buffers is de-interleaved.
    private static func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let sources = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let destinations = UnsafeMutableAudioBufferListPointer(output)
        guard !sources.isEmpty else {
            for destination in destinations { if let data = destination.mData { memset(data, 0, Int(destination.mDataByteSize)) } }
            return
        }
        if sources.count == destinations.count || sources.count > 1 {
            for (index, destination) in destinations.enumerated() {
                guard let target = destination.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let targetBuffer = UnsafeMutableBufferPointer(start: target, count: Int(destination.mDataByteSize) / MemoryLayout<Float>.size)
                let source = sources[min(index, sources.count - 1)]
                guard let data = source.mData?.assumingMemoryBound(to: Float.self) else { targetBuffer.update(repeating: 0); continue }
                AudioGain.apply(gain: gain, input: UnsafeBufferPointer(start: data, count: Int(source.mDataByteSize) / MemoryLayout<Float>.size),
                                output: targetBuffer)
            }
            return
        }
        // One interleaved source, several mono destinations.
        let source = sources[0]
        let channels = max(1, Int(source.mNumberChannels))
        guard let data = source.mData?.assumingMemoryBound(to: Float.self) else { return }
        let frames = Int(source.mDataByteSize) / MemoryLayout<Float>.size / channels
        for (index, destination) in destinations.enumerated() {
            guard let target = destination.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let capacity = Int(destination.mDataByteSize) / MemoryLayout<Float>.size
            let channel = min(index, channels - 1)
            for frame in 0..<min(frames, capacity) {
                let sample = data[frame * channels + channel] * gain
                target[frame] = gain > 1 ? AudioGain.limit(sample) : sample
            }
            if capacity > frames { for frame in frames..<capacity { target[frame] = 0 } }
        }
    }
}

/// An app currently producing sound, with the Core Audio process objects that belong to it (helpers included).
struct AudioApp: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let processObjects: [AudioObjectID]
    let playing: Bool
}

@MainActor
final class VolumeMixerService: ObservableObject {
    static let shared = VolumeMixerService()

    @Published var settings = VolumeMixerSettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            apply()
            updatePolling()
        }
    }
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var failure: String?
    private var taps: [String: AppAudioTap] = [:]
    private var tappedOutput: String?
    private var timer: Timer?
    private var viewVisible = false
    /// Core Audio calls that can block for as long as coreaudiod likes (the first one waits on the system-audio
    /// permission prompt) run here, never on the main thread.
    private let setupQueue = DispatchQueue(label: "MacPocket.mixer.setup", qos: .userInitiated)
    private var pending: Set<String> = []
    /// Bumped when the output changes, so a tap finished for the old output is thrown away.
    private var outputGeneration = 0

    private init() {}

    func start() {
        refresh()
        updatePolling()
    }

    func setViewVisible(_ visible: Bool) {
        viewVisible = visible
        if visible { refresh() }
        updatePolling()
    }

    /// The process list is only worth reading while the page shows it or an app has a tap to keep in line.
    private func updatePolling() {
        let needed = viewVisible || settings.hasActiveEntries
        if !needed {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Finds apps with audio and keeps taps in line with the settings and the current output device.
    func refresh() {
        apps = Self.audioApps()
        apply()
    }

    func stopAll() {
        for tap in taps.values { release(tap) }
        taps = [:]
    }

    private func release(_ tap: AppAudioTap) {
        setupQueue.async { tap.invalidate() }
    }

    private func apply() {
        let output = AudioOutputSystem.defaultOutput.flatMap { id in AudioOutputSystem.outputDevices().first { $0.objectID == id }?.uid }
        if output != tappedOutput { // the output changed: rebuild on the new one
            stopAll()
            tappedOutput = output
            outputGeneration += 1
        }
        guard let output else { return }
        let wanted = Dictionary(uniqueKeysWithValues: apps.compactMap { app -> (String, AudioApp)? in
            settings.entry(for: app.bundleID).isNeutral ? nil : (app.bundleID, app)
        })
        for (bundleID, tap) in taps where wanted[bundleID] == nil {
            release(tap)
            taps[bundleID] = nil
        }
        for (bundleID, app) in wanted {
            let gain = settings.entry(for: bundleID).gain
            if let tap = taps[bundleID] {
                tap.gain.value = gain
                continue
            }
            guard !pending.contains(bundleID) else { continue }
            pending.insert(bundleID)
            let generation = outputGeneration
            let objects = app.processObjects
            setupQueue.async { [weak self] in
                let result = Result { try AppAudioTap(processObjects: objects, outputUID: output, gain: gain) }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(bundleID, result, generation: generation) } }
            }
        }
    }

    /// Keeps a finished tap only if it is still wanted on the same output, with the gain as it is now.
    private func finish(_ bundleID: String, _ result: Result<AppAudioTap, Error>, generation: Int) {
        pending.remove(bundleID)
        switch result {
        case let .success(tap):
            let entry = settings.entry(for: bundleID)
            guard generation == outputGeneration, !entry.isNeutral, taps[bundleID] == nil else { release(tap); return }
            tap.gain.value = entry.gain
            taps[bundleID] = tap
            failure = nil
        case let .failure(error):
            failure = error.localizedDescription
        }
    }

    /// Core Audio's process list, grouped by app (helper bundle IDs share the app's prefix).
    private static func audioApps() -> [AudioApp] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        var grouped: [String: (name: String, objects: [AudioObjectID], playing: Bool)] = [:]
        for object in objects {
            guard let pid = Self.value(object, kAudioProcessPropertyPID, as: pid_t.self), pid != getpid() else { continue }
            let processBundle = Self.string(object, kAudioProcessPropertyBundleID) ?? ""
            let playing = (Self.value(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 0) != 0
            let owner = running.first { $0.processIdentifier == pid }
                ?? running.first { app in !processBundle.isEmpty && processBundle.hasPrefix(app.bundleIdentifier! + ".") }
            guard let owner, let bundleID = owner.bundleIdentifier else { continue }
            var entry = grouped[bundleID] ?? (owner.localizedName ?? bundleID, [], false)
            entry.objects.append(object)
            entry.playing = entry.playing || playing
            grouped[bundleID] = entry
        }
        return grouped.map { AudioApp(bundleID: $0.key, name: $0.value.name, processObjects: $0.value.objects, playing: $0.value.playing) }
            .sorted { ($0.playing ? 0 : 1, $0.name) < ($1.playing ? 0 : 1, $1.name) }
    }

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

/// Tools → Ses Mikseri.
struct VolumeMixerView: View {
    @ObservedObject private var service = VolumeMixerService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ses Mikseri",
                              subtitle: "Her uygulamanın sesini ayrı ayarla, sustur ya da %150’ye kadar yükselt; sürücü kurmadan.",
                              icon: "slider.vertical.3") {
                Button { service.refresh() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
            if let failure = service.failure { PocketMessage(failure, tone: .warning) }
            ScrollView {
                VStack(spacing: PocketSpacing.s) {
                    if service.apps.isEmpty {
                        ContentUnavailableView("Ses kullanan uygulama yok", systemImage: "speaker.slash",
                                               description: Text("Bir uygulama ses çalmaya başlayınca burada görünür."))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                    ForEach(service.apps) { app in MixerRow(app: app, service: service) }
                }
                .pocketCard()
                Text("İlk ayarlamada macOS, MacPocket’in sistem sesini kaydetmesine izin isteyebilir: ses yalnız bu Mac’te, seçtiğin seviyeyle yeniden çalınır ve hiçbir yere kaydedilmez. %100’deki uygulamalara dokunulmaz.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PocketSpacing.s)
            }
        }
        .pocketPage()
        .onAppear { service.setViewVisible(true) }
        .onDisappear { service.setViewVisible(false) }
    }
}

private struct MixerRow: View {
    let app: AudioApp
    @ObservedObject var service: VolumeMixerService

    var body: some View {
        let entry = service.settings.entry(for: app.bundleID)
        HStack(spacing: PocketSpacing.m) {
            PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.playing ? "Çalıyor" : "Sessiz").font(.caption).foregroundStyle(app.playing ? PocketTheme.disk : .secondary)
            }
            .frame(width: 160, alignment: .leading)
            Button {
                service.settings.entries[app.bundleID] = .init(volume: entry.volume, muted: !entry.muted)
            } label: {
                Image(systemName: entry.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.muted ? "Sesi aç" : "Sessize al")
            Slider(value: Binding(get: { entry.volume }, set: { service.settings.entries[app.bundleID] = .init(volume: $0, muted: entry.muted) }),
                   in: 0...VolumeMixerSettings.maximumVolume) { Text(app.name) }
                .labelsHidden()
                .disabled(entry.muted)
            Text(verbatim: pocketPercent(entry.volume * 100)).monospacedDigit().foregroundStyle(entry.volume > 1 ? .orange : .secondary)
                .frame(width: 52, alignment: .trailing)
            Button("Sıfırla") { service.settings.entries[app.bundleID] = nil }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(entry.isNeutral)
        }
        .padding(.vertical, PocketSpacing.xs)
    }
}

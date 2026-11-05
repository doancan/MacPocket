#if DEBUG
import AppKit
import AVFoundation
import MacPocketCore
import SwiftUI
import Synchronization

/// Exercises the production coordinator with an injected inventory/renderer. It never creates a process tap,
/// changes hardware routing/volume, or requests system audio permission. Offline rendering is separate evidence.
@MainActor
enum MixerRuntimeAudit {
    private final class Path: MixerAudioPath, Sendable {
        let gain: AudioRenderGain
        let invalidated = Atomic<Bool>(false)
        let changed = Atomic<Bool>(false)
        var needsRebuild: Bool { changed.load(ordering: .relaxed) }
        var progress: (capture: UInt64, output: UInt64)? { (0, 0) }
        init(_ gain: AudioRenderGain) { self.gain = gain }
        func invalidate() { invalidated.store(true, ordering: .relaxed) }
    }
    private struct State: Sendable {
        var inventory: MixerInventory
        var configurations: [MixerPathConfiguration] = []
        var paths: [Path] = []
        var fail = false
        var delay = false
        var entered = false
        var failInventory = false
    }
    private struct TestFailure: LocalizedError {
        var errorDescription: String? { String(localized: "Ses yolu durdu; uygulamanın kendi sesine dönüldü. Yeniden dene.") }
    }

    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested else { return [:] }
        var checks: [String: Bool] = [:]
        let running = MixerRunningApp.snapshot()
        let realInventory = await Task.detached { try? MixerInventory.read(running: running) }.value
        checks["mixerRealInventoryReadable"] = realInventory != nil
        checks["mixerRealDeviceFormatsReadable"] = realInventory?.devices.isEmpty == false
            && realInventory?.devices.allSatisfy { $0.sampleRate.isFinite && $0.sampleRate > 0 && $0.channels > 0 } == true
        checks["mixerRealInventoryExcludesOwnProcess"] = realInventory?.apps.allSatisfy { $0.processes.allSatisfy { $0.pid != getpid() } } == true
        if let realInventory, let data = try? JSONSerialization.data(withJSONObject: [
            "outputDevices": realInventory.devices.count, "audioApplications": realInventory.apps.count,
            "processIdentities": realInventory.apps.reduce(0) { $0 + $1.processes.count },
        ], options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: destination.appendingPathExtension("mixer-inventory.json")) }
        let speakers = device(10, uid: "audit.speakers", name: "Studio Speakers", rate: 48_000)
        let headset = device(20, uid: "audit.headset", name: "USB Headset — Conference Audio", rate: 44_100)
        let app = AudioApp(bundleID: "com.macpocket.audit.music", name: "Music Player — A Long Application Name",
                           processes: [.init(object: 100, pid: 900)], launchTime: 1, playing: false, sourceDevices: [10])
        let state = Mutex(State(inventory: .init(apps: [app], devices: [speakers, headset], defaultUID: speakers.device.uid)))
        let gate = DispatchSemaphore(value: 0)
        let suite = "com.doancan.MacPocket.MixerAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { return ["mixerAuditDefaults": false] }
        let service = VolumeMixerService(defaults: defaults, observesHardware: false, readInventory: { _ in
            try state.withLock { value in if value.failInventory { throw TestFailure() }; return value.inventory }
        }, buildPath: { configuration, gain, _ in
            let options = state.withLock { value in
                value.configurations.append(configuration); value.entered = true
                return (value.fail, value.delay)
            }
            if options.1 { _ = gate.wait(timeout: .now() + 4) }
            if options.0 { throw TestFailure() }
            let path = Path(gain)
            state.withLock { $0.paths.append(path) }
            return path
        })
        defer { gate.signal(); service.stopForModule(); defaults.removePersistentDomain(forName: suite) }
        service.start()
        checks["mixerInventoryLoaded"] = await eventually { service.apps.count == 1 && service.devices.count == 2 }
        checks["mixerNeutralHasNoCapture"] = state.withLock { $0.paths.isEmpty } && service.states[app.id] == .native

        service.setOutput(headset.device.uid, for: app.id)
        checks["mixerExplicitRouteBuilt"] = await eventually { service.states[app.id] == .active }
        checks["mixerSelectedDeviceNotSystemDefault"] = state.withLock { $0.configurations.last?.output.device.uid == headset.device.uid }
        service.setVolume(0.35, for: app.id); service.toggleMute(for: app.id)
        checks["mixerGainChangesPreserveRoute"] = service.settings.entry(for: app.id).outputUID == headset.device.uid
            && state.withLock { $0.paths.last?.gain.value == 0 && $0.paths.count == 1 }
        service.toggleMute(for: app.id)
        checks["mixerUnmuteUsesLatestGain"] = state.withLock { $0.paths.last?.gain.value == 0.35 }

        let firstPath = state.withLock { $0.paths.first }
        state.withLock { $0.inventory = .init(apps: [app], devices: [speakers], defaultUID: speakers.device.uid) }
        service.refresh()
        checks["mixerDisconnectFallsBack"] = await eventually {
            service.resolution(for: app.id).preferredUnavailable && service.states[app.id] == .active
                && state.withLock { $0.configurations.last?.output.device.uid == speakers.device.uid }
        }
        checks["mixerOldPathReleasedBeforeReplacement"] = firstPath?.invalidated.load(ordering: .relaxed) == true
        checks["mixerDisconnectedPreferenceRetained"] = service.settings.entry(for: app.id).outputUID == headset.device.uid
        state.withLock { $0.inventory = .init(apps: [app], devices: [speakers, headset], defaultUID: speakers.device.uid) }
        service.refresh()
        checks["mixerReconnectRestoresPreferred"] = await eventually {
            service.states[app.id] == .active && !service.resolution(for: app.id).preferredUnavailable
                && state.withLock { $0.configurations.last?.output.device.uid == headset.device.uid }
        }

        let changedHeadset = device(21, uid: headset.device.uid, name: headset.device.name, rate: 96_000)
        state.withLock { $0.inventory = .init(apps: [app], devices: [speakers, changedHeadset], defaultUID: speakers.device.uid) }
        service.refresh()
        checks["mixerSameUIDNewDeviceAndRateRebuilds"] = await eventually {
            service.states[app.id] == .active && state.withLock { $0.configurations.last?.output.device.objectID == 21 && $0.configurations.last?.output.sampleRate == 96_000 }
        }
        let relaunched = AudioApp(bundleID: app.bundleID, name: app.name, processes: [.init(object: 101, pid: 901)],
                                  launchTime: 2, playing: false, sourceDevices: [10])
        state.withLock { $0.inventory = .init(apps: [relaunched], devices: [speakers, changedHeadset], defaultUID: speakers.device.uid) }
        service.refresh()
        checks["mixerProcessRelaunchRebuilds"] = await eventually {
            service.states[app.id] == .active && state.withLock { $0.configurations.last?.processes == relaunched.processes }
        }

        state.withLock { $0.paths.last?.changed.store(true, ordering: .relaxed) }
        service.refresh()
        let beforeRecovery = state.withLock { $0.configurations.count }
        checks["mixerConfigurationChangeRecovers"] = await eventually {
            service.states[app.id] == .active && state.withLock { $0.configurations.count > beforeRecovery }
        }
        state.withLock { $0.paths.last?.changed.store(true, ordering: .relaxed) }
        service.refresh()
        checks["mixerRepeatedFailureRestoresNative"] = await eventually {
            if case .failed = service.states[app.id] { return service.moduleDiagnosticResources["taps"] == 0 && service.moduleDiagnosticResources["releasing"] == 0 }; return false
        }
        let afterFailure = state.withLock { $0.configurations.count }
        service.refresh(); try? await Task.sleep(for: .milliseconds(150))
        checks["mixerFailureDoesNotRetryContinuously"] = state.withLock { $0.configurations.count == afterFailure }
        service.retry(app.id)
        checks["mixerManualRetryWorks"] = await eventually { service.states[app.id] == .active }

        state.withLock { $0.failInventory = true }; service.refresh()
        checks["mixerInventoryFailureReleasesAudio"] = await eventually {
            service.failure != nil && service.moduleDiagnosticResources["taps"] == 0 && service.moduleDiagnosticResources["releasing"] == 0
        }
        state.withLock { $0.failInventory = false; $0.fail = true }
        service.refresh()
        checks["mixerSetupFailureDisplayed"] = await eventually { if case .failed = service.states[app.id] { return true }; return false }
        let failureNodes = await snapshot(service, destination: destination.appendingPathExtension("mixer-error.png"))
        checks["mixerRetryControlAccessible"] = failureNodes.contains { $0["role"] == "AXButton" && $0["name"] == String(localized: "Yeniden Dene") }
        state.withLock { $0.fail = false }; service.retry(app.id)
        checks["mixerSetupFailureRetryWorks"] = await eventually { service.states[app.id] == .active }

        // Retiring an in-flight build is distinct from retiring an installed path.
        service.reset(app.id)
        _ = await eventually { service.moduleDiagnosticResources["releasing"] == 0 }
        state.withLock { $0.delay = true; $0.entered = false }
        service.setOutput(headset.device.uid, for: app.id)
        _ = await eventually { state.withLock { $0.entered } }
        service.toggleMute(for: app.id)
        _ = await snapshot(service, destination: destination.appendingPathExtension("mixer-starting.png"))
        service.stopForModule()
        gate.signal()
        checks["mixerLateBuildCannotSurviveModuleStop"] = await eventually {
            service.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
                && state.withLock { $0.paths.allSatisfy { $0.invalidated.load(ordering: .relaxed) } }
        }

        state.withLock { $0.delay = false }
        service.start()
        checks["mixerRestartRestoresSavedRouteAndMute"] = await eventually {
            service.states[app.id] == .active && service.settings.entry(for: app.id).muted
                && state.withLock { $0.paths.last?.gain.value == 0 }
        }
        service.setVolume(0.7, for: app.id)
        if service.settings.entry(for: app.id).muted { service.toggleMute(for: app.id) }
        let nodes = await snapshot(service, destination: destination.appendingPathExtension("mixer.png"))
        checks["mixerOutputPickerAccessible"] = nodes.contains { $0["role"] == "AXPopUpButton" && $0["name"]?.contains(app.name) == true }
        checks["mixerVolumeSliderAccessible"] = nodes.contains { $0["role"] == "AXSlider" && $0["name"]?.contains(app.name) == true }
        // Explicit output disappears: keep the selected item visible in the picker.
        state.withLock { $0.inventory = .init(apps: [relaunched], devices: [speakers], defaultUID: speakers.device.uid) }
        service.refresh(); _ = await eventually { service.devices.count == 1 && service.states[app.id] == .active }
        _ = await snapshot(service, destination: destination.appendingPathExtension("mixer-disconnected.png"), width: 760)
        let playingApp = AudioApp(bundleID: app.bundleID, name: app.name, processes: relaunched.processes,
                                  launchTime: 2, playing: true, sourceDevices: [10])
        state.withLock { $0.inventory = .init(apps: [playingApp], devices: [speakers], defaultUID: speakers.device.uid) }
        service.refresh(); _ = await eventually { service.apps.first?.playing == true }
        service.diagnosticCheckHealth(after: 0)
        let beforeStall = state.withLock { $0.paths.count }
        service.diagnosticCheckHealth(after: 3)
        checks["mixerStalledCallbacksRecover"] = await eventually {
            service.states[app.id] == .active && state.withLock { $0.paths.count > beforeStall }
        }
        service.reset(app.id)
        checks["mixerResetRestoresNativeBypass"] = await eventually { service.states[app.id] == .native && service.moduleDiagnosticResources["taps"] == 0 }
        state.withLock { $0.inventory = .init(apps: [], devices: [speakers], defaultUID: speakers.device.uid) }
        service.refresh(); _ = await eventually { service.apps.isEmpty }
        _ = await snapshot(service, destination: destination.appendingPathExtension("mixer-empty.png"))
        service.stopForModule()
        checks["mixerStoppedReleasesAllResources"] = await eventually { service.moduleDiagnosticResources.values.allSatisfy { $0 == 0 } }
        checks["mixerOfflineSampleRateConversion"] = offlineRender()
        return checks
    }

    private static func device(_ id: UInt32, uid: String, name: String, rate: Double) -> MixerDeviceState {
        .init(device: .init(objectID: id, uid: uid, name: name, kind: .usb), sampleRate: rate, channels: 2, formats: [rate.bitPattern])
    }
    private static func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
    private static func snapshot(_ service: VolumeMixerService, destination: URL, width: CGFloat = 960) async -> [[String: String]] {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: width, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VolumeMixerView(service: service, showsMonitor: false))
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(250))
        let nodes = ToolUIAudit.accessibilityNodes(window)
        if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination.appendingPathExtension("ax.json"))
        }
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: destination)
        }
        window.close()
        return nodes
    }

    /// Real AVAudioEngine SRC, fully offline: 44.1 kHz stereo producer -> 48 kHz stereo destination.
    private static func offlineRender() -> Bool {
        let engine = AVAudioEngine()
        guard let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let destination = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else { return false }
        let ring = AudioFrameRing(sampleRate: 44_100, capacity: 16_384, primeFrames: 64)
        let samples = (0..<12_000).flatMap { _ in [Float(0.25), Float(-0.25)] }
        samples.withUnsafeBufferPointer { _ = ring.write($0) }
        let source = AVAudioSourceNode(format: sourceFormat) { _, _, count, output in
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard buffers.count == 2, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.read(left: .init(start: l, count: Int(count)), right: .init(start: r, count: Int(count)), gain: 1)
            return noErr
        }
        engine.attach(source)
        do {
            try engine.connectNode(source, to: engine.mainMixerNode, format: sourceFormat)
            try engine.enableManualRenderingMode(.offline, format: destination, maximumFrameCount: 512)
            try engine.start()
            defer { engine.stop() }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: 512) else { return false }
            var audible = false
            for _ in 0..<12 {
                guard try engine.renderOffline(512, to: buffer) == .success, let data = buffer.floatChannelData else { return false }
                for frame in 0..<Int(buffer.frameLength) {
                    let l = data[0][frame], r = data[1][frame]
                    guard l.isFinite, r.isFinite, abs(l) <= 1, abs(l + r) < 0.001 else { return false }
                    if l > 0.2 { audible = true }
                }
            }
            return audible && engine.manualRenderingSampleTime == 6_144
        } catch { return false }
    }
}
#endif

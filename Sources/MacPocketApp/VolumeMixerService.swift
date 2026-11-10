import AppKit
import CoreAudio
import MacPocketCore

struct MixerPathConfiguration: Equatable, Sendable {
    let processes: [MixerProcess]
    let launchTime: TimeInterval
    let output: MixerDeviceState
    let sources: [MixerDeviceState]
}

@MainActor
@Observable

final class VolumeMixerService {
    typealias PathBuilder = @Sendable (MixerPathConfiguration, AudioRenderGain, MixerBuildCancellation) throws -> any MixerAudioPath
    static let shared = VolumeMixerService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("VolumeMixerService")
    #endif
    enum RowState: Equatable {
        case native, starting, restoring, active, noOutput, failed(String)
    }
    private struct Build {
        let token: UInt64
        let configuration: MixerPathConfiguration
        let gain: AudioRenderGain
        let cancellation: MixerBuildCancellation
    }
    private struct Active {
        let configuration: MixerPathConfiguration
        let path: any MixerAudioPath
        let started: TimeInterval
        var lastProgress: (UInt64, UInt64)?
        var progressedAt: TimeInterval
    }
    private struct Failed {
        let configuration: MixerPathConfiguration
        let message: String
    }

    var settings: VolumeMixerSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            apply(); updatePolling()
        }
    }
    private(set) var apps: [AudioApp] = []
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var defaultUID: String?
    private(set) var states: [String: RowState] = [:]
    private(set) var failure: String?
    private(set) var refreshing = false
    @ObservationIgnored private(set) var moduleRunning = false
    private let defaults: UserDefaults
    private let readInventory: @Sendable ([MixerRunningApp]) throws -> MixerInventory
    private let buildPath: PathBuilder
    private let observesHardware: Bool
    private let setupQueue = DispatchQueue(label: "MacPocket.mixer.setup", qos: .userInitiated)
    // Teardown must never wait behind another application's permission prompt.
    private let releaseQueue = DispatchQueue(label: "MacPocket.mixer.release", qos: .userInitiated)
    private let scanQueue = DispatchQueue(label: "MacPocket.mixer.inventory", qos: .utility)
    private let observers = AudioPropertyObservers()
    private let deviceObservers = AudioPropertyObservers()
    @ObservationIgnored private var inventory: MixerInventory?
    @ObservationIgnored private var observedDevices: [AudioObjectID] = []
    @ObservationIgnored private var taps: [String: Active] = [:]
    @ObservationIgnored private var builds: [String: Build] = [:]
    @ObservationIgnored private var retiringBuilds: [String: Set<UInt64>] = [:]
    @ObservationIgnored private var registry = MixerBuildRegistry()
    @ObservationIgnored private var releasing: Set<String> = []
    @ObservationIgnored private var failures: [String: Failed] = [:]
    @ObservationIgnored private var recoveries: [String: Int] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var viewVisible = false
    @ObservationIgnored private var scanInFlight = false
    @ObservationIgnored private var scanAgain = false
    @ObservationIgnored private var generation: UInt64 = 0

    init(defaults: UserDefaults = .standard, observesHardware: Bool = true,
         readInventory: @escaping @Sendable ([MixerRunningApp]) throws -> MixerInventory = { try MixerInventory.read(running: $0) },
         buildPath: @escaping PathBuilder = { configuration, gain, cancellation in
             try AppAudioTap(processes: configuration.processes, outputUID: configuration.output.device.uid,
                             gain: gain, cancellation: cancellation)
         }) {
        self.defaults = defaults; self.readInventory = readInventory; self.buildPath = buildPath; self.observesHardware = observesHardware
        settings = VolumeMixerSettings.load(from: defaults)
    }

    func start() {
        guard !moduleRunning else { return }
        moduleRunning = true
        for selector in observesHardware ? [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] : [] {
            observers.add(selector) { [weak self] _, _ in MainActor.assumeIsolated { self?.refresh() } }
        }
        refresh(); updatePolling()
    }

    func stopForModule() {
        moduleRunning = false; generation &+= 1
        timer?.invalidate(); timer = nil
        observers.removeAll(); deviceObservers.removeAll(); observedDevices = []
        scanAgain = false; refreshing = false
        for id in Array(builds.keys) { cancelBuild(id) }
        stopAll()
        apps = []; devices = []; defaultUID = nil; inventory = nil
        states = [:]; failures = [:]; recoveries = [:]; failure = nil
    }

    func stopAll() {
        for id in Array(taps.keys) { removeTap(id) }
    }

    func setViewVisible(_ visible: Bool) {
        viewVisible = visible
        if visible { refresh() }
        updatePolling()
    }

    func setVolume(_ volume: Double, for id: String) {
        var entry = settings.entry(for: id)
        entry.volume = volume.isFinite ? min(1.5, max(0, volume)) : 1
        settings.entries[id] = entry
    }
    func toggleMute(for id: String) {
        var entry = settings.entry(for: id); entry.muted.toggle(); settings.entries[id] = entry
    }
    func setOutput(_ uid: String?, for id: String) {
        var entry = settings.entry(for: id)
        entry.outputUID = uid
        entry.outputName = devices.first { $0.uid == uid }?.name
        settings.entries[id] = entry
    }
    func reset(_ id: String) {
        failures[id] = nil; recoveries[id] = nil
        settings.entries[id] = nil
    }
    func retry(_ id: String) {
        failures[id] = nil; recoveries[id] = nil; apply(); refresh()
    }
    func resolution(for id: String) -> MixerOutputResolution {
        .resolve(entry: settings.entry(for: id), devices: devices, defaultUID: defaultUID)
    }

    private func updatePolling() {
        let needed = moduleRunning && (viewVisible || settings.hasActiveEntries)
        if !needed { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth(); self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    func refresh() {
        guard moduleRunning else { return }
        if scanInFlight { scanAgain = true; return }
        scanInFlight = true; refreshing = true
        let running = MixerRunningApp.snapshot(), currentGeneration = generation, read = readInventory
        scanQueue.async { [weak self] in
            let result = Result { try read(running) }
            DispatchQueue.main.async { [weak self] in self?.finishInventory(result, generation: currentGeneration) }
        }
    }

    private func finishInventory(_ result: Result<MixerInventory, Error>, generation scannedGeneration: UInt64) {
        scanInFlight = false; refreshing = false
        guard moduleRunning else { return }
        if scannedGeneration == generation {
            switch result {
            case .success(let fresh):
                inventory = fresh; apps = fresh.apps; devices = fresh.devices.map(\.device); defaultUID = fresh.defaultUID
                failure = nil; observeDevices(fresh.devices.map { $0.device.objectID })
                apply(); checkHealth()
            case .failure(let error):
                // An unreadable inventory is not evidence that devices/apps still exist. Restore native audio.
                failure = error.localizedDescription
                for id in Array(builds.keys) { cancelBuild(id) }
                stopAll(); inventory = nil
                states = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, .failed(error.localizedDescription)) })
            }
        }
        if scanAgain || scannedGeneration != generation { scanAgain = false; refresh() }
    }

    private func observeDevices(_ ids: [AudioObjectID]) {
        guard observesHardware else { return }
        let sorted = ids.sorted()
        guard observedDevices != sorted else { return }
        deviceObservers.removeAll(); observedDevices = sorted
        for id in sorted {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                deviceObservers.add(selector, object: id) { [weak self] _, _ in MainActor.assumeIsolated { self?.refresh() } }
            }
            deviceObservers.add(kAudioDevicePropertyStreamConfiguration, object: id, scope: kAudioDevicePropertyScopeOutput) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func configuration(for app: AudioApp) -> MixerPathConfiguration? {
        guard let inventory else { return nil }
        let resolved = resolution(for: app.id)
        guard resolved.needsTap, let output = inventory.devices.first(where: { $0.device.uid == resolved.effectiveUID }) else { return nil }
        // A silent process may temporarily report no source devices. Retain the previous source fingerprint.
        let sourceIDs = app.sourceDevices.isEmpty ? taps[app.id]?.configuration.sources.map { $0.device.objectID } ?? [] : app.sourceDevices
        return .init(processes: app.processes, launchTime: app.launchTime, output: output,
                     sources: inventory.devices.filter { sourceIDs.contains($0.device.objectID) })
    }

    private func apply() {
        guard moduleRunning, inventory != nil else { return }
        let desired = Dictionary(uniqueKeysWithValues: apps.compactMap { app in configuration(for: app).map { (app.id, $0) } })
        for (id, build) in builds where desired[id] != build.configuration { cancelBuild(id) }
        for (id, active) in taps where desired[id] != active.configuration { removeTap(id); recoveries[id] = nil }
        failures = failures.filter { desired[$0.key] == $0.value.configuration }
        var nextStates: [String: RowState] = [:]
        for app in apps {
            let id = app.id
            if releasing.contains(id) { nextStates[id] = .restoring; continue }
            guard let config = desired[id] else {
                nextStates[id] = !settings.entry(for: id).isNeutral && resolution(for: id).effectiveUID == nil ? .noOutput : .native
                continue
            }
            let gain = settings.entry(for: id).gain
            if let active = taps[id] { active.path.gain.value = gain; nextStates[id] = .active; continue }
            if let failed = failures[id] { nextStates[id] = .failed(failed.message); continue }
            nextStates[id] = .starting
            if let build = builds[id] { build.gain.value = gain; continue }
            guard !releasing.contains(id), retiringBuilds[id, default: []].isEmpty, let token = registry.begin(id) else { continue }
            let build = Build(token: token, configuration: config, gain: AudioRenderGain(gain), cancellation: MixerBuildCancellation())
            builds[id] = build
            let builder = buildPath, cleanup = releaseQueue
            setupQueue.async { [weak self] in
                let result = Result {
                    try build.cancellation.check()
                    let path = try builder(config, build.gain, build.cancellation)
                    if build.cancellation.isCancelled { path.invalidate(); throw CancellationError() }
                    return path
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { if case .success(let path) = result { cleanup.async { path.invalidate() } }; return }
                    self.finishBuild(id, result: result, build: build)
                }
            }
        }
        states = nextStates
    }

    private func cancelBuild(_ id: String) {
        if let build = builds.removeValue(forKey: id) {
            build.cancellation.cancel(); retiringBuilds[id, default: []].insert(build.token)
        }
        registry.invalidate(id)
    }

    private func finishBuild(_ id: String, result: Result<any MixerAudioPath, Error>, build: Build) {
        guard registry.finish(id, token: build.token) else {
            if case .success(let path) = result {
                releaseQueue.async { [weak self] in
                    path.invalidate()
                    DispatchQueue.main.async { self?.finishRetiringBuild(id, token: build.token) }
                }
            } else { finishRetiringBuild(id, token: build.token) }
            return
        }
        builds[id] = nil
        guard moduleRunning, let app = apps.first(where: { $0.id == id }), configuration(for: app) == build.configuration else {
            if case .success(let path) = result { releaseQueue.async { path.invalidate() } }
            apply(); return
        }
        switch result {
        case .success(let path):
            path.gain.value = settings.entry(for: id).gain
            let now = ProcessInfo.processInfo.systemUptime
            taps[id] = Active(configuration: build.configuration, path: path, started: now, progressedAt: now)
        case .failure(let error):
            failures[id] = .init(configuration: build.configuration, message: error.localizedDescription)
        }
        apply()
    }

    private func finishRetiringBuild(_ id: String, token: UInt64) {
        retiringBuilds[id]?.remove(token)
        if retiringBuilds[id]?.isEmpty == true { retiringBuilds[id] = nil }
        apply()
    }

    private func removeTap(_ id: String) {
        guard let active = taps.removeValue(forKey: id) else { return }
        releasing.insert(id)
        releaseQueue.async { [weak self] in
            active.path.invalidate()
            DispatchQueue.main.async { [weak self] in
                self?.releasing.remove(id); self?.apply()
            }
        }
    }

    private func checkHealth(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        for id in Array(taps.keys) {
            guard var active = taps[id], let app = apps.first(where: { $0.id == id }) else { continue }
            let progress = active.path.progress
            if let progress, active.lastProgress?.0 != progress.capture && active.lastProgress?.1 != progress.output {
                active.progressedAt = now
            }
            if !app.playing { active.progressedAt = now }
            active.lastProgress = progress.map { ($0.capture, $0.output) }
            taps[id] = active
            let stalled = app.playing && now - active.progressedAt > 2
            if active.path.needsRebuild || stalled {
                let attempts = recoveries[id, default: 0]
                recoveries[id] = attempts + 1
                if attempts >= 1 {
                    failures[id] = .init(configuration: active.configuration,
                        message: String(localized: "Ses yolu durdu; uygulamanın kendi sesine dönüldü. Yeniden dene."))
                }
                removeTap(id); apply()
            } else if now - active.started > 10 { recoveries[id] = nil }
        }
    }

    #if DEBUG
    func diagnosticCheckHealth(after seconds: TimeInterval) {
        checkHealth(now: ProcessInfo.processInfo.systemUptime + seconds)
    }
    var moduleDiagnosticResources: [String: Int] {
        ["timer": timer?.isValid == true ? 1 : 0, "taps": taps.count, "pending": builds.count + retiringBuilds.values.reduce(0) { $0 + $1.count },
         "releasing": releasing.count, "listeners": observers.count + deviceObservers.count, "inventoryRead": scanInFlight ? 1 : 0]
    }
    #endif
}

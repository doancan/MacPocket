import AppKit
import CoreAudio
import MacPocketCore

/// Volume keys for monitor speakers. macOS cannot change the volume of most monitors on HDMI or DisplayPort,
/// so when one of them is the sound output MacPocket answers the volume and mute keys itself over DDC/CI and
/// shows its own indicator (same style and position as the brightness indicator). Every other output stays
/// with macOS.
@MainActor
final class MonitorVolumeService: ObservableObject {
    static let shared = MonitorVolumeService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("MonitorVolumeService")
    #endif

    struct Settings: Codable, Equatable {
        var keysEnabled = false
        static let storageKey = "MacPocket.monitorVolume.settings"
    }

    /// Who answers the volume keys for the current sound output.
    enum Route: Equatable {
        /// macOS controls this output (built-in speakers, headphones, USB, Bluetooth…).
        case system(name: String)
        /// A monitor speaker MacPocket controls over DDC.
        case monitor(Monitor)
        /// A monitor speaker neither macOS nor DDC can control.
        case unsupported(name: String)
        case none
    }

    struct Monitor: Equatable {
        let display: CGDirectDisplayID
        let name: String
        var state: MonitorVolumeState
        /// The monitor has its own DDC mute; otherwise mute is played as volume 0.
        let nativeMute: Bool
    }

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Settings.storageKey) }
            configureTap()
        }
    }
    @Published private(set) var route = Route.none
    @Published private(set) var tapActive = false
    @Published private(set) var detecting = false

    private var channel: (serviceID: UInt64, channel: DDCChannel)?
    private var maximum: UInt16 = 100
    private var keyTap: VolumeKeyTap?
    private var pendingWrite: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var detectionGeneration = UUID()
    private let audioObservers = AudioPropertyObservers()
    private var refreshAgain = false

    private init() {
        settings = UserDefaults.standard.data(forKey: Settings.storageKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    func start() {
        guard !started, PocketModule.audioOutput.isAvailable() else { return }
        started = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            audioObservers.add(selector) { [weak self] _, _ in
                Task { @MainActor in await self?.refresh() }
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap() }
        })
        Task { await refresh() }
    }

    func stopForModule() {
        started = false
        detectionGeneration = UUID()
        pendingWrite?.cancel()
        pendingWrite = nil
        audioObservers.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        keyTap?.stop()
        keyTap = nil
        channel = nil
        route = .none
        tapActive = false
    }

    // MARK: Routing

    func refresh() async {
        guard started else { return }
        if detecting { refreshAgain = true; return }
        detecting = true
        repeat {
            refreshAgain = false
            await detect()
        } while refreshAgain
        detecting = false
        configureTap()
    }

    private func detect() async {
        let generation = detectionGeneration
        guard started else { return }
        guard let outputID = AudioOutputSystem.defaultOutput,
              let device = AudioOutputSystem.outputDevices().first(where: { $0.objectID == outputID }) else {
            route = .none
            channel = nil
            return
        }
        guard MonitorVolumeRouting.controlsOutput(kind: device.kind, systemVolumeSettable: AudioOutputSystem.isVolumeSettable(outputID)) else {
            route = .system(name: device.name)
            channel = nil
            return
        }
        let screens = NSScreen.screens.compactMap { screen -> (id: UInt32, name: String)? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return (id, screen.localizedName)
        }
        guard DDCChannel.isAvailable, let display = MonitorVolumeRouting.display(forAudioDevice: device.name, screens: screens),
              let serviceID = DisplayMatcher.match([(id: display, vendor: CGDisplayVendorNumber(display), product: CGDisplayModelNumber(display),
                                                     serial: CGDisplaySerialNumber(display))], registry: DisplayRegistry.scan())[display] else {
            route = .unsupported(name: device.name)
            channel = nil
            return
        }
        let opened: DDCChannel
        if let existing = channel, existing.serviceID == serviceID {
            opened = existing.channel
        } else if let fresh = DDCChannel.shared(registryID: serviceID) {
            opened = fresh
        } else {
            route = .unsupported(name: device.name)
            channel = nil
            return
        }
        channel = (serviceID, opened)
        // DDC reads block for ~50 ms per attempt: off the main thread.
        var reading = await Task.detached { (opened.get(.volume), opened.get(.audioMute, attempts: 2)) }.value
        guard started, generation == detectionGeneration else { return }
        if reading.0 == nil {
            // Monitors drop the odd burst of transactions (often right after wake or a display change): one
            // more try.
            try? await Task.sleep(for: .seconds(1))
            guard started, generation == detectionGeneration else { return }
            reading = await Task.detached { (opened.get(.volume), opened.get(.audioMute, attempts: 2)) }.value
        }
        guard started, generation == detectionGeneration else { return }
        guard let volume = reading.0, volume.maximum > 0 else {
            route = .unsupported(name: device.name)
            return
        }
        maximum = volume.maximum
        let nativeMute = MonitorVolumeRouting.muteState(fromReply: reading.1?.current)
        var state = MonitorVolumeState(level: Double(volume.current) / Double(volume.maximum), muted: nativeMute ?? false)
        // Keep an emulated mute across refreshes: the monitor itself only knows "volume 0".
        if nativeMute == nil, case .monitor(let previous) = route, previous.display == display, previous.state.muted, volume.current == 0 {
            state = previous.state
        }
        route = .monitor(Monitor(display: display, name: device.name, state: state, nativeMute: nativeMute != nil))
    }

    // MARK: Changing volume

    /// From the page's slider: sets the level and unmutes.
    func setLevel(_ level: Double) {
        guard case .monitor(var monitor) = route else { return }
        let wasMuted = monitor.state.muted
        monitor.state = MonitorVolumeState(level: level, muted: false)
        route = .monitor(monitor)
        write(monitor, muteChanged: wasMuted)
    }

    func toggleMute() {
        apply(.mute, fine: false, showIndicator: false)
    }

    private func apply(_ key: VolumeKey, fine: Bool, showIndicator: Bool) {
        guard case .monitor(var monitor) = route else { return }
        let wasMuted = monitor.state.muted
        monitor.state.apply(key, fine: fine)
        route = .monitor(monitor)
        write(monitor, muteChanged: wasMuted != monitor.state.muted)
        guard showIndicator else { return }
        let brightness = UserDefaults.standard.data(forKey: DisplayBrightnessService.Settings.storageKey)
            .flatMap { try? JSONDecoder().decode(DisplayBrightnessService.Settings.self, from: $0) } ?? DisplayBrightnessService.Settings()
        guard brightness.showIndicator else { return }
        BrightnessIndicator.show(level: monitor.state.effectiveLevel, on: Self.displayUnderPointer() ?? monitor.display,
                                 position: brightness.indicatorPosition ?? .topRight, style: brightness.indicatorStyle ?? .modern,
                                 kind: .volume(muted: monitor.state.muted, name: monitor.name))
    }

    /// Coalesces key repeats and slider drags: only the latest value is written, at most every 40 ms.
    private func write(_ monitor: Monitor, muteChanged: Bool) {
        guard let channel = channel?.channel else { return }
        let maximum = maximum
        let fraction = min(1, max(0, monitor.nativeMute ? monitor.state.level : monitor.state.effectiveLevel))
        let volume = UInt16((fraction * Double(maximum)).rounded())
        let mute: UInt16? = monitor.nativeMute && muteChanged ? (monitor.state.muted ? 1 : 2) : nil
        pendingWrite?.cancel()
        pendingWrite = Task.detached {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            if let mute { channel.set(.audioMute, value: mute) }
            channel.set(.volume, value: volume)
        }
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    }

    // MARK: Keys

    private func configureTap() {
        let wanted = started && settings.keysEnabled && AXIsProcessTrusted()
        if wanted && keyTap == nil {
            keyTap = VolumeKeyTap { [weak self] key, fine in
                Task { @MainActor in self?.apply(key, fine: fine, showIndicator: true) }
            }
        } else if !wanted, let keyTap {
            keyTap.stop()
            self.keyTap = nil
        }
        if case .monitor = route { keyTap?.setActive(true) } else { keyTap?.setActive(false) }
        tapActive = keyTap?.isRunning == true
    }
}

/// The volume keys on top of a `KeyEventTap`. While a DDC monitor is the sound output it swallows the volume
/// and mute keys and hands them over with `onKey`; otherwise every key goes to macOS untouched.
final class VolumeKeyTap: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var tap: KeyEventTap?
    private let onKey: @Sendable (VolumeKey, Bool) -> Void

    /// `onKey` gets the key and whether ⌥⇧ asked for fine steps. It is called on the tap thread.
    init(onKey: @escaping @Sendable (VolumeKey, Bool) -> Void) {
        self.onKey = onKey
        tap = KeyEventTap(name: "MacPocket volume keys") { [weak self] type, event in self?.handle(type, event) ?? true }
    }

    deinit { stop() }

    var isRunning: Bool { tap != nil }

    func setActive(_ active: Bool) { lock.withLock { self.active = active } }

    func stop() {
        tap?.stop()
        tap = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard lock.withLock({ active }) else { return true }
        let key: VolumeKey
        let isDown: Bool
        switch type {
        case .keyDown, .keyUp:
            guard let decoded = VolumeKey(keyCode: event.getIntegerValueField(.keyboardEventKeycode)) else { return true }
            key = decoded
            isDown = type == .keyDown
        default:
            guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined,
                  let decoded = VolumeKey(systemDefinedSubtype: Int(ns.subtype.rawValue), data1: ns.data1) else { return true }
            key = decoded
            isDown = BrightnessKey.isSystemDefinedKeyDown(data1: ns.data1)
        }
        if isDown { onKey(key, event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)) }
        return false
    }
}

#if DEBUG
extension MonitorVolumeService {
    var moduleDiagnosticResources: [String: Int] { ["observers": observers.count + audioObservers.count, "tap": tapActive ? 1 : 0, "write": pendingWrite == nil ? 0 : 1] }
}
#endif

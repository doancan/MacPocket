import AppKit
import SwiftUI
import ApplicationServices
import MacPocketCore

/// Brightness for external displays, driven by the keyboard's brightness keys like the built-in screen.
///
/// Each display uses hardware DDC/CI when the monitor answers a brightness read, otherwise software dimming
/// (the display's gamma table). Built-in displays are left to macOS. Keys are taken from a system-defined
/// event tap (Accessibility) and the level is shown with macOS's own brightness indicator when available.
@MainActor
final class DisplayBrightnessService: ObservableObject {
    static let shared = DisplayBrightnessService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("DisplayBrightnessService")
    #endif
    private(set) var moduleRunning = false

    enum Method: String, Codable, CaseIterable {
        case automatic, hardware, software
    }

    enum Target: String, Codable, CaseIterable {
        case underPointer, allExternal, main
    }

    /// Where MacPocket's own brightness indicator appears on each screen.
    enum IndicatorPosition: String, Codable, CaseIterable {
        case topRight, topCenter, bottomCenter, center
    }

    /// How the brightness indicator looks: MacPocket's glass slider, a compact one-line capsule, or the classic
    /// macOS square bezel.
    enum IndicatorStyle: String, Codable, CaseIterable {
        case modern, capsule, classic
    }

    struct Settings: Codable, Equatable {
        var keysEnabled = false
        var target = Target.underPointer
        var showIndicator = true
        /// Optional so settings saved before the option existed still decode.
        var indicatorPosition: IndicatorPosition?
        var indicatorStyle: IndicatorStyle?
        /// Per display (vendor-product-serial): the chosen method and last level, re-applied after a relaunch.
        var methods: [String: Method] = [:]
        var levels: [String: Double] = [:]
        /// Optional so settings saved before the schedule existed still decode (and keep their levels).
        var schedule: BrightnessSchedule?

        static let storageKey = "MacPocket.brightness.settings"
    }

    struct ManagedDisplay: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let key: String
        let name: String
        /// The method in effect after detection (never `.automatic`).
        var active: Method
        var level: Double
        var contrast: Double?
        var hardwareAvailable: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.active == rhs.active && lhs.level == rhs.level && lhs.contrast == rhs.contrast
                && lhs.hardwareAvailable == rhs.hardwareAvailable && lhs.name == rhs.name
        }
    }

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Settings.storageKey) }
            if settings.methods != oldValue.methods { Task { await refreshDisplays() } }
            configureTap()
        }
    }
    @Published private(set) var displays: [ManagedDisplay] = [] {
        didSet { keyTap?.update(managed: displays.map(\.id), target: settings.target) }
    }
    @Published private(set) var detecting = false
    @Published private(set) var tapActive = false

    /// DDC channel per display, with the registry entry it was opened for (a reused display ID after swapping
    /// monitors must not keep writing to the old monitor's channel).
    private var channels: [CGDirectDisplayID: (serviceID: UInt64, channel: DDCChannel)] = [:]
    private var refreshAgain = false
    private var maximums: [CGDirectDisplayID: (brightness: UInt16, contrast: UInt16)] = [:]
    private var pendingWrites: [CGDirectDisplayID: Task<Void, Never>] = [:]
    /// Each display's calibrated gamma table, captured before MacPocket first dims it.
    private var originalGamma: [CGDirectDisplayID: GammaTable] = [:]
    /// Software brightness scale per display (absent = 1, e.g. DDC displays).
    private var softwareScale: [CGDirectDisplayID: Float] = [:]
    /// Night-mode color warmth, multiplied into every managed display's gamma.
    private var warmth: (red: Float, green: Float, blue: Float) = (1, 1, 1)
    private var keyTap: BrightnessKeyTap?
    private var observers: [NSObjectProtocol] = []
    private var detectionGeneration = UUID()
    private var scheduleTimer: Timer?
    /// Until when a manual change wins over the schedule. A date, not a minute of the day, so a Mac asleep
    /// at that minute still returns to the schedule afterwards.
    @Published private(set) var overrideUntil: Date?
    /// Displays whose gamma table did not keep the night warmth (read back different, e.g. with HDR on).
    @Published private(set) var warmthUnsupported: Set<CGDirectDisplayID> = []
    /// In "follow the sun" mode, told about each manual level change (display key, new level); returns until when
    /// the manual brightness should win over night mode (nil: no hold).
    var solarManualChange: ((String, Double) -> Date?)?
    /// Never dim software displays to black: the screen would look off with no way to see the slider.
    private static let softwareFloor = 0.12

    private init() {
        settings = UserDefaults.standard.data(forKey: Settings.storageKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    func stopForModule() {
        moduleRunning = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        pendingWrites.values.forEach { $0.cancel() }
        pendingWrites = [:]
        detectionGeneration = UUID()
        keyTap?.stop()
        keyTap = nil
        tapActive = false
        restoreSoftwareDimming()
        channels = [:]
        displays = []
    }

    func start() {
        guard !moduleRunning, PocketModule.displays.isAvailable() else { return }
        moduleRunning = true
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshDisplays() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap() }
        })
        Task { await refreshDisplays(); applySchedule() }
        configureTap()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.applySchedule() } }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    // MARK: Schedule

    var schedule: BrightnessSchedule {
        get { settings.schedule ?? BrightnessSchedule() }
        set {
            settings.schedule = newValue
            overrideUntil = nil
            applySchedule()
        }
    }

    /// The next time the clock shows `minute` (today if still ahead, otherwise tomorrow).
    static func nextDate(atMinute minute: Int, after now: Date = Date()) -> Date {
        Calendar.current.nextDate(after: now, matching: DateComponents(hour: minute / 60, minute: minute % 60), matchingPolicy: .nextTime) ?? now
    }

    static var currentMinute: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Moves every external display to the scheduled level, unless the user changed it since the last point.
    /// Set by a focus session so the schedule doesn't undo its dimming.
    var scheduleHeld = false

    func applySchedule() {
        guard moduleRunning else { return }
        // In "follow the sun" mode NightModeService drives brightness; the points are not used.
        guard schedule.source != .solar else { return }
        guard schedule.enabled, !scheduleHeld, let target = schedule.level(at: Self.currentMinute) else { return }
        if let until = overrideUntil {
            if Date() < until { return }
            overrideUntil = nil
        }
        for display in displays where abs(display.level - target) > 0.01 {
            setLevel(target, for: display.id, fromSchedule: true)
        }
    }

    /// Whether brightness must be left alone at `now`: a focus session holds it, or a manual change still wins.
    func brightnessHeld(at now: Date) -> Bool {
        if scheduleHeld { return true }
        guard let until = overrideUntil else { return false }
        if now < until { return true }
        overrideUntil = nil
        return false
    }

    /// Restores every gamma table MacPocket changed (called at quit).
    func restoreSoftwareDimming() {
        warmth = (1, 1, 1)
        softwareScale = [:]
        guard !originalGamma.isEmpty else { return }
        CGDisplayRestoreColorSyncSettings()
        originalGamma = [:]
    }

    /// Sets the night-mode color warmth (per-channel factors, 1 = neutral) on every managed display.
    func setWarmth(_ factors: (red: Double, green: Double, blue: Double)) {
        warmth = (Float(factors.red), Float(factors.green), Float(factors.blue))
        for display in displays { applyGamma(display.id) }
        // Read the tables back: some displays (e.g. with HDR on) silently ignore the write. A neutral warmth
        // proves nothing, so the last verdict is kept until the next warm write.
        guard warmth != (1, 1, 1) else { return }
        for display in displays {
            if gammaHolds(display.id) { warmthUnsupported.remove(display.id) } else { warmthUnsupported.insert(display.id) }
        }
    }

    /// Whether the display's current gamma table is the one MacPocket last wrote.
    private func gammaHolds(_ id: CGDirectDisplayID) -> Bool {
        guard let expected = originalGamma[id]?.composed(warmth: warmth, scale: softwareScale[id] ?? 1),
              let actual = GammaTable.read(id) else { return false }
        return expected.matches(actual)
    }

    // MARK: Detection

    /// Serialized: a request arriving during a refresh runs once more afterwards instead of racing it.
    func refreshDisplays() async {
        guard moduleRunning else { return }
        if detecting { refreshAgain = true; return }
        detecting = true
        repeat {
            refreshAgain = false
            await detect()
        } while refreshAgain
        detecting = false
    }

    private func detect() async {
        let generation = detectionGeneration
        guard moduleRunning else { return }
        let online = Self.onlineExternalDisplays()
        let registry = DisplayRegistry.scan()
        let matches = DisplayMatcher.match(online.map { (id: $0, vendor: CGDisplayVendorNumber($0), product: CGDisplayModelNumber($0),
                                                         serial: CGDisplaySerialNumber($0)) }, registry: registry)
        var result: [ManagedDisplay] = []
        for id in online {
            let key = Self.key(for: id)
            let preference = settings.methods[key] ?? .automatic
            var channel: DDCChannel?
            if let serviceID = matches[id], DDCChannel.isAvailable {
                if let existing = channels[id], existing.serviceID == serviceID {
                    channel = existing.channel
                } else if let opened = DDCChannel.shared(registryID: serviceID) {
                    channels[id] = (serviceID, opened)
                    channel = opened
                }
            } else {
                channels[id] = nil
            }
            // Probe off the main thread: a DDC read blocks for ~50 ms per attempt.
            typealias Reading = (current: UInt16, maximum: UInt16)
            var probe: (brightness: Reading?, contrast: Reading?) = (nil, nil)
            if let channel, preference != .software {
                let readTask = Task.detached { () -> (Reading?, Reading?) in (channel.get(.brightness), channel.get(.contrast, attempts: 2)) }
                probe = await readTask.value
            }
            guard moduleRunning, generation == detectionGeneration else { return }
            let hardware = probe.brightness != nil
            let active: Method = preference == .software ? .software : preference == .hardware && channel != nil ? .hardware
                : hardware ? .hardware : .software
            var level = settings.levels[key] ?? 1
            var contrast: Double?
            if let brightness = probe.brightness {
                maximums[id] = (brightness.maximum, probe.contrast?.maximum ?? 100)
                level = Double(brightness.current) / Double(brightness.maximum)
                contrast = probe.contrast.map { Double($0.current) / Double($0.maximum) }
            } else if active == .hardware {
                maximums[id] = (100, 100) // write-only monitor: the usual 0…100 scale
            }
            // Untouched displays keep their ColorSync calibration: gamma is only changed once dimmed or warmed.
            if active == .software { applySoftware(id, level: level) } else { softwareScale[id] = nil }
            // Switched away from software dimming: drop its scale (warmth, if any, stays applied).
            applyGamma(id)
            result.append(ManagedDisplay(id: id, key: key, name: Self.name(of: id), active: active, level: level,
                                         contrast: contrast, hardwareAvailable: hardware))
        }
        displays = result
    }

    private static func onlineExternalDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        // External, and not the secondary of a mirror set (that one shows the primary's picture).
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }

    private static func key(for id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?
            .localizedName ?? String(localized: "Ekran \(id)")
    }

    // MARK: Changing brightness

    func setLevel(_ level: Double, for id: CGDirectDisplayID, fromSchedule: Bool = false) {
        guard moduleRunning else { return }
        let clamped = min(1, max(0, level))
        if !fromSchedule, schedule.enabled {
            if schedule.source == .solar {
                if let key = displays.first(where: { $0.id == id })?.key { overrideUntil = solarManualChange?(key, clamped) }
            } else if let minute = schedule.nextPoint(after: Self.currentMinute) {
                overrideUntil = Self.nextDate(atMinute: minute)
            }
        }
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[index].level = clamped
        settings.levels[displays[index].key] = clamped
        switch displays[index].active {
        case .software, .automatic: applySoftware(id, level: clamped)
        case .hardware: scheduleHardware(id, code: .brightness, fraction: clamped)
        }
    }

    func setContrast(_ value: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }), displays[index].active == .hardware else { return }
        displays[index].contrast = min(1, max(0, value))
        scheduleHardware(id, code: .contrast, fraction: value)
    }

    /// Coalesces slider and key-repeat bursts: only the latest value is written, at most every 40 ms.
    /// Restores a level right away (quit, crash recovery): DDC is written synchronously, and the stored level is
    /// updated so the next launch doesn't re-apply a dimmed one.
    /// Crash recovery runs even when the module is unavailable, without constructing its service or listeners.
    static func restoreInterruptedLevels(_ levels: [UInt32: Double]) {
        guard !levels.isEmpty else { return }
        var settings = UserDefaults.standard.data(forKey: Settings.storageKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        let displays = onlineExternalDisplays().filter { levels[$0] != nil }
        let matches = DisplayMatcher.match(displays.map { (id: $0, vendor: CGDisplayVendorNumber($0), product: CGDisplayModelNumber($0),
                                                           serial: CGDisplaySerialNumber($0)) }, registry: DisplayRegistry.scan())
        for id in displays {
            guard let storedLevel = levels[id], storedLevel.isFinite else { continue }
            let level = min(1, max(0, storedLevel))
            let key = key(for: id)
            settings.levels[key] = level
            guard settings.methods[key] != .software, DDCChannel.isAvailable, let registryID = matches[id],
                  let channel = DDCChannel.shared(registryID: registryID), let reading = channel.get(.brightness), reading.maximum > 0 else { continue }
            channel.set(.brightness, value: UInt16((level * Double(reading.maximum)).rounded()))
        }
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Settings.storageKey) }
    }

    func restoreLevelNow(_ level: Double, for id: CGDirectDisplayID) {
        pendingWrites[id]?.cancel()
        pendingWrites[id] = nil
        let key = displays.first { $0.id == id }?.key ?? "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
        settings.levels[key] = level
        if let index = displays.firstIndex(where: { $0.id == id }) { displays[index].level = level }
        if let channel = channels[id]?.channel, displays.first(where: { $0.id == id })?.active == .hardware {
            channel.set(.brightness, value: UInt16((level * Double(maximums[id]?.brightness ?? 100)).rounded()))
        } else if originalGamma[id] != nil {
            applySoftware(id, level: level)
        }
    }

    private func scheduleHardware(_ id: CGDirectDisplayID, code: VCPCode, fraction: Double) {
        guard let channel = channels[id]?.channel else { return }
        let maximum = code == .brightness ? (maximums[id]?.brightness ?? 100) : (maximums[id]?.contrast ?? 100)
        let value = UInt16((min(1, max(0, fraction)) * Double(maximum)).rounded())
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task.detached {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            channel.set(code, value: value)
        }
    }

    /// Records the software brightness scale: `level` 0...1 maps to floor...1 so the screen never goes fully dark.
    private func applySoftware(_ id: CGDirectDisplayID, level: Double) {
        softwareScale[id] = Float(Self.softwareFloor + (1 - Self.softwareFloor) * level)
        applyGamma(id)
    }

    /// The single gamma write: original table x warmth x software brightness scale. The original is captured
    /// before the first change of either kind; when nothing is left to change it is put back.
    private func applyGamma(_ id: CGDirectDisplayID) {
        let scale = softwareScale[id] ?? 1
        let neutral = warmth.red == 1 && warmth.green == 1 && warmth.blue == 1 && scale == 1
        if neutral {
            if let original = originalGamma.removeValue(forKey: id) { original.apply(to: id) }
            return
        }
        if originalGamma[id] == nil {
            guard let table = GammaTable.read(id) else { return }
            originalGamma[id] = table
        }
        originalGamma[id]?.composed(warmth: warmth, scale: scale).apply(to: id)
    }

    // MARK: Keys

    private func configureTap() {
        let wanted = moduleRunning && settings.keysEnabled && AXIsProcessTrusted()
        if wanted && keyTap == nil {
            keyTap = BrightnessKeyTap { [weak self] key, fine, targets in
                Task { @MainActor in self?.apply(key, fine: fine, to: targets) }
            }
        } else if !wanted, let keyTap {
            keyTap.stop()
            self.keyTap = nil
        }
        keyTap?.update(managed: displays.map(\.id), target: settings.target)
        tapActive = keyTap != nil
    }

    /// Shows the indicator on every managed display at its current level, so a new position can be seen right away.
    func previewIndicator() {
        for display in displays {
            BrightnessIndicator.show(level: display.level, on: display.id, position: settings.indicatorPosition ?? .topRight,
                                     style: settings.indicatorStyle ?? .modern)
        }
    }

    private func apply(_ key: BrightnessKey, fine: Bool, to targets: [CGDirectDisplayID]) {
        for id in targets {
            guard let display = displays.first(where: { $0.id == id }) else { continue }
            let level = BrightnessStep.next(from: display.level, up: key.isUp,
                                            step: fine ? BrightnessStep.fine : BrightnessStep.normal)
            setLevel(level, for: id)
            if settings.showIndicator {
                BrightnessIndicator.show(level: level, on: id, position: settings.indicatorPosition ?? .topRight,
                                         style: settings.indicatorStyle ?? .modern)
            }
        }
    }
}

/// The brightness keys on top of a `KeyEventTap`: other keys pass straight through, and only brightness keys aimed at
/// a managed display are swallowed and handed over with `onKey`.
final class BrightnessKeyTap: @unchecked Sendable {
    private let lock = NSLock()
    private var managed: [CGDirectDisplayID] = []
    private var target = DisplayBrightnessService.Target.underPointer
    private var tap: KeyEventTap?
    private let onKey: @Sendable (BrightnessKey, Bool, [CGDirectDisplayID]) -> Void

    /// `onKey` gets the key, whether ⌥⇧ asked for fine steps, and the target displays. It is called on the tap thread.
    init(onKey: @escaping @Sendable (BrightnessKey, Bool, [CGDirectDisplayID]) -> Void) {
        self.onKey = onKey
        tap = KeyEventTap(name: "MacPocket brightness keys") { [weak self] type, event in self?.handle(type, event) ?? true }
    }

    deinit { stop() }

    var isRunning: Bool { tap != nil }

    func update(managed: [CGDirectDisplayID], target: DisplayBrightnessService.Target) {
        lock.withLock { self.managed = managed; self.target = target }
    }

    func stop() {
        tap?.stop()
        tap = nil
    }

    /// Returns false to swallow the event (it was used for an external display).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key: BrightnessKey
        let isDown: Bool
        switch type {
        case .keyDown, .keyUp:
            guard let decoded = BrightnessKey(keyCode: event.getIntegerValueField(.keyboardEventKeycode)) else { return true }
            key = decoded
            isDown = type == .keyDown
        default:
            guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined,
                  let decoded = BrightnessKey(systemDefinedSubtype: Int(ns.subtype.rawValue), data1: ns.data1) else { return true }
            key = decoded
            isDown = BrightnessKey.isSystemDefinedKeyDown(data1: ns.data1)
        }
        let targets = targetDisplays(pointer: event.location)
        guard !targets.isEmpty else { return true } // pointer on the built-in screen: let macOS handle it
        if isDown { onKey(key, event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift), targets) }
        return false
    }

    private func targetDisplays(pointer: CGPoint) -> [CGDirectDisplayID] {
        let (managed, target) = lock.withLock { (managed, target) }
        switch target {
        case .allExternal:
            return managed
        case .main:
            let main = CGMainDisplayID()
            return managed.contains(main) ? [main] : []
        case .underPointer:
            var id: CGDirectDisplayID = 0
            var count: UInt32 = 0
            guard CGGetDisplaysWithPoint(pointer, 1, &id, &count) == .success, count > 0, managed.contains(id) else { return [] }
            return [id]
        }
    }
}

/// The brightness indicator shown for key presses, in the chosen style. MacPocket draws every style itself: the
/// system's private OSD framework accepts the call but no longer draws the classic bezel.
@MainActor
enum BrightnessIndicator {
    /// What the indicator shows: a screen's brightness, or a monitor speaker's volume (with the speaker's name).
    enum Kind: Equatable {
        case brightness
        case volume(muted: Bool, name: String)
    }

    /// One indicator per display, so "all external displays" shows each screen its own level at the same time.
    private static var huds: [CGDirectDisplayID: BrightnessHUD] = [:]

    static func show(level: Double, on display: CGDirectDisplayID, position: DisplayBrightnessService.IndicatorPosition,
                     style: DisplayBrightnessService.IndicatorStyle, kind: Kind = .brightness) {
        let hud = huds[display] ?? BrightnessHUD()
        huds[display] = hud
        hud.show(level: level, on: display, position: position, style: style, kind: kind)
    }
}

/// MacPocket's own brightness indicator for one display, in either style. It never takes focus or clicks and fades
/// out shortly after the last key press.
@MainActor
private final class BrightnessHUD {
    private var panel: NSPanel?
    private let state = BrightnessHUDState()
    private var hideWork: DispatchWorkItem?
    func show(level: Double, on display: CGDirectDisplayID, position: DisplayBrightnessService.IndicatorPosition,
              style: DisplayBrightnessService.IndicatorStyle, kind: BrightnessIndicator.Kind) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }) ?? NSScreen.main else { return }
        if case .volume(_, let name) = kind { state.name = name } else { state.name = screen.localizedName }
        state.kind = kind
        state.style = style
        if panel?.isVisible == true && panel?.alphaValue == 1 {
            withAnimation(.snappy(duration: 0.18)) { state.level = level }
        } else {
            state.level = level
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(Self.frame(in: screen.visibleFrame, position: position, size: Self.size(style)), display: false)
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private static func size(_ style: DisplayBrightnessService.IndicatorStyle) -> NSSize {
        switch style {
        case .modern: NSSize(width: 320, height: 96)
        case .capsule: NSSize(width: 300, height: 64)
        case .classic: NSSize(width: 220, height: 220)
        }
    }

    private static func frame(in area: NSRect, position: DisplayBrightnessService.IndicatorPosition, size: NSSize) -> NSRect {
        let origin: NSPoint
        switch position {
        case .topRight: origin = NSPoint(x: area.maxX - size.width - 12, y: area.maxY - size.height - 8)
        case .topCenter: origin = NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 8)
        case .bottomCenter: origin = NSPoint(x: area.midX - size.width / 2, y: area.minY + area.height * 0.12)
        case .center: origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        }
        return NSRect(origin: origin, size: size)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        panel.contentView = NSHostingView(rootView: BrightnessHUDView(state: state))
        return panel
    }
}

@MainActor
private final class BrightnessHUDState: ObservableObject {
    @Published var level = 1.0
    @Published var name = ""
    @Published var style = DisplayBrightnessService.IndicatorStyle.modern
    @Published var kind = BrightnessIndicator.Kind.brightness

    var symbol: String {
        switch kind {
        case .brightness: BrightnessHUDSymbol.brightness(level: level)
        case .volume(let muted, _): BrightnessHUDSymbol.volume(muted: muted, level: level)
        }
    }
    var label: Text { kind == .brightness ? Text("Parlaklık") : Text("Ses") }
}

/// SF Symbols for the indicator, shared with the pages that show the same levels.
enum BrightnessHUDSymbol {
    static func brightness(level: Double) -> String { level < 0.5 ? "sun.min.fill" : "sun.max.fill" }

    static func volume(muted: Bool, level: Double) -> String {
        muted || level <= 0 ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// Laid out like the system's Control Center sliders: the screen's name and percentage above a thick filled track
/// that carries the sun symbol.
private struct BrightnessHUDView: View {
    @ObservedObject var state: BrightnessHUDState

    var body: some View {
        switch state.style {
        case .modern: ModernBrightnessHUD(state: state)
        case .capsule: CapsuleBrightnessHUD(state: state)
        case .classic: ClassicBrightnessHUD(state: state)
        }
    }
}

/// A compact one-line glass capsule: the sun, a level bar and the percentage.
private struct CapsuleBrightnessHUD: View {
    @ObservedObject var state: BrightnessHUDState
    private var level: Double { state.level }

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Image(systemName: state.symbol)
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
            ProgressView(value: level)
                .progressViewStyle(.linear)
                .tint(.primary)
            Text(level, format: .percent.precision(.fractionLength(0)))
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, PocketSpacing.l)
        .frame(height: 52)
        .modifier(CapsuleHUDSurface())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
        .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
    }
}

private struct CapsuleHUDSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .capsule)
    }
}

/// The classic macOS bezel: a rounded square with the large sun and a row of 16 segments.
private struct ClassicBrightnessHUD: View {
    @ObservedObject var state: BrightnessHUDState
    private var level: Double { state.level }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: state.kind == .brightness ? "sun.max.fill" : state.symbol)
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 76, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    Rectangle()
                        .fill(Double(index) < (level * 16).rounded() ? Color.primary.opacity(0.85) : Color.primary.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 26)
        }
        .frame(width: 200, height: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
        .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
    }
}

private struct ModernBrightnessHUD: View {
    @ObservedObject var state: BrightnessHUDState
    private let trackHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: state.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: PocketSpacing.s)
                Text(state.level, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: state.level))
            }
            track
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 300)
        .modifier(BrightnessHUDSurface())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
        .accessibilityValue(Text(state.level, format: .percent.precision(.fractionLength(0))))
    }

    private var track: some View {
        GeometryReader { proxy in
            // Never narrower than the track is tall, so the sun stays on the fill even at 0 %.
            let fill = trackHeight + (proxy.size.width - trackHeight) * min(1, max(0, state.level))
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(.primary.opacity(0.88)).frame(width: fill)
                Image(systemName: state.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: trackHeight, height: trackHeight)
            }
        }
        .frame(height: trackHeight)
    }
}

/// Liquid Glass panel behind the modern indicator.
private struct BrightnessHUDSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: shape)
    }
}

/// A display's gamma ramp: one curve per channel.
struct GammaTable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    static func read(_ display: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity)), green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0 else { return nil }
        return GammaTable(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }

    func composed(warmth: (red: Float, green: Float, blue: Float), scale: Float) -> GammaTable {
        GammaTable(red: GammaComposer.compose(red, factor: warmth.red, scale: scale),
                   green: GammaComposer.compose(green, factor: warmth.green, scale: scale),
                   blue: GammaComposer.compose(blue, factor: warmth.blue, scale: scale))
    }

    func apply(to display: CGDirectDisplayID) {
        CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
    }

    /// Whether `other` has the same curves within `tolerance`, sampling proportionally if the lengths differ.
    func matches(_ other: GammaTable, tolerance: CGGammaValue = 0.01) -> Bool {
        func same(_ a: [CGGammaValue], _ b: [CGGammaValue]) -> Bool {
            guard !a.isEmpty, !b.isEmpty else { return a.isEmpty == b.isEmpty }
            return a.indices.allSatisfy { i in
                let j = a.count > 1 ? i * (b.count - 1) / (a.count - 1) : 0
                return abs(a[i] - b[j]) <= tolerance
            }
        }
        return same(red, other.red) && same(green, other.green) && same(blue, other.blue)
    }
}

#if DEBUG
extension DisplayBrightnessService {
    var moduleDiagnosticResources: [String: Int] { ["observers": observers.count, "timer": scheduleTimer?.isValid == true ? 1 : 0, "tap": tapActive ? 1 : 0, "writes": pendingWrites.count] }
}
#endif

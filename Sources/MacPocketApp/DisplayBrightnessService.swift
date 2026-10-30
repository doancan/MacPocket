import AppKit
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

    enum Method: String, Codable, CaseIterable {
        case automatic, hardware, software
    }

    enum Target: String, Codable, CaseIterable {
        case underPointer, allExternal, main
    }

    struct Settings: Codable, Equatable {
        var keysEnabled = false
        var target = Target.underPointer
        var showIndicator = true
        /// Per display (vendor-product-serial): the chosen method and last level, re-applied after a relaunch.
        var methods: [String: Method] = [:]
        var levels: [String: Double] = [:]

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
    @Published private(set) var displays: [ManagedDisplay] = []
    @Published private(set) var detecting = false
    @Published private(set) var tapActive = false

    private var channels: [CGDirectDisplayID: DDCChannel] = [:]
    private var maximums: [CGDirectDisplayID: (brightness: UInt16, contrast: UInt16)] = [:]
    private var pendingWrites: [CGDirectDisplayID: Task<Void, Never>] = [:]
    /// Each display's calibrated gamma table, captured before MacPocket first dims it.
    private var originalGamma: [CGDirectDisplayID: GammaTable] = [:]
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    /// Never dim software displays to black: the screen would look off with no way to see the slider.
    private static let softwareFloor = 0.12

    private init() {
        settings = UserDefaults.standard.data(forKey: Settings.storageKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    func start() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.refreshDisplays() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap() }
        })
        Task { await refreshDisplays() }
        configureTap()
    }

    /// Restores every gamma table MacPocket changed (called at quit).
    func restoreSoftwareDimming() {
        guard !originalGamma.isEmpty else { return }
        CGDisplayRestoreColorSyncSettings()
        originalGamma = [:]
    }

    // MARK: Detection

    func refreshDisplays() async {
        detecting = true
        defer { detecting = false }
        let online = Self.onlineExternalDisplays()
        let registry = DisplayRegistry.scan()
        let matches = DisplayMatcher.match(online.map { (id: $0, vendor: CGDisplayVendorNumber($0), product: CGDisplayModelNumber($0),
                                                         serial: CGDisplaySerialNumber($0)) }, registry: registry)
        var result: [ManagedDisplay] = []
        for id in online {
            let key = Self.key(for: id)
            let preference = settings.methods[key] ?? .automatic
            var channel = channels[id]
            if channel == nil, DDCChannel.isAvailable, let serviceID = matches[id] {
                channel = DDCChannel(registryID: serviceID)
                channels[id] = channel
            }
            // Probe off the main thread: a DDC read blocks for ~50 ms per attempt.
            typealias Reading = (current: UInt16, maximum: UInt16)
            var probe: (brightness: Reading?, contrast: Reading?) = (nil, nil)
            if let channel, preference != .software {
                let readTask = Task.detached { () -> (Reading?, Reading?) in (channel.get(.brightness), channel.get(.contrast, attempts: 2)) }
                probe = await readTask.value
            }
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
            // Untouched displays keep their ColorSync calibration: gamma is only changed once dimmed.
            if active == .software, level < 1 { applySoftware(id, level: level) }
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

    func setLevel(_ level: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(1, max(0, level))
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
    private func scheduleHardware(_ id: CGDirectDisplayID, code: VCPCode, fraction: Double) {
        guard let channel = channels[id] else { return }
        let maximum = code == .brightness ? (maximums[id]?.brightness ?? 100) : (maximums[id]?.contrast ?? 100)
        let value = UInt16((min(1, max(0, fraction)) * Double(maximum)).rounded())
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task.detached {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            channel.set(code, value: value)
        }
    }

    /// Scales the display's own (calibrated) gamma table. `level` 0…1 maps to floor…1 so the screen never goes
    /// fully dark; full brightness puts the original table back.
    private func applySoftware(_ id: CGDirectDisplayID, level: Double) {
        if originalGamma[id] == nil {
            guard level < 1, let table = GammaTable.read(id) else { return }
            originalGamma[id] = table
        }
        guard let original = originalGamma[id] else { return }
        original.scaled(by: Float(Self.softwareFloor + (1 - Self.softwareFloor) * level)).apply(to: id)
    }

    // MARK: Keys

    private func configureTap() {
        let wanted = settings.keysEnabled && AXIsProcessTrusted()
        if wanted && tap == nil {
            let mask = CGEventMask(1 << 14) // NX_SYSDEFINED: media and brightness keys
            let callback: CGEventTapCallBack = { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<DisplayBrightnessService>.fromOpaque(context).takeUnretainedValue()
                let keep: Bool = MainActor.assumeIsolated { service.handle(type, event) }
                return keep ? Unmanaged.passUnretained(event) : nil
            }
            if let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: callback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) {
                let source = CFMachPortCreateRunLoopSource(nil, created, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: created, enable: true)
                tap = created
                tapSource = source
            }
        } else if !wanted, let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
            self.tap = nil
            tapSource = nil
        }
        tapActive = tap != nil
    }

    private static let brightnessUp = 2, brightnessDown = 3

    /// Returns false to swallow the key (it was used for an external display).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return true }
        let keyCode = (ns.data1 & 0xFFFF_0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        guard keyCode == Self.brightnessUp || keyCode == Self.brightnessDown else { return true }
        let targets = targetDisplays()
        guard !targets.isEmpty else { return true } // pointer on the built-in screen: let macOS handle it
        guard isDown else { return false }
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
        for id in targets {
            guard let display = displays.first(where: { $0.id == id }) else { continue }
            let level = BrightnessStep.next(from: display.level, up: keyCode == Self.brightnessUp,
                                            step: fine ? BrightnessStep.fine : BrightnessStep.normal)
            setLevel(level, for: id)
            if settings.showIndicator { BrightnessIndicator.show(level: level, on: id) }
        }
        return false
    }

    private func targetDisplays() -> [CGDirectDisplayID] {
        let managed = Set(displays.map(\.id))
        switch settings.target {
        case .allExternal:
            return displays.map(\.id)
        case .main:
            let main = CGMainDisplayID()
            return managed.contains(main) ? [main] : []
        case .underPointer:
            var id: CGDirectDisplayID = 0
            var count: UInt32 = 0
            let point = CGEvent(source: nil)?.location ?? .zero
            guard CGGetDisplaysWithPoint(point, 1, &id, &count) == .success, count > 0, managed.contains(id) else { return [] }
            return [id]
        }
    }
}

/// macOS's own brightness bezel (the OSD framework the system uses for the built-in screen). When that private
/// class is missing no bezel is shown; Settings says so through `isNative`.
@MainActor
enum BrightnessIndicator {
    @objc private protocol OSDManaging {
        func showImage(_ image: Int64, onDisplayID display: UInt32, priority: UInt32, msecUntilFade: UInt32,
                       filledChiclets: UInt32, totalChiclets: UInt32, locked: Bool)
    }

    private static let manager: AnyObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY)
        guard let type = NSClassFromString("OSDManager") as? NSObject.Type,
              type.responds(to: NSSelectorFromString("sharedManager")),
              let shared = type.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject,
              shared.responds(to: NSSelectorFromString("showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"))
        else { return nil }
        return shared
    }()

    static var isNative: Bool { manager != nil }

    static func show(level: Double, on display: CGDirectDisplayID) {
        let chiclets = BrightnessStep.chiclets(level)
        if let manager {
            let osd = unsafeBitCast(manager, to: OSDManaging.self)
            // Image 1 is the brightness sun; priority 0x1F4 is what the system uses for key presses.
            osd.showImage(1, onDisplayID: display, priority: 0x1F4, msecUntilFade: 1000,
                          filledChiclets: chiclets.filled, totalChiclets: chiclets.total, locked: false)
        }
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

    func scaled(by factor: Float) -> GammaTable {
        GammaTable(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
    }

    func apply(to display: CGDirectDisplayID) {
        CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
    }
}

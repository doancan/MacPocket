import AppKit
import IOKit
import MacPocketCore
import UserNotifications

/// Battery levels of connected Bluetooth accessories. The I/O Registry gives Magic keyboards, trackpads and mice
/// live (cheap, read every minute); `system_profiler` gives names, kinds and AirPods' left/right/case (slower, read
/// when the set of accessories changes and every ten minutes). Needs no Bluetooth permission.
@MainActor
final class BluetoothBatteryService: NSObject, ObservableObject {
    static let shared = BluetoothBatteryService()

    struct Settings: Codable, Equatable {
        var lowBatteryAlerts = true
        var threshold = 20
        var showInMenuBar = false
        static let storageKey = "MacPocket.bluetoothBattery.settings"
    }

    @Published private(set) var devices: [BluetoothBatteryDevice] = [] { didSet { updateStatusItem() } }
    @Published private(set) var loading = false
    @Published private(set) var updatedAt: Date?
    /// A Logitech device is connected but its battery needs Input Monitoring.
    @Published private(set) var logitechNeedsPermission = false
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Settings.storageKey) }
            alerts = LowBatteryAlerts(threshold: settings.threshold, rearm: settings.threshold + 10)
            if settings.lowBatteryAlerts && !oldValue.lowBatteryAlerts { Task { _ = await PocketAlertNotifier.requestAuthorization() } }
            updateStatusItem()
        }
    }

    private var profiled: [BluetoothBatteryDevice] = []
    private var profiledAt: Date?
    private var knownAddresses: Set<String> = []
    private var alerts: LowBatteryAlerts
    private var logitech: [(name: String, kind: BluetoothBatteryDevice.Kind, reading: HIDPPBattery.Reading)] = []
    private var logitechAt: Date?
    private var timer: Timer?
    private var statusItem: NSStatusItem?

    private override init() {
        let loaded = UserDefaults.standard.data(forKey: Settings.storageKey).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        settings = loaded
        alerts = LowBatteryAlerts(threshold: loaded.threshold, rearm: loaded.threshold + 10)
        super.init()
    }

    func start() {
        guard timer == nil else { return }
        updateStatusItem()
        Task { await refresh() }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { Task { await self?.refresh() } } }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Lowest known level among connected accessories, for the menu bar.
    var lowest: (device: BluetoothBatteryDevice, level: Int)? {
        devices.compactMap { device in device.levels.lowest.map { (device, $0) } }.min { $0.1 < $1.1 }
    }

    func refresh(forceProfile: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let registry = await Task.detached { Self.registryLevels() }.value
        let addresses = Set(registry.keys)
        let stale = profiledAt.map { Date().timeIntervalSince($0) > 600 } ?? true
        // Re-read the (slow) profiler when the set of accessories changes, not every minute a cabled one is missing from it.
        if forceProfile || stale || addresses != knownAddresses {
            if let data = await Self.systemProfiler() {
                profiled = BluetoothBatteryParser.connectedDevices(fromSystemProfiler: data)
                profiledAt = Date()
                knownAddresses = addresses
            }
        }
        // HID++ talks to the device itself: every five minutes is plenty for a battery.
        if forceProfile || logitechAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            switch await LogitechBatteryReader.read() {
            case .readings(let readings): logitech = readings; logitechNeedsPermission = false
            case .notPermitted: logitech = []; logitechNeedsPermission = true
            case .none: logitech = []; logitechNeedsPermission = false
            }
            logitechAt = Date()
        }
        devices = BluetoothBatteryParser.merge(BluetoothBatteryParser.merge(profiled, registry: registry), logitech: logitech)
        updatedAt = Date()
        if settings.lowBatteryAlerts { notify(alerts.evaluate(devices)) }
    }

    func requestLogitechAccess() {
        LogitechBatteryReader.requestAccess()
        Task { await refresh(forceProfile: true) }
    }

    // MARK: Menu bar

    /// The lowest level with its device's symbol in the menu bar; the menu lists every accessory.
    private func updateStatusItem() {
        guard settings.showInMenuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = statusItem ?? {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "MacPocketBluetoothBattery"
            return item
        }()
        statusItem = item
        guard let button = item.button else { return }
        if let lowest {
            let image = NSImage(systemSymbolName: lowest.device.kind.symbol, accessibilityDescription: lowest.device.name)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = " \(lowest.level)%"
            button.contentTintColor = lowest.level <= settings.threshold ? .systemRed : nil
            button.toolTip = String(localized: "\(lowest.device.name): %\(lowest.level)")
        } else {
            let image = NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: String(localized: "Bluetooth Pilleri"))
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.contentTintColor = nil
        }
        let menu = NSMenu()
        for device in devices {
            let level = device.levels.lowest.map { "%\($0)" } ?? "—"
            let entry = NSMenuItem(title: "\(device.name)  \(level)", action: nil, keyEquivalent: "")
            entry.image = NSImage(systemSymbolName: device.kind.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        if devices.isEmpty { menu.addItem(withTitle: String(localized: "Bağlı Bluetooth aygıtı yok"), action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let open = NSMenuItem(title: String(localized: "Bluetooth Pilleri…"), action: #selector(openPage), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        item.menu = menu
    }

    @objc private func openPage() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .pocketOpenTool, object: "bluetooth-battery")
    }

    private func notify(_ due: [BluetoothBatteryDevice]) {
        guard PocketAlertNotifier.isAvailable, !due.isEmpty else { return }
        for device in due {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(device.name) pili azaldı")
            content.body = String(localized: "Pil %\(device.levels.lowest ?? 0) seviyesinde. Şarj etmeyi unutma.")
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "MacPocket.bluetoothBattery.\(device.address)",
                                                                         content: content, trigger: nil))
        }
    }

    // MARK: Sources

    /// "BatteryPercent" of Apple's accessories (over Bluetooth, or USB while charging), keyed by normalized address.
    nonisolated static func registryLevels() -> [String: RegistryBattery] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(iterator) }
        var levels: [String: RegistryBattery] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func property(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            guard let level = (property("BatteryPercent") as? NSNumber)?.intValue,
                  let address = property("DeviceAddress") as? String else { continue }
            levels[BluetoothBatteryParser.normalize(address)] = RegistryBattery(
                level: min(100, max(0, level)), productID: (property("ProductID") as? NSNumber)?.intValue ?? 0,
                wired: (property("Transport") as? String)?.lowercased() == "usb")
        }
        return levels
    }

    private static func systemProfiler() async -> Data? {
        let result = try? await BoundedProcess.run("/usr/sbin/system_profiler", ["-json", "-detailLevel", "basic", "SPBluetoothDataType"], timeout: 20)
        return result.flatMap { $0.status == 0 ? Data($0.output.utf8) : nil }
    }
}

extension Notification.Name {
    /// Asks the main window to open a tool by its catalog ID.
    static let pocketOpenTool = Notification.Name("MacPocket.openTool")
}

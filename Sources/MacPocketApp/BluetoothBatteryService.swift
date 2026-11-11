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
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("BluetoothBatteryService")
    #endif
    private(set) var moduleRunning = false

    struct Settings: Codable, Equatable {
        var lowBatteryAlerts = true
        var threshold = 20
        static let storageKey = "MacPocket.bluetoothBattery.settings"
    }

    @Published private(set) var devices: [BluetoothBatteryDevice] = []
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
        }
    }

    private var profiled: [BluetoothBatteryDevice] = []
    private var profiledAt: Date?
    private var knownAddresses: Set<String> = []
    private var alerts: LowBatteryAlerts
    private var logitech: [(name: String, kind: BluetoothBatteryDevice.Kind, reading: HIDPPBattery.Reading)] = []
    private var logitechAt: Date?
    private var refreshGeneration = UUID()
    private var timer: Timer?

    private override init() {
        let loaded = UserDefaults.standard.data(forKey: Settings.storageKey).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        settings = loaded
        alerts = LowBatteryAlerts(threshold: loaded.threshold, rearm: loaded.threshold + 10)
        super.init()
    }

    func stopForModule() {
        moduleRunning = false
        timer?.invalidate()
        timer = nil
        refreshGeneration = UUID()
    }

    func start() {
        guard !moduleRunning, PocketModule.bluetoothBattery.isAvailable() else { return }
        moduleRunning = true
        guard timer == nil else { return }
        Task { await refresh() }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh(forceProfile: Bool = false) async {
        guard moduleRunning, !loading else { return }
        let generation = refreshGeneration
        loading = true
        defer { loading = false }
        let registry = await Task.detached { Self.registryLevels() }.value
        guard moduleRunning, generation == refreshGeneration else { return }
        let addresses = Set(registry.keys)
        let stale = profiledAt.map { Date().timeIntervalSince($0) > 600 } ?? true
        // Re-read the (slow) profiler when the set of accessories changes, not every minute a cabled one is missing from it.
        if forceProfile || stale || addresses != knownAddresses {
            if let data = await Self.systemProfiler() {
                guard moduleRunning, generation == refreshGeneration else { return }
                profiled = BluetoothBatteryParser.connectedDevices(fromSystemProfiler: data)
                profiledAt = Date()
                knownAddresses = addresses
            }
        }
        // HID++ talks to the device itself: every five minutes is plenty for a battery.
        if forceProfile || logitechAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            let result = await LogitechBatteryReader.read()
            guard moduleRunning, generation == refreshGeneration else { return }
            switch result {
            case .readings(let readings): logitech = readings; logitechNeedsPermission = false
            case .notPermitted: logitech = []; logitechNeedsPermission = true
            case .none: logitech = []; logitechNeedsPermission = false
            }
            logitechAt = Date()
        }
        guard moduleRunning, generation == refreshGeneration else { return }
        devices = BluetoothBatteryParser.merge(BluetoothBatteryParser.merge(profiled, registry: registry), logitech: logitech)
        updatedAt = Date()
        if settings.lowBatteryAlerts { notify(alerts.evaluate(devices)) }
    }

    func requestLogitechAccess() {
        LogitechBatteryReader.requestAccess()
        Task { await refresh(forceProfile: true) }
    }

    // MARK: Menu bar

    /// Whether the settings saved by earlier versions asked for the standalone menu bar item, which the
    /// Bluetooth module of the menu bar configuration replaces.
    static func legacyMenuBarItemRequested(_ defaults: UserDefaults = .standard) -> Bool {
        guard let data = defaults.data(forKey: Settings.storageKey),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["showInMenuBar"] as? Bool == true
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

#if DEBUG
extension BluetoothBatteryService {
    var moduleDiagnosticResources: [String: Int] { ["timer": timer?.isValid == true ? 1 : 0] }
}
#endif

import Foundation

// MARK: - Modules

/// One monitoring module shown in the menu bar (a status item, or a tab of the grouped popover).
public enum MenuBarModule: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, gpu, memory, disk, network, power, weather

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: String(localized: "Bellek")
        case .disk: String(localized: "Disk")
        case .network: String(localized: "Ağ")
        case .power: String(localized: "Güç ve Fan")
        case .weather: String(localized: "Hava durumu")
        }
    }

    /// Short uppercase label for compact menu bar rendering.
    public var shortLabel: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: String(localized: "MenuBar.shortLabel.memory", defaultValue: "RAM")
        case .disk: String(localized: "MenuBar.shortLabel.disk", defaultValue: "DİSK")
        case .network: String(localized: "MenuBar.shortLabel.network", defaultValue: "AĞ")
        case .power: String(localized: "MenuBar.shortLabel.power", defaultValue: "GÜÇ")
        case .weather: String(localized: "MenuBar.shortLabel.weather", defaultValue: "HAVA")
        }
    }

    /// The label for what the module currently shows: the power module reads "FAN" or "ISI" for those values.
    public func shortLabel(for value: MenuBarValue) -> String {
        switch value {
        case .powerFanSpeed, .powerFanPercent: String(localized: "MenuBar.shortLabel.fan", defaultValue: "FAN")
        case .powerThermal: String(localized: "MenuBar.shortLabel.thermal", defaultValue: "ISI")
        case .powerTemperature: "°C"
        case .networkPing: "PING"
        case .networkWifiSignal: "Wi-Fi"
        default: shortLabel
        }
    }

    public var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up.fill"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .power: "bolt.fill"
        case .weather: "cloud.sun.fill"
        }
    }

    /// Value choices offered for this module, first one is the default.
    public var valueOptions: [MenuBarValue] {
        switch self {
        case .cpu: [.cpuTotal, .cpuUser, .cpuSystem]
        case .gpu: [.gpuUtilization, .gpuRenderer, .gpuMemory]
        case .memory: [.memoryUsedPercent, .memoryUsedBytes, .memoryFreeBytes, .memoryPressure]
        case .disk: [.diskFreeBytes, .diskUsedPercent, .diskFreePercent, .diskActivity, .diskReadWrite]
        case .network: [.networkUpDown, .networkCombined, .networkDownload, .networkUpload, .networkPing, .networkWifiSignal]
        case .power: [.powerBattery, .powerTimeRemaining, .powerSource, .powerFanSpeed, .powerFanPercent, .powerThermal, .powerTemperature]
        case .weather: [.weatherTemperature, .weatherApparent]
        }
    }

    /// UserDefaults key of the enable flag. These are the pre-existing keys, so the General
    /// settings toggle ("MacPocket.menuBarCPU") keeps controlling the CPU module.
    public var enabledKey: String { self == .cpu ? "MacPocket.menuBarCPU" : "MacPocket.bar.\(rawValue)" }

    /// Enabled state when the user never chose one.
    public var enabledByDefault: Bool { self == .cpu || self == .memory }

    /// Display styles that make sense for this module; per-core bars exist only for the CPU.
    public var styleOptions: [MenuBarDisplayStyle] {
        if self == .weather { return [.value, .icon] }
        return self == .cpu ? MenuBarDisplayStyle.allCases : MenuBarDisplayStyle.allCases.filter { $0 != .cores }
    }
}

/// What a module shows as its menu bar value.
public enum MenuBarValue: String, Codable, Sendable, CaseIterable, Identifiable {
    case cpuTotal, cpuUser, cpuSystem
    case gpuUtilization, gpuRenderer, gpuMemory
    case memoryUsedPercent, memoryUsedBytes, memoryFreeBytes, memoryPressure
    case diskFreeBytes, diskUsedPercent, diskFreePercent, diskActivity, diskReadWrite
    case networkUpDown, networkCombined, networkDownload, networkUpload, networkPing, networkWifiSignal
    case powerBattery, powerTimeRemaining, powerSource
    case powerFanSpeed, powerFanPercent, powerThermal, powerTemperature
    case weatherTemperature, weatherApparent

    public var id: String { rawValue }

    /// A symbol that replaces the module's own when this value is shown (fans, heat).
    public var symbol: String? {
        switch self {
        case .powerFanSpeed, .powerFanPercent: "fan"
        case .powerThermal: "thermometer.medium"
        case .powerTemperature: "thermometer.high"
        case .networkPing: "stopwatch"
        case .networkWifiSignal: "wifi"
        default: nil
        }
    }

    public var title: String {
        switch self {
        case .cpuTotal: String(localized: "Toplam kullanım")
        case .cpuUser: String(localized: "Kullanıcı")
        case .cpuSystem: String(localized: "Sistem")
        case .gpuUtilization: String(localized: "GPU kullanımı (%)")
        case .gpuRenderer: String(localized: "İşleyici (%)")
        case .gpuMemory: String(localized: "GPU belleği (boyut)")
        case .memoryUsedPercent: String(localized: "Kullanılan (%)")
        case .memoryUsedBytes: String(localized: "Kullanılan (boyut)")
        case .memoryFreeBytes: String(localized: "Kullanılabilir (boyut)")
        case .memoryPressure: String(localized: "Bellek baskısı (%)")
        case .diskFreeBytes: String(localized: "Boş alan")
        case .diskUsedPercent: String(localized: "Doluluk (%)")
        case .diskFreePercent: String(localized: "Boş alan (%)")
        case .diskActivity: String(localized: "Okuma + yazma hızı")
        case .diskReadWrite: String(localized: "Okuma ve yazma (iki satır)")
        case .networkUpDown: String(localized: "Gönderme ve alma (iki satır)")
        case .networkCombined: String(localized: "Toplam hız")
        case .networkDownload: String(localized: "Yalnız alma")
        case .networkUpload: String(localized: "Yalnız gönderme")
        case .networkPing: String(localized: "Gecikme (ping)")
        case .networkWifiSignal: String(localized: "Wi-Fi sinyali (dBm)")
        case .powerBattery: String(localized: "Pil yüzdesi")
        case .powerTimeRemaining: String(localized: "Kalan süre")
        case .powerSource: String(localized: "Güç kaynağı")
        case .powerFanSpeed: String(localized: "Fan hızı (rpm)")
        case .powerFanPercent: String(localized: "Fan hızı (%)")
        case .powerThermal: String(localized: "Isı durumu")
        case .powerTemperature: String(localized: "Sıcaklık sensörü (°C)")
        case .weatherTemperature: String(localized: "Hava sıcaklığı (°C)")
        case .weatherApparent: String(localized: "Hissedilen sıcaklık (°C)")
        }
    }
}

public enum MenuBarLayout: String, Codable, Sendable, CaseIterable, Identifiable {
    /// One status item; the popover has one tab per module.
    case grouped
    /// One status item per enabled module.
    case separate
    public var id: String { rawValue }
    public var title: String { self == .grouped ? String(localized: "Gruplu") : String(localized: "Ayrı") }
}

/// How the single grouped status item draws itself: always one compact, icon-sized image.
/// Earlier versions also offered wide text and bar layouts ("stacked", "gauges"); those stored values
/// no longer decode and fall back to the default.
public enum MenuBarGroupedStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The static MacPocket glyph.
    case symbol = "glyph"
    /// A speedometer whose needle and arc follow the chosen metric.
    case dial
    /// A progress ring around the chosen metric's symbol.
    case ring

    public static let defaultValue = MenuBarGroupedStyle.dial
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .symbol: String(localized: "Sabit simge")
        case .dial: String(localized: "Canlı gösterge")
        case .ring: String(localized: "Canlı halka")
        }
    }

    public var isLive: Bool { self != .symbol }
}

/// How a separate status item draws its module.
public enum MenuBarDisplayStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case value, graph, gauge, pie, cores, icon
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .value: String(localized: "Değer")
        case .graph: String(localized: "Mini grafik")
        case .gauge: String(localized: "Mini çubuk")
        case .pie: String(localized: "Pasta")
        case .cores: String(localized: "Çekirdekler")
        case .icon: String(localized: "Yalnız simge")
        }
    }

    /// Styles that draw a level or history and may show the value beside it.
    public var drawsLevel: Bool { self == .graph || self == .gauge || self == .pie || self == .cores }
}

// MARK: - Thresholds

/// How a module item is colored in the menu bar.
public enum MenuBarColorMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Follows the menu bar like every other item (template image).
    case monochrome
    /// Orange past the warning threshold, red past the critical one.
    case thresholds
    public var id: String { rawValue }
    public var title: String { self == .monochrome ? String(localized: "Tek renk") : String(localized: "Eşiğe göre") }
}

public enum MenuBarLevel: Int, Sendable, Comparable {
    case normal, warning, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The scale a value's thresholds are entered in.
public enum MenuBarThresholdUnit: Sendable, Equatable {
    case percent, celsius, milliseconds, dBm

    public var symbol: String {
        switch self {
        case .percent: "%"
        case .celsius: "°C"
        case .milliseconds: "ms"
        case .dBm: "dBm"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .percent: 0...100
        case .celsius: 30...110
        case .milliseconds: 10...1000
        case .dBm: -95 ... -40
        }
    }

    public var step: Double {
        switch self {
        case .percent, .celsius, .dBm: 1
        case .milliseconds: 10
        }
    }
}

extension MenuBarValue {
    /// Nil for values with no meaningful alarm level (rates, power source).
    public var thresholdUnit: MenuBarThresholdUnit? {
        switch self {
        case .cpuTotal, .cpuUser, .cpuSystem, .gpuUtilization, .gpuRenderer, .gpuMemory,
             .memoryUsedPercent, .memoryUsedBytes, .memoryFreeBytes, .memoryPressure,
             .diskFreeBytes, .diskUsedPercent, .diskFreePercent, .powerBattery, .powerTimeRemaining,
             .powerFanSpeed, .powerFanPercent, .powerThermal: .percent
        case .powerTemperature: .celsius
        case .networkPing: .milliseconds
        case .networkWifiSignal: .dBm
        case .diskActivity, .diskReadWrite, .networkUpDown, .networkCombined, .networkDownload, .networkUpload, .powerSource, .weatherTemperature, .weatherApparent: nil
        }
    }

    /// Battery charge and Wi-Fi signal get worse as they fall; everything else as it rises.
    public var lowerIsWorse: Bool {
        switch self {
        case .powerBattery, .powerTimeRemaining, .networkWifiSignal: true
        default: false
        }
    }

    /// Thresholds used until the user sets their own: (warning, critical).
    public var defaultThresholds: (warning: Double, critical: Double)? {
        switch self {
        case .cpuTotal, .cpuUser, .cpuSystem, .gpuUtilization, .gpuRenderer: (70, 90)
        case .gpuMemory: (50, 75)
        case .memoryUsedPercent, .memoryUsedBytes, .memoryFreeBytes: (80, 92)
        case .memoryPressure: (50, 80)
        case .diskFreeBytes, .diskUsedPercent, .diskFreePercent: (85, 95)
        case .powerBattery, .powerTimeRemaining: (20, 10)
        case .powerFanSpeed, .powerFanPercent: (70, 90)
        case .powerThermal: (50, 75)
        case .powerTemperature: (80, 95)
        case .networkPing: (100, 250)
        case .networkWifiSignal: (-70, -80)
        default: nil
        }
    }

    /// Short description for settings, e.g. "üstüne çıkınca" or "altına düşünce".
    public var thresholdDirection: String {
        lowerIsWorse ? String(localized: "altına düşünce") : String(localized: "üstüne çıkınca")
    }
}

public enum MenuBarThresholds {
    /// The level of a reading under the module's thresholds; normal when coloring is off or the value has no scale.
    public static func level(_ reading: MenuBarReading, settings: MenuBarModuleSettings) -> MenuBarLevel {
        guard settings.colorMode == .thresholds, let value = reading.thresholdValue,
              let limits = settings.thresholds else { return .normal }
        if settings.value.lowerIsWorse {
            return value <= limits.critical ? .critical : value <= limits.warning ? .warning : .normal
        }
        return value >= limits.critical ? .critical : value >= limits.warning ? .warning : .normal
    }
}

// MARK: - Settings

/// Per-module menu bar options, stored as JSON under `MenuBarPreferences.moduleKey(_:)`.
public struct MenuBarModuleSettings: Codable, Equatable, Sendable {
    public var style: MenuBarDisplayStyle
    public var showLabel: Bool
    public var showIcon: Bool
    /// Show the value next to a mini graph or gauge (always shown for the plain value style).
    public var showValue: Bool
    public var decimals: Bool
    public var value: MenuBarValue
    /// Disk module only: the volume to show; empty means the startup volume.
    public var volumePath: String
    /// Power module temperature: the sensor to show by name; empty means the hottest one.
    public var sensorName: String
    /// Network module: mark the item with a lock while a VPN is connected.
    public var showVPN: Bool
    public var colorMode: MenuBarColorMode
    /// User thresholds in the value's unit; nil keeps the value's defaults.
    public var warningThreshold: Double?
    public var criticalThreshold: Double?

    /// The thresholds in effect for the current value, or nil when it has no scale.
    public var thresholds: (warning: Double, critical: Double)? {
        guard let defaults = value.defaultThresholds else { return nil }
        return (warningThreshold ?? defaults.warning, criticalThreshold ?? defaults.critical)
    }

    public init(style: MenuBarDisplayStyle = .value, showLabel: Bool = true, showIcon: Bool = false,
                showValue: Bool = true, decimals: Bool = false, value: MenuBarValue, volumePath: String = "",
                sensorName: String = "", showVPN: Bool = true, colorMode: MenuBarColorMode = .monochrome,
                warningThreshold: Double? = nil, criticalThreshold: Double? = nil) {
        self.style = style; self.showLabel = showLabel; self.showIcon = showIcon
        self.showValue = showValue; self.decimals = decimals; self.value = value; self.volumePath = volumePath
        self.sensorName = sensorName; self.showVPN = showVPN
        self.colorMode = colorMode; self.warningThreshold = warningThreshold; self.criticalThreshold = criticalThreshold
    }

    public static func defaults(for module: MenuBarModule) -> Self {
        switch module {
        case .network: Self(showLabel: false, showIcon: false, value: .networkUpDown)
        case .power: Self(showLabel: false, showIcon: true, value: .powerBattery)
        case .weather: Self(showLabel: false, showIcon: true, value: .weatherTemperature)
        default: Self(value: module.valueOptions[0])
        }
    }

    private enum CodingKeys: String, CodingKey { case style, showLabel, showIcon, showValue, decimals, value, volumePath, sensorName, showVPN, colorMode, warningThreshold, criticalThreshold }

    /// Missing or unknown fields fall back to defaults, so stored settings survive future additions.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try? container.decodeIfPresent(MenuBarValue.self, forKey: .value)
        self.init(style: (try? container.decodeIfPresent(MenuBarDisplayStyle.self, forKey: .style)) ?? .value,
                  showLabel: (try? container.decodeIfPresent(Bool.self, forKey: .showLabel)) ?? true,
                  showIcon: (try? container.decodeIfPresent(Bool.self, forKey: .showIcon)) ?? false,
                  showValue: (try? container.decodeIfPresent(Bool.self, forKey: .showValue)) ?? true,
                  decimals: (try? container.decodeIfPresent(Bool.self, forKey: .decimals)) ?? false,
                  value: value ?? .cpuTotal,
                  volumePath: (try? container.decodeIfPresent(String.self, forKey: .volumePath)) ?? "",
                  sensorName: (try? container.decodeIfPresent(String.self, forKey: .sensorName)) ?? "",
                  showVPN: (try? container.decodeIfPresent(Bool.self, forKey: .showVPN)) ?? true,
                  colorMode: (try? container.decodeIfPresent(MenuBarColorMode.self, forKey: .colorMode)) ?? .monochrome,
                  warningThreshold: try? container.decodeIfPresent(Double.self, forKey: .warningThreshold),
                  criticalThreshold: try? container.decodeIfPresent(Double.self, forKey: .criticalThreshold))
    }

    /// Keeps `value` within the module's options (e.g. after decoding a hand-edited plist).
    func normalized(for module: MenuBarModule) -> Self {
        var copy = self
        if !module.valueOptions.contains(value) { copy.value = module.valueOptions[0] }
        if !module.styleOptions.contains(style) { copy.style = .value }
        return copy
    }
}

/// The complete menu bar configuration. All reads/writes go through `load`/`save`.
public struct MenuBarPreferences: Equatable, Sendable {
    public var visible: Bool
    public var layout: MenuBarLayout
    public var groupedStyle: MenuBarGroupedStyle
    /// The module whose level drives the live grouped icon.
    public var groupedMetric: MenuBarModule
    /// Marks the grouped icon with a dot while something needs attention (see `MenuBarAttention`).
    public var groupedBadge: Bool
    public var order: [MenuBarModule]
    public var enabled: Set<MenuBarModule>
    public var modules: [MenuBarModule: MenuBarModuleSettings]
    /// Binary (1024) units when true, decimal (1000) otherwise.
    public var binaryUnits: Bool

    public static let visibleKey = "MacPocket.showMenuBar"
    public static let layoutKey = "MacPocket.menubar.layout"
    public static let groupedStyleKey = "MacPocket.menubar.groupedStyle"
    public static let groupedMetricKey = "MacPocket.menubar.groupedMetric"
    public static let groupedBadgeKey = "MacPocket.menubar.groupedBadge"
    public static let orderKey = "MacPocket.menubar.order"
    public static let unitsKey = "MacPocket.bar.units"
    public static let schemaKey = "MacPocket.menubar.schema"
    public static let schemaVersion = 1
    public static func moduleKey(_ module: MenuBarModule) -> String { "MacPocket.menubar.module.\(module.rawValue)" }

    public init(visible: Bool = true, layout: MenuBarLayout = .grouped, groupedStyle: MenuBarGroupedStyle = .defaultValue,
                groupedMetric: MenuBarModule = .cpu, groupedBadge: Bool = true, order: [MenuBarModule] = MenuBarModule.allCases,
                enabled: Set<MenuBarModule> = Set(MenuBarModule.allCases.filter(\.enabledByDefault)),
                modules: [MenuBarModule: MenuBarModuleSettings] = [:], binaryUnits: Bool = true) {
        self.visible = visible; self.layout = layout; self.groupedStyle = groupedStyle
        self.groupedMetric = groupedMetric; self.groupedBadge = groupedBadge
        self.order = Self.completeOrder(order); self.enabled = enabled; self.modules = modules
        self.binaryUnits = binaryUnits
    }

    public func settings(for module: MenuBarModule) -> MenuBarModuleSettings {
        (modules[module] ?? .defaults(for: module)).normalized(for: module)
    }

    /// Enabled modules in display order.
    public var enabledModules: [MenuBarModule] { order.filter(enabled.contains) }

    /// Appends missing modules and drops duplicates, so the order always lists every module once.
    static func completeOrder(_ order: [MenuBarModule]) -> [MenuBarModule] {
        var seen = Set<MenuBarModule>()
        return (order + MenuBarModule.allCases).filter { seen.insert($0).inserted }
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        migrateIfNeeded(defaults)
        let order = (defaults.string(forKey: orderKey) ?? "").split(separator: ",")
            .compactMap { MenuBarModule(rawValue: String($0)) }
        var modules: [MenuBarModule: MenuBarModuleSettings] = [:]
        let decoder = JSONDecoder()
        for module in MenuBarModule.allCases {
            if let data = defaults.data(forKey: moduleKey(module)),
               let settings = try? decoder.decode(MenuBarModuleSettings.self, from: data) {
                modules[module] = settings.normalized(for: module)
            }
        }
        let enabled = MenuBarModule.allCases.filter {
            defaults.object(forKey: $0.enabledKey) as? Bool ?? $0.enabledByDefault
        }
        return Self(visible: defaults.object(forKey: visibleKey) as? Bool ?? true,
                    layout: defaults.string(forKey: layoutKey).flatMap(MenuBarLayout.init(rawValue:)) ?? .grouped,
                    groupedStyle: defaults.string(forKey: groupedStyleKey).flatMap(MenuBarGroupedStyle.init(rawValue:)) ?? .defaultValue,
                    groupedMetric: defaults.string(forKey: groupedMetricKey).flatMap(MenuBarModule.init(rawValue:)) ?? .cpu,
                    groupedBadge: defaults.object(forKey: groupedBadgeKey) as? Bool ?? true,
                    order: order, enabled: Set(enabled), modules: modules,
                    binaryUnits: defaults.string(forKey: unitsKey) != "decimal")
    }

    /// Writes only values that differ from what is stored, so observers of
    /// `UserDefaults.didChangeNotification` are not flooded.
    public func save(to defaults: UserDefaults = .standard) {
        func set(_ value: Any, _ key: String) {
            if let current = defaults.object(forKey: key) as? NSObject, let new = value as? NSObject, current == new { return }
            defaults.set(value, forKey: key)
        }
        set(visible, Self.visibleKey)
        set(layout.rawValue, Self.layoutKey)
        set(groupedStyle.rawValue, Self.groupedStyleKey)
        set(groupedMetric.rawValue, Self.groupedMetricKey)
        set(groupedBadge, Self.groupedBadgeKey)
        set(order.map(\.rawValue).joined(separator: ","), Self.orderKey)
        set(binaryUnits ? "binary" : "decimal", Self.unitsKey)
        for module in MenuBarModule.allCases {
            set(enabled.contains(module), module.enabledKey)
            if let settings = modules[module], let data = try? Self.encoder.encode(settings) {
                set(data, Self.moduleKey(module))
            }
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    // MARK: Migration

    /// Converts the pre-module "MacPocket.bar.*" keys once. Idempotent: guarded by `schemaKey`.
    /// Legacy keys are left in place (other app versions may still read them) except where noted.
    public static func migrateIfNeeded(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: schemaKey) < schemaVersion else { return }
        defer { defaults.set(schemaVersion, forKey: schemaKey) }
        let legacyKeys = ["MacPocket.bar.layout", "MacPocket.bar.style", "MacPocket.bar.labels", "MacPocket.bar.icons",
                          "MacPocket.bar.decimals", "MacPocket.bar.memoryValue", "MacPocket.bar.memoryPercent",
                          "MacPocket.bar.diskPercent", "MacPocket.bar.volume", "MacPocket.bar.order",
                          "MacPocket.bar.memory", "MacPocket.bar.disk", "MacPocket.bar.battery",
                          "MacPocket.bar.power", "MacPocket.menuBarCPU"]
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }

        if let layout = defaults.string(forKey: "MacPocket.bar.layout") {
            defaults.set(layout == "separate" ? MenuBarLayout.separate.rawValue : MenuBarLayout.grouped.rawValue,
                         forKey: layoutKey)
        }
        // The old bar showed live values; keep it live rather than collapsing to the static glyph.
        defaults.set(MenuBarGroupedStyle.dial.rawValue, forKey: groupedStyleKey)

        // Old enable defaults: only CPU was on. Make them explicit so new defaults don't add items.
        func legacyBool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        let battery = legacyBool("MacPocket.bar.battery", false)
        let power = legacyBool("MacPocket.bar.power", false)
        defaults.set(legacyBool("MacPocket.menuBarCPU", true), forKey: MenuBarModule.cpu.enabledKey)
        defaults.set(legacyBool("MacPocket.bar.memory", false), forKey: MenuBarModule.memory.enabledKey)
        defaults.set(legacyBool("MacPocket.bar.disk", false), forKey: MenuBarModule.disk.enabledKey)
        defaults.set(battery || power, forKey: MenuBarModule.power.enabledKey)
        defaults.set(false, forKey: MenuBarModule.network.enabledKey)
        defaults.removeObject(forKey: "MacPocket.bar.battery")

        if let order = defaults.string(forKey: "MacPocket.bar.order") {
            let mapped = order.split(separator: ",").compactMap { item -> MenuBarModule? in
                item == "battery" ? .power : MenuBarModule(rawValue: String(item))
            }
            defaults.set(completeOrder(mapped).map(\.rawValue).joined(separator: ","), forKey: orderKey)
        }

        let oldStyle = defaults.string(forKey: "MacPocket.bar.style") ?? "text"
        let style: MenuBarDisplayStyle = oldStyle == "text" ? .value : .gauge
        let showValue = oldStyle != "gaugeOnly"
        let labels = legacyBool("MacPocket.bar.labels", true)
        let icons = legacyBool("MacPocket.bar.icons", true)
        let decimals = legacyBool("MacPocket.bar.decimals", false)
        for module in MenuBarModule.allCases {
            var settings = MenuBarModuleSettings.defaults(for: module)
            settings.style = style; settings.showValue = showValue
            settings.showLabel = labels; settings.showIcon = icons; settings.decimals = decimals
            switch module {
            case .memory:
                let percent = legacyBool("MacPocket.bar.memoryPercent", false)
                switch defaults.string(forKey: "MacPocket.bar.memoryValue") ?? "used" {
                case "free": settings.value = .memoryFreeBytes
                default: settings.value = percent ? .memoryUsedPercent : .memoryUsedBytes
                }
            case .disk:
                settings.value = legacyBool("MacPocket.bar.diskPercent", false) ? .diskUsedPercent : .diskFreeBytes
                settings.volumePath = defaults.string(forKey: "MacPocket.bar.volume") ?? ""
            case .power:
                settings.value = battery ? .powerBattery : .powerSource
            case .network, .weather:
                settings = .defaults(for: module)
            case .cpu, .gpu:
                break
            }
            if let data = try? encoder.encode(settings) { defaults.set(data, forKey: moduleKey(module)) }
        }
    }
}

// MARK: - Formatting

/// What a module renders in the menu bar for one snapshot.
public struct MenuBarReading: Equatable, Sendable {
    /// One or two text lines (two for stacked network up/down).
    public let lines: [String]
    /// Widest plausible text for each line, used to reserve a stable width so the item doesn't jitter.
    public let reserve: [String]
    /// 0…1 for gauges and graphs; nil when the value has no natural scale (rates, source).
    public let fraction: Double?
    /// Raw magnitude for graphs of unbounded values (bytes/s); graphs normalise against recent maximum.
    public let magnitude: Double?
    /// Spoken description, e.g. "CPU: %12 kullanım".
    public let accessibility: String
    /// The value in its threshold unit (see `MenuBarValue.thresholdUnit`), nil when it has none.
    public var thresholdValue: Double? = nil
}

public enum MenuBarFormatter {
    /// Follows the app language: Turkish "%12,5" (prefix, comma), English "12.5%".
    public static func percent(_ value: Double, decimals: Bool) -> String {
        let clamped = min(100, max(0, value))
        return percentText(number(clamped, fractionDigits: decimals ? 1 : 0))
    }

    /// Places an already formatted number in the language's percent pattern ("#" marks the number);
    /// the Turkish default puts the sign first.
    public static func percentText(_ number: String) -> String {
        String(localized: "MenuBar.percentPattern", defaultValue: "%#").replacingOccurrences(of: "#", with: number)
    }

    public static func number(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", value)
            .replacingOccurrences(of: ".", with: String(localized: "MenuBar.decimalSeparator", defaultValue: ","))
    }

    /// Compact size, e.g. "512 MB", "1,2 GB", "18 GB". One decimal below 10 of a unit.
    public static func bytes(_ value: Double, binary: Bool, decimals: Bool = false) -> String {
        let base: Double = binary ? 1024 : 1000
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = max(0, value)
        var index = 0
        while scaled >= base * 0.9995, index < units.count - 1 { scaled /= base; index += 1 }
        let digits = index == 0 ? 0 : (decimals || scaled < 9.95 ? 1 : 0)
        return number(scaled, fractionDigits: digits) + " " + units[index]
    }

    /// Transfer rate, e.g. "0 KB/s", "84 KB/s", "1,2 MB/s". Never shows bytes, to keep width steady.
    public static func rate(_ bytesPerSecond: Double?, binary: Bool) -> String {
        guard let bytesPerSecond else { return "— KB/s" }
        let base: Double = binary ? 1024 : 1000
        let kilo = max(0, bytesPerSecond) / base
        if kilo < base * 0.9995 { return number(kilo, fractionDigits: 0) + " KB/s" }
        return bytes(bytesPerSecond, binary: binary) + "/s"
    }

    public static var rpmUnit: String { String(localized: "MenuBar.rpm", defaultValue: "rpm") }

    /// `ProcessInfo.ThermalState` names as produced by the system monitor.
    public static func thermalTitle(_ state: String) -> String {
        switch state {
        case "nominal": String(localized: "Normal")
        case "fair": String(localized: "Hafif yüksek")
        case "serious": String(localized: "Yüksek")
        case "critical": String(localized: "Kritik")
        default: String(localized: "Bilinmiyor")
        }
    }

    /// Thermal pressure on a 0…1 scale for gauges; nil for an unknown state.
    public static func thermalLevel(_ state: String) -> Double? {
        switch state {
        case "nominal": 0.25
        case "fair": 0.5
        case "serious": 0.75
        case "critical": 1
        default: nil
        }
    }

    public static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        return hours > 0 ? "\(hours):" + String(format: "%02d", rest) : String(localized: "\(rest) dk")
    }

    public static func reading(_ module: MenuBarModule, settings raw: MenuBarModuleSettings,
                               snapshot: SystemSnapshot?, binaryUnits: Bool = true, weather: WeatherSnapshot? = nil) -> MenuBarReading {
        if module == .weather {
            let settings = raw.normalized(for: module)
            let value = settings.value == .weatherApparent ? weather?.current.apparent : weather?.current.temperature
            let text = value.map { number($0, fractionDigits: settings.decimals ? 1 : 0) + "°" } ?? "—°"
            let spoken = weather.map { String(localized: "Hava durumu, \($0.location.name): \(settings.value.title), \(text)") }
                ?? String(localized: "Hava durumu: bir konum seç")
            return MenuBarReading(lines: [text], reserve: [settings.decimals ? "−88.8°" : "−88°"], fraction: nil,
                                  magnitude: value, accessibility: spoken)
        }
        var reading = baseReading(module, settings: raw, snapshot: snapshot, binaryUnits: binaryUnits)
        let value = raw.normalized(for: module).value
        switch value.thresholdUnit {
        case .percent?: reading.thresholdValue = reading.fraction.map { $0 * 100 }
        case .celsius?, .milliseconds?: reading.thresholdValue = reading.fraction == nil ? nil : reading.magnitude
        case .dBm?: reading.thresholdValue = reading.fraction == nil ? nil : snapshot?.connectivity?.wifiRSSI.map(Double.init)
        case nil: break
        }
        return reading
    }

    private static func baseReading(_ module: MenuBarModule, settings raw: MenuBarModuleSettings,
                                    snapshot: SystemSnapshot?, binaryUnits: Bool) -> MenuBarReading {
        let settings = raw.normalized(for: module)
        let decimals = settings.decimals
        let percentReserve = percent(100, decimals: decimals)
        let bytesReserve = "1023 GB"
        func pending(_ reserve: String = percentReserve) -> MenuBarReading {
            MenuBarReading(lines: ["—"], reserve: [reserve], fraction: nil, magnitude: nil,
                           accessibility: String(localized: "\(module.title): ölçüm bekleniyor"))
        }
        guard let s = snapshot else {
            return module == .network && settings.value == .networkUpDown
                ? MenuBarReading(lines: ["↑ —", "↓ —"], reserve: ["↑ 999 KB/s", "↓ 999 KB/s"], fraction: nil, magnitude: nil,
                                 accessibility: String(localized: "Ağ: ölçüm bekleniyor"))
                : pending()
        }
        if module == .network, s.connectivity?.online == false {
            let text = String(localized: "Çevrimdışı")
            return MenuBarReading(lines: [text], reserve: [text], fraction: nil, magnitude: nil,
                                  accessibility: String(localized: "Ağ: internet bağlantısı yok"))
        }
        switch settings.value {
        case .weatherTemperature, .weatherApparent: return pending()
        case .gpuUtilization, .gpuRenderer:
            guard let gpu = s.gpu else { return pending() }
            let value = settings.value == .gpuRenderer ? (gpu.rendererPercent ?? gpu.utilizationPercent) : gpu.utilizationPercent
            let text = percent(value, decimals: decimals)
            let spoken = settings.value == .gpuRenderer ? String(localized: "GPU işleyici: \(text)") : String(localized: "GPU: \(text) kullanım")
            return MenuBarReading(lines: [text], reserve: [percentReserve], fraction: value / 100, magnitude: value, accessibility: spoken)
        case .gpuMemory:
            guard let used = s.gpu?.memoryInUseBytes else { return pending(bytesReserve) }
            let text = bytes(Double(used), binary: binaryUnits, decimals: decimals)
            let fraction = s.physicalMemoryBytes > 0 ? min(1, Double(used) / Double(s.physicalMemoryBytes)) : nil
            return MenuBarReading(lines: [text], reserve: [bytesReserve], fraction: fraction, magnitude: fraction.map { $0 * 100 },
                                  accessibility: String(localized: "GPU belleği: \(text)"))
        case .networkPing:
            guard let connectivity = s.connectivity else { return pending("999 ms") }
            if connectivity.pingFailed {
                return MenuBarReading(lines: ["—"], reserve: ["999 ms"], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Gecikme: yanıt yok"))
            }
            guard let ms = connectivity.pingMilliseconds else { return pending("999 ms") }
            let text = number(ms, fractionDigits: decimals && ms < 100 ? 1 : 0) + " ms"
            return MenuBarReading(lines: [text], reserve: ["999 ms"], fraction: min(1, ms / 150), magnitude: ms,
                                  accessibility: String(localized: "Gecikme: \(text)"))
        case .networkWifiSignal:
            guard let connectivity = s.connectivity else { return pending("-100 dBm") }
            guard let rssi = connectivity.wifiRSSI else {
                return MenuBarReading(lines: ["—"], reserve: ["-100 dBm"], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Wi-Fi bağlı değil"))
            }
            let text = "\(rssi) dBm"
            // −90 dBm (unusable) … −30 dBm (next to the router).
            let fraction = min(1, max(0, Double(rssi + 90) / 60))
            return MenuBarReading(lines: [text], reserve: ["-100 dBm"], fraction: fraction, magnitude: fraction * 100,
                                  accessibility: String(localized: "Wi-Fi sinyali: \(text), \(WiFiSignalQuality(rssi: rssi).title)"))
        case .diskReadWrite:
            let read = s.diskIO?.readBytesPerSecond, write = s.diskIO?.writeBytesPerSecond
            let readText = rate(read, binary: binaryUnits), writeText = rate(write, binary: binaryUnits)
            let readMark = String(localized: "MenuBar.diskReadMark", defaultValue: "O"), writeMark = String(localized: "MenuBar.diskWriteMark", defaultValue: "Y")
            return MenuBarReading(lines: [readMark + " " + readText, writeMark + " " + writeText],
                                  reserve: [readMark + " 999 KB/s", writeMark + " 999 KB/s"], fraction: nil,
                                  magnitude: read.flatMap { r in write.map { r + $0 } },
                                  accessibility: String(localized: "Disk etkinliği: okuma \(readText), yazma \(writeText)"))
        case .cpuTotal, .cpuUser, .cpuSystem:
            guard let user = s.cpuUserPercent, let system = s.cpuSystemPercent else { return pending() }
            let value = settings.value == .cpuUser ? user : settings.value == .cpuSystem ? system : min(100, user + system)
            let text = percent(value, decimals: decimals)
            let spoken = settings.value == .cpuUser ? String(localized: "CPU: \(text) kullanıcı")
                : settings.value == .cpuSystem ? String(localized: "CPU: \(text) sistem") : String(localized: "CPU: \(text) kullanım")
            return MenuBarReading(lines: [text], reserve: [percentReserve],
                                  fraction: value / 100, magnitude: value, accessibility: spoken)
        case .memoryUsedPercent, .memoryUsedBytes, .memoryFreeBytes:
            guard let used = s.usedMemoryBytes, s.physicalMemoryBytes > 0 else { return pending() }
            let total = Double(s.physicalMemoryBytes)
            let fraction = min(1, Double(used) / total)
            switch settings.value {
            case .memoryUsedPercent:
                let text = percent(fraction * 100, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: [percentReserve], fraction: fraction, magnitude: fraction * 100,
                                      accessibility: String(localized: "Bellek: \(text) kullanılıyor"))
            case .memoryUsedBytes:
                let text = bytes(Double(used), binary: binaryUnits, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: [bytesReserve], fraction: fraction, magnitude: fraction * 100,
                                      accessibility: String(localized: "Bellek: \(text) kullanılıyor"))
            default:
                let free = max(0, total - Double(used))
                let text = bytes(free, binary: binaryUnits, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: [bytesReserve], fraction: fraction, magnitude: fraction * 100,
                                      accessibility: String(localized: "Bellek: \(text) kullanılabilir"))
            }
        case .memoryPressure:
            guard let pressure = s.memoryPressurePercent else { return pending() }
            let text = percent(pressure, decimals: decimals)
            return MenuBarReading(lines: [text], reserve: [percentReserve], fraction: pressure / 100, magnitude: pressure,
                                  accessibility: String(localized: "Bellek baskısı: \(text)"))
        case .diskFreeBytes, .diskUsedPercent, .diskFreePercent:
            let path = settings.volumePath
            guard let volume = path.isEmpty ? (s.volumes.first { $0.path == "/" } ?? s.volumes.first)
                                            : s.volumes.first(where: { $0.path == path }),
                  volume.totalBytes > 0 else {
                return pending(settings.value == .diskFreeBytes ? bytesReserve : percentReserve)
            }
            let free = Double(max(0, volume.availableBytes))
            let total = Double(volume.totalBytes)
            let usedFraction = min(1, max(0, (total - free) / total))
            switch settings.value {
            case .diskFreeBytes:
                let text = bytes(free, binary: binaryUnits, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: [bytesReserve], fraction: usedFraction, magnitude: usedFraction * 100,
                                      accessibility: String(localized: "\(volume.name): \(text) boş"))
            case .diskUsedPercent:
                let text = percent(usedFraction * 100, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: [percentReserve], fraction: usedFraction, magnitude: usedFraction * 100,
                                      accessibility: String(localized: "\(volume.name): \(text) dolu"))
            default:
                let text = percent((1 - usedFraction) * 100, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: [percentReserve], fraction: usedFraction, magnitude: usedFraction * 100,
                                      accessibility: String(localized: "\(volume.name): \(text) boş"))
            }
        case .diskActivity:
            let read = s.diskIO?.readBytesPerSecond, write = s.diskIO?.writeBytesPerSecond
            let total = read.flatMap { r in write.map { r + $0 } }
            let text = rate(total, binary: binaryUnits)
            let readText = rate(read, binary: binaryUnits), writeText = rate(write, binary: binaryUnits)
            return MenuBarReading(lines: [text], reserve: ["999 KB/s"], fraction: nil, magnitude: total,
                                  accessibility: String(localized: "Disk etkinliği: okuma \(readText), yazma \(writeText)"))
        case .networkUpDown, .networkCombined, .networkDownload, .networkUpload:
            let down = s.network?.receivedBytesPerSecond, up = s.network?.sentBytesPerSecond
            let downText = rate(down, binary: binaryUnits), upText = rate(up, binary: binaryUnits)
            let spoken = String(localized: "Ağ: alma \(downText), gönderme \(upText)")
            switch settings.value {
            case .networkUpDown:
                return MenuBarReading(lines: ["↑ " + rate(up, binary: binaryUnits), "↓ " + rate(down, binary: binaryUnits)],
                                      reserve: ["↑ 999 KB/s", "↓ 999 KB/s"], fraction: nil,
                                      magnitude: s.network?.combinedBytesPerSecond, accessibility: spoken)
            case .networkCombined:
                let combined = s.network?.combinedBytesPerSecond
                return MenuBarReading(lines: [rate(combined, binary: binaryUnits)], reserve: ["999 KB/s"], fraction: nil,
                                      magnitude: combined, accessibility: spoken)
            case .networkDownload:
                return MenuBarReading(lines: ["↓ " + rate(down, binary: binaryUnits)], reserve: ["↓ 999 KB/s"], fraction: nil,
                                      magnitude: down, accessibility: spoken)
            default:
                return MenuBarReading(lines: ["↑ " + rate(up, binary: binaryUnits)], reserve: ["↑ 999 KB/s"], fraction: nil,
                                      magnitude: up, accessibility: spoken)
            }
        case .powerFanSpeed, .powerFanPercent:
            let reserve = settings.value == .powerFanSpeed ? "9999 " + rpmUnit : percentReserve
            guard let fans = s.fans else { return pending(reserve) }
            guard let fastest = fans.max(by: { $0.rpm < $1.rpm }) else {
                return MenuBarReading(lines: ["—"], reserve: [reserve], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Bu Mac’te fan yok"))
            }
            let speed = number(fastest.rpm, fractionDigits: 0) + " " + rpmUnit
            let text = settings.value == .powerFanPercent ? fastest.fraction.map { percent($0 * 100, decimals: decimals) } ?? speed : speed
            let spoken = fans.count > 1 ? String(localized: "En hızlı fan: \(speed)") : String(localized: "Fan: \(speed)")
            return MenuBarReading(lines: [text], reserve: [reserve], fraction: fastest.fraction, magnitude: fastest.rpm,
                                  accessibility: spoken)
        case .powerThermal:
            let text = thermalTitle(s.thermalState)
            let level = thermalLevel(s.thermalState)
            // The state changes rarely, so the item sizes to the current word instead of reserving the
            // widest one (which left a wide gap after short states like "Normal").
            return MenuBarReading(lines: [text], reserve: [text], fraction: level, magnitude: level.map { $0 * 100 },
                                  accessibility: String(localized: "Isı durumu: \(text)"))
        case .powerTemperature:
            guard let readings = s.temperatures else { return pending("100°") }
            let chosen = settings.sensorName.isEmpty ? nil : readings.first { $0.name == settings.sensorName }
            guard let sensor = chosen ?? TemperatureSummary.hottest(readings) else {
                return MenuBarReading(lines: ["—"], reserve: ["100°"], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Bu Mac sıcaklık sensörü yayınlamıyor."))
            }
            let text = number(sensor.celsius, fractionDigits: decimals ? 1 : 0) + "°"
            return MenuBarReading(lines: [text], reserve: [decimals ? "100,0°" : "100°"], fraction: min(1, max(0, sensor.celsius / 100)),
                                  magnitude: sensor.celsius,
                                  accessibility: chosen == nil ? String(localized: "En sıcak sensör: \(text)C")
                                                               : String(localized: "\(sensor.name): \(text)C"))
        case .powerBattery, .powerTimeRemaining, .powerSource:
            let power = s.power
            let charging = power.isCharging == true
            func batterySpoken(_ text: String) -> String {
                charging ? String(localized: "Pil: \(text) (şarj oluyor)") : String(localized: "Pil: \(text)")
            }
            if settings.value == .powerSource || !power.batteryPresent {
                let mains = String(localized: "Priz")
                let text = power.source == "AC Power" ? mains : power.source == "Battery Power" ? String(localized: "Pil")
                    : power.source == "UPS Power" ? "UPS" : "—"
                let spoken = power.lowPowerMode ? String(localized: "Güç kaynağı: \(text), düşük güç modu")
                                                : String(localized: "Güç kaynağı: \(text)")
                return MenuBarReading(lines: [text + (power.lowPowerMode ? " ↓" : "")], reserve: [mains + " ↓"],
                                      fraction: power.chargePercent.map { $0 / 100 }, magnitude: power.chargePercent,
                                      accessibility: spoken)
            }
            guard let charge = power.chargePercent else { return pending() }
            if settings.value == .powerTimeRemaining {
                let text = power.minutesRemaining.map { duration(minutes: $0) } ?? percent(charge, decimals: decimals)
                return MenuBarReading(lines: [text], reserve: ["99:59"], fraction: charge / 100, magnitude: charge,
                                      accessibility: batterySpoken(percent(charge, decimals: decimals))
                                          + (power.minutesRemaining.map { String(localized: ", kalan \(duration(minutes: $0))") } ?? ""))
            }
            let text = percent(charge, decimals: decimals)
            return MenuBarReading(lines: [text], reserve: [percentReserve], fraction: charge / 100, magnitude: charge,
                                  accessibility: batterySpoken(text))
        }
    }
}

// MARK: - Attention

/// Whether the grouped icon carries its attention dot. Independent of notification settings: the dot is a
/// glanceable state, not an alert. Uses the same rules as resource alerts, with every condition enabled.
public enum MenuBarAttention {
    public static func isNeeded(_ snapshot: SystemSnapshot?, diskFreeThreshold: Double) -> Bool {
        !reasons(snapshot, diskFreeThreshold: diskFreeThreshold).isEmpty
    }

    /// Spoken reasons, in a stable order, for the accessibility label and tooltip.
    public static func reasons(_ snapshot: SystemSnapshot?, diskFreeThreshold: Double) -> [String] {
        guard let snapshot else { return [] }
        let everything = ResourceAlertSettings(enabled: Set(ResourceAlertKind.allCases), diskFreePercent: diskFreeThreshold)
        let triggered = ResourceAlertReading(snapshot).triggered(everything)
        return ResourceAlertKind.allCases.filter(triggered.contains).map { kind in
            switch kind {
            case .lowDisk: String(localized: "Disk alanı azaldı")
            case .thermal: String(localized: "Isı yüksek")
            case .memoryPressure: String(localized: "Bellek baskısı kritik")
            case .sustainedCPU: String(localized: "İşlemci uzun süredir yoğun")
            case .lowBattery: String(localized: "Pil azaldı")
            }
        }
    }
}

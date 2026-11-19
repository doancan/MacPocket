import AppKit
import Combine
import MacPocketCore
import SwiftUI

extension MenuBarModule {
    /// Module color identity, shared by the tab bar, detail views and settings.
    var tint: Color {
        switch self {
        case .cpu: PocketTheme.accent
        case .gpu: Color(hex: 0x30B0C7)
        case .memory: PocketTheme.memory
        case .disk: PocketTheme.disk
        case .network: Color(hex: 0x00A6C8)
        case .power: PocketTheme.power
        case .weather: Color(hex: 0xE67E00)
        case .aiUsage: Color(hex: 0x14A085)
        case .awake: Color(hex: 0xA2845E)
        case .focus: PocketTheme.brand
        case .bluetooth: .blue
        case .display: Color(hex: 0xD99A00)
        case .clock: Color(hex: 0xD6455D)
        case .clipboard: Color(hex: 0x5E6AD2)
        case .overview: PocketTheme.brand
        case .health: Color(hex: 0xE5484D)
        case .timeline: Color(hex: 0x8E6CEF)
        case .launcher: Color(hex: 0xF5A524)
        }
    }

    /// The name in the popover's tab bar: one short word, as toolbar labels are (HIG Toolbars). The full title
    /// heads the page.
    var tabTitle: String {
        switch self {
        case .overview: String(localized: "Özet")
        case .power: String(localized: "Güç")
        case .weather: String(localized: "Hava")
        case .aiUsage: "AI"
        case .awake: String(localized: "Uyanık")
        case .bluetooth: "Bluetooth"
        case .display: String(localized: "Ekran")
        default: title
        }
    }

    /// Whether the module can show anything right now. The clipboard tab and item exist only while clipboard
    /// history is on; the other modules show their own empty or disabled states.
    @MainActor var isRuntimeAvailable: Bool {
        switch self {
        case .clipboard: PocketModule.clipboard.isAvailable() && ClipboardService.shared.settings.enabled
        default: true
        }
    }

    /// Whether the detail view lists top processes (process sampling runs only while it is visible).
    var showsProcesses: Bool { self == .cpu || self == .memory }
}

/// Single source of truth for menu bar preferences. Writes go to UserDefaults through
/// `MenuBarPreferences.save` (diffed); external writes (General settings toggle) are picked up.
@MainActor
final class MenuBarSettingsStore: ObservableObject {
    static let shared = MenuBarSettingsStore()

    @Published var preferences: MenuBarPreferences {
        didSet { if preferences != oldValue { preferences.save() } }
    }
    private var subscription: AnyCancellable?

    private init() {
        let needsWeather = UserDefaults.standard.object(forKey: MenuBarModule.weather.enabledKey) == nil
        let needsBluetooth = UserDefaults.standard.object(forKey: MenuBarModule.bluetooth.enabledKey) == nil
        preferences = MenuBarPreferences.load()
        if needsWeather {
            preferences.enabled.insert(.weather)
            preferences.save()
        }
        // The Bluetooth page used to own a separate status item; carry its "show in menu bar" choice over once.
        if needsBluetooth, BluetoothBatteryService.legacyMenuBarItemRequested() {
            preferences.enabled.insert(.bluetooth)
            preferences.save()
        }
        subscription = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
    }

    private func reload() {
        let fresh = MenuBarPreferences.load()
        if fresh != preferences { preferences = fresh }
    }

    func settings(_ module: MenuBarModule) -> Binding<MenuBarModuleSettings> {
        Binding(get: { self.preferences.settings(for: module) },
                set: { self.preferences.modules[module] = $0 })
    }

    func enabled(_ module: MenuBarModule) -> Binding<Bool> {
        Binding(get: { self.preferences.enabled.contains(module) },
                set: { isOn in
                    if isOn { self.preferences.enabled.insert(module) } else { self.preferences.enabled.remove(module) }
                })
    }

    /// Moves an enabled module one place among the enabled ones (the order of switched-off modules is kept after them).
    func move(_ module: MenuBarModule, by offset: Int) {
        var enabled = preferences.enabledModules
        guard let index = enabled.firstIndex(of: module), enabled.indices.contains(index + offset) else { return }
        enabled.swapAt(index, index + offset)
        applyEnabledOrder(enabled)
    }

    /// Drag-and-drop reordering of the enabled modules, as `ForEach.onMove` reports it.
    func moveEnabled(from source: IndexSet, to destination: Int) {
        var enabled = preferences.enabledModules
        enabled.move(fromOffsets: source, toOffset: destination)
        applyEnabledOrder(enabled)
    }

    private func applyEnabledOrder(_ enabled: [MenuBarModule]) {
        preferences.order = enabled + preferences.order.filter { !preferences.enabled.contains($0) }
    }

    /// Back to the shipped look of one module; whether it is switched on stays as it is.
    func resetModule(_ module: MenuBarModule) {
        preferences.modules[module] = .defaults(for: module)
    }

    /// Every layout and module option back to the defaults; the menu bar stays visible or hidden as it was.
    func resetAll() {
        preferences = MenuBarPreferences(visible: preferences.visible)
    }
}

extension MenuBarGroupedStyle {
    var settingsSymbol: String {
        switch self {
        case .symbol: "app"
        case .dial: "speedometer"
        case .ring: "circle.circle"
        case .bars: "chart.bar.fill"
        case .sparkline: "waveform.path.ecg"
        case .value: "textformat.123"
        }
    }
}

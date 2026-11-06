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
        case .weather: .orange
        case .aiUsage: .mint
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
        preferences = MenuBarPreferences.load()
        if needsWeather {
            preferences.enabled.insert(.weather)
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

    func move(_ module: MenuBarModule, by offset: Int) {
        var order = preferences.order
        guard let index = order.firstIndex(of: module), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        preferences.order = order
    }
}

extension MenuBarGroupedStyle {
    var settingsSymbol: String {
        switch self {
        case .symbol: "app"
        case .dial: "speedometer"
        case .ring: "circle.circle"
        }
    }
}

/// Settings → Menü Çubuğu: the live editor first, then the selected module's options, then layout and units.
struct StatusBarPreferencesView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject private var store = MenuBarSettingsStore.shared
    @State private var selection: MenuBarModule?

    var body: some View {
        Form {
            Section {
                MenuBarEditor(model: model, selection: $selection)
                    .padding(.vertical, PocketSpacing.xs)
            } header: { Text("Menü çubuğu") }

            if let module = selection ?? store.preferences.enabledModules.first ?? store.preferences.order.first {
                Section {
                    HStack(spacing: PocketSpacing.s) {
                        PocketIconTile(symbol: module.symbol, tint: module.tint, size: 24)
                        Text(module.title).font(.headline)
                        Spacer(minLength: PocketSpacing.s)
                        Text("Menü çubuğunda").foregroundStyle(.secondary)
                        Toggle("Menü çubuğunda", isOn: store.enabled(module)).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                    if module == .aiUsage {
                        AIUsageSettingsView(embedded: true)
                    } else {
                        ModuleSettingsEditor(module: module, settings: store.settings(module), volumes: model.system?.volumes ?? [],
                                             sensors: (model.system?.temperatures ?? [])
                                                 .filter { TemperatureGroup.classify($0.name) != nil }.sorted { $0.name < $1.name },
                                             layout: store.preferences.layout)
                    }
                } header: { Text("Seçili modül") } footer: {
                    Text("Pil bilgileri yalnız pili olan Mac’lerde, fan hızı yalnız fanlı Mac’lerde gösterilir. Sığmayan öğeleri macOS ekran alanına göre gizleyebilir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Menü çubuğunda göster", isOn: $store.preferences.visible)
                LabeledContent("Düzen") {
                    GlassTabBar(tabs: MenuBarLayout.allCases.map { GlassTab(id: $0, title: $0.title) }, selection: $store.preferences.layout)
                        .frame(maxWidth: 220)
                }
                Text(store.preferences.layout == .grouped
                     ? "Sistem modülleri tek simgede toplanır; hava durumu ve AI kotaları etkinse ayrı gösterilir. Tıklayınca modülün ayrıntıları açılır."
                     : "Her etkin modül kendi menü çubuğu öğesini ve kendi ayarlarını kullanır. Gerçek menü çubuğunda öğeler ⌘ basılıyken de sürüklenebilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.preferences.layout == .grouped { groupedOptions }
            } header: { Text("Yerleşim") }

            Section {
                Picker("Boyut birimi", selection: $store.preferences.binaryUnits) {
                    Text("İkili (1024)").tag(true)
                    Text("Ondalık (1000)").tag(false)
                }
                Picker("Yenileme", selection: $model.refreshSeconds) {
                    Text("1 saniye").tag(1.0); Text("2 saniye").tag(2.0); Text("5 saniye").tag(5.0); Text("10 saniye").tag(10.0)
                }
                Text("Menü çubuğu ve ana pencere aynı ölçümleri kullanır. İzleme duraklatıldığında son değer korunur.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: { Text("Birimler ve örnekleme") }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var groupedOptions: some View {
        LabeledContent("Simge") {
            GlassTabBar(tabs: MenuBarGroupedStyle.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.settingsSymbol) },
                        selection: $store.preferences.groupedStyle)
                .frame(maxWidth: 380)
        }
        if store.preferences.groupedStyle.isLive {
            Picker("Göstergenin izlediği", selection: $store.preferences.groupedMetric) {
                ForEach(MenuBarModule.allCases.filter { $0 != .weather && $0 != .aiUsage }) { module in
                    Label(module.title, systemImage: module.symbol).tag(module)
                }
            }
            Text("Gösterge, modülün kendi ayarlarında seçili değeri izler; eşiğe göre renk açıksa simge de renklenir. Hız gibi üst sınırı olmayan değerler son ölçümlerin en yükseğine göre oranlanır.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Toggle("Dikkat gerektiğinde nokta göster", isOn: $store.preferences.groupedBadge)
        Text("Başlangıç diskindeki boş alan bildirim eşiğinin altına düştüğünde, ısı yükseldiğinde veya bellek baskısı kritikleştiğinde simgenin köşesinde nokta belirir; nedeni ipucunda yazar.")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Inline editor for one module's own menu bar options.
private struct ModuleSettingsEditor: View {
    let module: MenuBarModule
    @Binding var settings: MenuBarModuleSettings
    let volumes: [VolumeSnapshot]
    var sensors: [TemperatureReading] = []
    let layout: MenuBarLayout

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            if module == .weather { WeatherLocationPicker() }
            Picker("Değer", selection: $settings.value) {
                ForEach(module.valueOptions) { Text($0.title).tag($0) }
            }
            if module == .disk {
                Picker("Disk bölümü", selection: $settings.volumePath) {
                    Text("Başlangıç diski").tag("")
                    if !settings.volumePath.isEmpty, !volumes.contains(where: { $0.path == settings.volumePath }) {
                        Text("\(settings.volumePath) (bağlı değil)").tag(settings.volumePath)
                    }
                    ForEach(volumes, id: \.path) { Text($0.name).tag($0.path) }
                }
            }
            if module == .power && settings.value == .powerTemperature {
                Picker("Sensör", selection: $settings.sensorName) {
                    Text("En sıcak sensör").tag("")
                    if !settings.sensorName.isEmpty, !sensors.contains(where: { $0.name == settings.sensorName }) {
                        Text("\(settings.sensorName) (şu an yok)").tag(settings.sensorName)
                    }
                    ForEach(sensors, id: \.name) { sensor in
                        Text(verbatim: "\(sensor.name) · \(MenuBarFormatter.number(sensor.celsius, fractionDigits: 0))°").tag(sensor.name)
                    }
                }
            }
            if module == .network {
                Toggle("VPN bağlıyken kilit simgesi göster", isOn: $settings.showVPN)
                if settings.value == .networkPing {
                    Text("Gecikme her 10 saniyede 1.1.1.1’e tek bir ping paketiyle ölçülür; bu değer seçili değilken hiç paket gönderilmez.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Text("Görünüm")
                GlassTabBar(tabs: module.styleOptions.map { GlassTab(id: $0, title: $0.title) }, selection: $settings.style)
                    .frame(maxWidth: .infinity)
            }
            if settings.value.thresholdUnit != nil {
                LabeledContent("Renk") {
                    GlassTabBar(tabs: MenuBarColorMode.allCases.map { GlassTab(id: $0, title: $0.title) }, selection: $settings.colorMode)
                        .frame(maxWidth: 240)
                }
                if settings.colorMode == .thresholds { ThresholdEditor(settings: $settings) }
            }
            HStack(spacing: PocketSpacing.l) {
                Toggle("Etiket", isOn: $settings.showLabel)
                Toggle("Simge", isOn: $settings.showIcon)
                if settings.style.drawsLevel {
                    Toggle("Değer", isOn: $settings.showValue)
                }
                Toggle("Ondalık", isOn: $settings.decimals)
            }
            .disabled(settings.style == .icon)
            .toggleStyle(.checkbox)
            if module == .weather {
                Text("Hava durumu her düzende kendi menü çubuğu öğesinde gösterilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if layout == .grouped {
                Text("Gruplu düzende bu modül açılır pencerede kendi sekmesinde gösterilir; seçili değer canlı göstergeyi de besler. Görünüm seçenekleri Ayrı düzende uygulanır.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Warning and critical limits for a module's value, in its own unit.
private struct ThresholdEditor: View {
    @Binding var settings: MenuBarModuleSettings

    var body: some View {
        if let unit = settings.value.thresholdUnit, let limits = settings.thresholds {
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                row(String(localized: "Uyarı"), color: .orange, unit: unit, value: limits.warning) { settings.warningThreshold = $0 }
                row(String(localized: "Kritik"), color: .red, unit: unit, value: limits.critical) { settings.criticalThreshold = $0 }
                HStack {
                    Text(explanation(unit)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: PocketSpacing.s)
                    if settings.warningThreshold != nil || settings.criticalThreshold != nil {
                        Button("Varsayılana Dön") { settings.warningThreshold = nil; settings.criticalThreshold = nil }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func row(_ title: String, color: Color, unit: MenuBarThresholdUnit, value: Double,
                     set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { set(($0 / unit.step).rounded() * unit.step) }), in: unit.range)
            Text(verbatim: format(value, unit)).monospacedDigit().frame(width: 74, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func format(_ value: Double, _ unit: MenuBarThresholdUnit) -> String {
        switch unit {
        case .percent: MenuBarFormatter.percentText(MenuBarFormatter.number(value, fractionDigits: 0))
        default: MenuBarFormatter.number(value, fractionDigits: 0) + " " + unit.symbol
        }
    }

    private func explanation(_ unit: MenuBarThresholdUnit) -> String {
        let measured: String = switch settings.value {
        case .memoryFreeBytes, .diskFreeBytes, .diskFreePercent: String(localized: "Doluluk oranı")
        case .powerFanSpeed: String(localized: "Fanın en yüksek hıza oranı")
        case .powerTimeRemaining: String(localized: "Pil yüzdesi")
        default: String(localized: "Değer")
        }
        return String(localized: "\(measured) eşiğin \(settings.value.thresholdDirection) öğe turuncuya, kritik eşikte kırmızıya döner.")
    }
}

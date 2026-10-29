import AppKit
import Combine
import MacPocketCore
import SwiftUI

extension MenuBarModule {
    /// Module color identity, shared by the tab bar, detail views and settings.
    var tint: Color {
        switch self {
        case .cpu: PocketTheme.accent
        case .memory: PocketTheme.memory
        case .disk: PocketTheme.disk
        case .network: Color(hex: 0x00A6C8)
        case .power: PocketTheme.power
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
        preferences = MenuBarPreferences.load()
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

/// Settings → Menü Çubuğu.
struct StatusBarPreferencesView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject private var store = MenuBarSettingsStore.shared
    @ObservedObject private var history = MenuBarHistory.shared
    @State private var expanded: MenuBarModule?

    var body: some View {
        Form {
            Section {
                Toggle("Menü çubuğunda göster", isOn: $store.preferences.visible)
                Picker("Düzen", selection: $store.preferences.layout) {
                    ForEach(MenuBarLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(store.preferences.layout == .grouped
                     ? "Tek simge; tıklayınca her modül için bir sekme açılır. Etkin modüller simgede kompakt olarak gösterilir."
                     : "Her etkin modül kendi menü çubuğu öğesini ve kendi ayarlarını kullanır. Öğeler ⌘ basılıyken sürüklenebilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.preferences.layout == .grouped {
                    Picker("Simge görünümü", selection: $store.preferences.groupedStyle) {
                        ForEach(MenuBarGroupedStyle.allCases) { Text($0.title).tag($0) }
                    }
                }
                LabeledContent("Önizleme") { preview }
            } header: { Text("Yerleşim") }

            Section {
                ForEach(store.preferences.order) { module in
                    moduleRow(module)
                }
            } header: {
                Text("Modüller")
            } footer: {
                Text("Pil bilgileri yalnız pili olan Mac’lerde gösterilir. Sığmayan öğeleri macOS ekran alanına göre gizleyebilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

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

    @ViewBuilder private var preview: some View {
        let preferences = store.preferences
        if !preferences.visible {
            Text("Gizli").foregroundStyle(.secondary)
        } else if preferences.layout == .grouped || preferences.enabledModules.isEmpty {
            let readings = preferences.enabledModules.map {
                ($0, MenuBarFormatter.reading($0, settings: preferences.settings(for: $0), snapshot: model.system,
                                              binaryUnits: preferences.binaryUnits))
            }
            MenuBarItemPreview(image: MenuBarRenderer.grouped(style: preferences.groupedStyle, readings: readings,
                                                              history: history, preferences: preferences))
        } else {
            HStack(spacing: PocketSpacing.xs) {
                ForEach(preferences.enabledModules) { module in
                    MenuBarItemPreview(image: moduleImage(module))
                }
            }
        }
    }

    private func moduleImage(_ module: MenuBarModule) -> NSImage {
        let settings = store.preferences.settings(for: module)
        let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: model.system,
                                               binaryUnits: store.preferences.binaryUnits)
        return MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: model.system, history: history)
    }

    private func moduleRow(_ module: MenuBarModule) -> some View {
        let order = store.preferences.order
        let index = order.firstIndex(of: module) ?? 0
        return DisclosureGroup(isExpanded: Binding(get: { expanded == module },
                                                   set: { expanded = $0 ? module : nil })) {
            ModuleSettingsEditor(module: module, settings: store.settings(module), volumes: model.system?.volumes ?? [],
                                 layout: store.preferences.layout)
                .padding(.top, PocketSpacing.xs)
        } label: {
            HStack(spacing: PocketSpacing.s) {
                Toggle(isOn: store.enabled(module)) { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(module.title) modülünü menü çubuğunda göster")
                PocketIconTile(symbol: module.symbol, tint: module.tint, size: 20)
                Text(module.title)
                Spacer(minLength: PocketSpacing.s)
                if store.preferences.layout == .separate, store.preferences.enabled.contains(module) {
                    MenuBarItemPreview(image: moduleImage(module))
                }
                Button { store.move(module, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .help("Öne al")
                    .accessibilityLabel("\(module.title) modülünü öne al")
                Button { store.move(module, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == order.count - 1)
                    .help("Arkaya al")
                    .accessibilityLabel("\(module.title) modülünü arkaya al")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}

/// Inline editor for one module's own menu bar options.
private struct ModuleSettingsEditor: View {
    let module: MenuBarModule
    @Binding var settings: MenuBarModuleSettings
    let volumes: [VolumeSnapshot]
    let layout: MenuBarLayout

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
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
            Picker("Görünüm", selection: $settings.style) {
                ForEach(MenuBarDisplayStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: PocketSpacing.l) {
                Toggle("Etiket", isOn: $settings.showLabel)
                Toggle("Simge", isOn: $settings.showIcon)
                if settings.style == .graph || settings.style == .gauge {
                    Toggle("Değer", isOn: $settings.showValue)
                }
                Toggle("Ondalık", isOn: $settings.decimals)
            }
            .disabled(settings.style == .icon)
            .toggleStyle(.checkbox)
            if layout == .grouped {
                Text("Gruplu düzende bu modülün değeri ve ondalık ayarı tek simgede kullanılır; görünüm seçenekleri Ayrı düzende uygulanır.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

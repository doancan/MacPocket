import MacPocketCore
import SwiftUI

/// Every option of one menu bar module, grouped by what it changes: data, look, graph, text and color.
struct MenuBarModuleInspector: View {
    var model: PocketModel
    let module: MenuBarModule
    let provider: MenuBarImageProvider
    let surface: MenuBarSurface
    @ObservedObject var store: MenuBarSettingsStore
    @State private var confirmsReset = false

    private var settings: Binding<MenuBarModuleSettings> { store.settings(module) }
    private var current: MenuBarModuleSettings { store.preferences.settings(for: module) }
    private var volumes: [VolumeSnapshot] { model.system?.volumes ?? [] }
    private var sensors: [TemperatureReading] {
        (model.system?.temperatures ?? []).filter { TemperatureGroup.classify($0.name) != nil }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            header
            if store.preferences.layout == .grouped { placementCard }
            if module == .aiUsage {
                StudioCard(title: "Hesaplar", icon: "person.2.fill") { AIUsageSettingsView(embedded: true) }
            }
            if hasDataOptions { dataCard }
            appearanceCard
            if current.style == .graph { graphCard }
            if current.style != .icon { contentCard }
            colorCard
            resetRow
        }
        .confirmationDialog("Bu modülün görünümü varsayılana dönsün mü?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Varsayılana Dön", role: .destructive) { store.resetModule(module) }
        } message: { Text("Değer, görünüm, renk ve eşikler ilk haline döner. Modül açık ya da kapalı kalır.") }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketIconTile(symbol: module.symbol, tint: module.tint, size: PocketIconSize.feature).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(module.title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(provider.readingText(module).nonEmpty.map { String(localized: "Şu an: \($0)") } ?? "")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: PocketSpacing.m)
            Toggle("Menü çubuğunda", isOn: store.enabled(module)).pocketSwitch()
        }
        .pocketCard()
    }

    /// Grouped layout: each module lives in the grouped icon's popover, and can also get an item of its own.
    private var placementCard: some View {
        let ownItem = store.ownItem(module)
        return StudioCard(title: "Yerleşim", icon: "rectangle.3.group",
                          footer: ownItem.wrappedValue
                            ? "Modül menü çubuğunda kendi öğesiyle görünür; gruplu simgenin açılır penceresinde de sekmesi kalır."
                            : "Modül yalnız gruplu simgenin açılır penceresinde, kendi sekmesinde görünür. Aşağıdaki görünüm ayarları ayrı öğe için geçerlidir.") {
            Picker("Yerleşim", selection: ownItem) {
                Label("Grupta", systemImage: "square.stack").tag(false)
                Label("Ayrı öğe", systemImage: "rectangle.split.3x1").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(!store.preferences.enabled.contains(module))
        }
    }

    // MARK: Data

    private var hasDataOptions: Bool {
        module.valueOptions.count > 1 || [.weather, .disk, .network, .bluetooth, .clock].contains(module)
            || (module == .power && current.value == .powerTemperature)
    }

    private var dataCard: some View {
        StudioCard(title: "Veri", icon: "chart.xyaxis.line") {
            if module == .weather {
                WeatherLocationPicker()
                WeatherSourcePicker()
                Divider()
            }
            if module.valueOptions.count > 1 {
                StudioRow(title: "Gösterilen değer") {
                    Picker("Değer", selection: settings.value) {
                        ForEach(module.valueOptions) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pocketMenuPicker().fixedSize()
                }
            }
            if module == .disk {
                StudioRow(title: "Disk bölümü") {
                    Picker("Disk bölümü", selection: settings.volumePath) {
                        Text("Başlangıç diski").tag("")
                        if !current.volumePath.isEmpty, !volumes.contains(where: { $0.path == current.volumePath }) {
                            Text("\(current.volumePath) (bağlı değil)").tag(current.volumePath)
                        }
                        ForEach(volumes, id: \.path) { Text($0.name).tag($0.path) }
                    }
                    .labelsHidden().pocketMenuPicker().fixedSize()
                }
            }
            if module == .power && current.value == .powerTemperature {
                StudioRow(title: "Sensör") {
                    Picker("Sensör", selection: settings.sensorName) {
                        Text("En sıcak sensör").tag("")
                        if !current.sensorName.isEmpty, !sensors.contains(where: { $0.name == current.sensorName }) {
                            Text("\(current.sensorName) (şu an yok)").tag(current.sensorName)
                        }
                        ForEach(sensors, id: \.name) { sensor in
                            Text(verbatim: "\(sensor.name) · \(MenuBarFormatter.number(sensor.celsius, fractionDigits: 0))°").tag(sensor.name)
                        }
                    }
                    .labelsHidden().pocketMenuPicker().fixedSize()
                }
            }
            if module == .clock { clockOptions }
            if module == .network {
                StudioToggle(title: "VPN bağlıyken kilit simgesi göster", isOn: settings.showVPN)
                if current.value == .networkPing {
                    note("Gecikme her 10 saniyede 1.1.1.1’e tek bir ping paketiyle ölçülür; bu değer seçili değilken hiç paket gönderilmez.")
                }
            }
            if module == .bluetooth {
                note("Bağlı aygıtlardan pili en önce bitecek olanı gösterir; tıklayınca tüm aygıtlar listelenir. Pil azalınca bildirim ayarları Araçlar › Bluetooth Pilleri’ndedir.")
            }
        }
    }

    // MARK: Clock

    private var clockOptions: some View {
        Group {
            StudioRow(title: "Menü çubuğunda gösterilen saat dilimi") {
                Picker("Saat dilimi", selection: settings.timeZoneID) {
                    Text("Bu Mac’in saat dilimi").tag("")
                    ForEach(zoneChoices(including: current.timeZoneID), id: \.self) { Text(verbatim: MenuBarFormatter.cityName($0)).tag($0) }
                }
                .labelsHidden().pocketMenuPicker().fixedSize()
            }
            Divider()
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                HStack {
                    Text("Dünya saatleri")
                    Spacer()
                    Menu("Şehir Ekle", systemImage: "plus") {
                        ForEach(MenuBarFormatter.commonTimeZones.filter { !current.worldClocks.contains($0) }, id: \.self) { zone in
                            Button(MenuBarFormatter.cityName(zone)) { settings.wrappedValue.worldClocks.append(zone) }
                        }
                    }
                    .menuStyle(.button).tint(.primary).fixedSize()
                    .disabled(current.worldClocks.count >= 8)
                }
                if current.worldClocks.isEmpty {
                    note("Açılır pencerede listelenecek şehirleri ekle; en fazla sekiz.")
                }
                ForEach(current.worldClocks, id: \.self) { zone in
                    HStack {
                        Label { Text(verbatim: MenuBarFormatter.cityName(zone)) } icon: { Image(systemName: "globe") }
                        Spacer()
                        Text(verbatim: MenuBarFormatter.clockReading(value: .clockTime, zoneID: zone).lines.first ?? "")
                            .monospacedDigit().foregroundStyle(.secondary)
                        Button { settings.wrappedValue.worldClocks.removeAll { $0 == zone } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Kaldır"))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// The common zones, plus the current choice when it is not among them (a hand-edited preference).
    private func zoneChoices(including selected: String) -> [String] {
        selected.isEmpty || MenuBarFormatter.commonTimeZones.contains(selected) ? MenuBarFormatter.commonTimeZones
            : [selected] + MenuBarFormatter.commonTimeZones
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        StudioCard(title: "Görünüm", icon: "square.on.square.dashed", footer: appearanceFooter) {
            StyleGallery(choices: module.styleOptions.map { style in
                var variant = current
                variant.style = style
                return StyleChoice(id: style, title: Text(style.title), image: provider.image(module, settings: variant, demo: true))
            }, selection: settings.style, surface: surface)
        }
    }

    private var appearanceFooter: LocalizedStringKey? {
        if !module.isSystemMetric { return "Bu modül her düzende kendi menü çubuğu öğesinde gösterilir." }
        return nil
    }

    // MARK: Graph

    private var graphCard: some View {
        StudioCard(title: "Grafik", icon: "waveform.path.ecg") {
            StyleGallery(choices: MenuBarGraphKind.allCases.map { kind in
                var variant = current
                variant.graphKind = kind
                return StyleChoice(id: kind, title: Text(kind.title), image: provider.image(module, settings: variant))
            }, selection: settings.graphKind, surface: surface, minimumWidth: 150)
            StudioSegmented(title: "Genişlik", detail: "Geniş grafik daha uzun bir geçmişi gösterir.",
                            selection: settings.graphWidth) { Text($0.title) }
        }
    }

    // MARK: Text

    private var contentCard: some View {
        StudioCard(title: "Metin ve simge", icon: "textformat") {
            let columns = [GridItem(.adaptive(minimum: 250), spacing: PocketSpacing.xl, alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: PocketSpacing.m) {
                StudioToggle(title: "Etiket", isOn: settings.showLabel)
                StudioToggle(title: "Simge", isOn: settings.showIcon)
                if current.style.drawsLevel { StudioToggle(title: "Değer", isOn: settings.showValue) }
                if module != .clock { StudioToggle(title: "Ondalık", isOn: settings.decimals) }
            }
            Divider()
            if current.showLabel {
                StudioSegmented(title: "Etiket konumu", detail: "İki satırlı değerlerde etiket her zaman yanda durur.",
                                selection: settings.labelPosition) { Text($0.title) }
            }
            if current.showLabel || current.value == .networkUpDown || current.value == .diskReadWrite {
                StudioSegmented(title: "Hizalama", detail: "Üst üste duran etiket ve değer, iki satırlı değerler aynı kenara hizalanır.",
                                selection: settings.textAlignment) { Text($0.title) }
            }
            StudioSegmented(title: "Boyut", selection: settings.textSize) { Text($0.title) }
        }
    }

    // MARK: Color

    private var colorCard: some View {
        StudioCard(title: "Renk", icon: "paintpalette", footer: colorFooter) {
            if current.value.thresholdUnit != nil {
                StudioSegmented(title: "Renk kuralı", selection: settings.colorMode) { Text($0.title) }
            }
            // The detail line is always there (the color's name once one is picked), so the swatches never
            // jump.
            StudioRow(title: "Vurgu rengi", detail: current.accent == .automatic ? "Menü çubuğunun rengini izler." : LocalizedStringKey(current.accent.title)) {
                EmptyView()
            }
            AccentSwatches(selection: settings.accent)
            if current.value.thresholdUnit != nil, current.colorMode == .thresholds {
                Divider()
                ThresholdEditor(settings: settings, currentValue: provider.thresholdValue(module))
            }
        }
    }

    private var colorFooter: LocalizedStringKey? {
        guard current.accent != .automatic else { return nil }
        return current.colorMode == .thresholds
            ? "Vurgu rengi, açık ve koyu menü çubuğuna göre tonunu ayarlar. Eşik aşılınca öğe turuncuya ya da kırmızıya döner."
            : "Vurgu rengi, açık ve koyu menü çubuğuna göre tonunu ayarlar."
    }

    // MARK: Reset

    private var resetRow: some View {
        HStack {
            Spacer()
            Button("Bu Modülü Varsayılana Döndür…", role: .destructive) { confirmsReset = true }
                .buttonStyle(.bordered).tint(.red)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

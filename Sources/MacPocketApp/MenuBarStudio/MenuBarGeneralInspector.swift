import MacPocketCore
import SwiftUI

/// Layout-wide options: grouped or separate items, the grouped icon, units and sampling.
struct MenuBarGeneralInspector: View {
    @Bindable var model: PocketModel
    let provider: MenuBarImageProvider
    let surface: MenuBarSurface
    @ObservedObject var store: MenuBarSettingsStore
    @State private var confirmsReset = false

    private var preferences: MenuBarPreferences { store.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            layoutCard
            if preferences.layout == .grouped { groupedIconCard }
            unitsCard
            HStack {
                Spacer()
                Button("Tüm Menü Çubuğu Ayarlarını Sıfırla…", role: .destructive) { confirmsReset = true }
                    .buttonStyle(.bordered).tint(.red)
            }
        }
        .confirmationDialog("Menü çubuğu ayarları sıfırlansın mı?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Hepsini Sıfırla", role: .destructive) { store.resetAll() }
        } message: { Text("Düzen, sıra, açık modüller ve her modülün görünümü varsayılana döner. Menü çubuğu görünürlüğü korunur.") }
    }

    // MARK: Layout

    private var layoutCard: some View {
        StudioCard(title: "Yerleşim", icon: "rectangle.3.group", footer: layoutFooter) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                ForEach(MenuBarLayout.allCases) { layout in
                    LayoutOption(layout: layout, selected: preferences.layout == layout, surface: surface,
                                 images: images(for: layout)) {
                        withAnimation(.snappy(duration: 0.2)) { store.preferences.layout = layout }
                    }
                }
            }
        }
    }

    private var layoutFooter: LocalizedStringKey {
        preferences.layout == .grouped
            ? "Sistem modülleri tek simgede toplanır; hava durumu, AI kotaları, uyanık tut, odak, Bluetooth pilleri ve parlaklık etkinse ayrı gösterilir. Tıklayınca modülün ayrıntıları açılır."
            : "Her etkin modül kendi menü çubuğu öğesini ve kendi ayarlarını kullanır. Gerçek menü çubuğunda öğeler ⌘ basılıyken de sürüklenebilir."
    }

    /// A few real item images for the miniature of each layout.
    private func images(for layout: MenuBarLayout) -> [NSImage] {
        switch layout {
        case .grouped:
            var overridden = preferences
            overridden.layout = .grouped
            return [provider.grouped(overridden)]
        case .separate:
            let modules = (preferences.enabledModules.filter(\.isSystemMetric) + [.cpu, .memory, .network]).uniqued().prefix(3)
            return modules.map { provider.image($0) }
        }
    }

    // MARK: Grouped icon

    private var groupedIconCard: some View {
        StudioCard(title: "Gruplu simge", icon: "gauge.with.dots.needle.50percent", footer: groupedFooter) {
            StyleGallery(choices: MenuBarGroupedStyle.allCases.map { style in
                var overridden = preferences
                overridden.groupedStyle = style
                return StyleChoice(id: style, title: Text(style.title), image: provider.grouped(overridden))
            }, selection: $store.preferences.groupedStyle, surface: surface)
            if preferences.groupedStyle.isLive && preferences.groupedStyle != .bars {
                StudioRow(title: "Göstergenin izlediği") {
                    Picker("Göstergenin izlediği", selection: $store.preferences.groupedMetric) {
                        ForEach(MenuBarModule.allCases.filter(\.isSystemMetric)) { module in
                            Label(module.title, systemImage: module.symbol).tag(module)
                        }
                    }
                    .labelsHidden().pocketMenuPicker().fixedSize()
                }
            }
            StudioRow(title: "Simge rengi", detail: preferences.groupedAccent == .automatic ? "Menü çubuğunun rengini izler." : LocalizedStringKey(preferences.groupedAccent.title)) {
                EmptyView()
            }
            AccentSwatches(selection: $store.preferences.groupedAccent)
            Divider()
            StudioToggle(title: "Dikkat gerektiğinde nokta göster",
                         detail: "Başlangıç diskindeki boş alan bildirim eşiğinin altına düştüğünde, ısı yükseldiğinde veya bellek baskısı kritikleştiğinde simgenin köşesinde nokta belirir; nedeni ipucunda yazar.",
                         isOn: $store.preferences.groupedBadge)
        }
    }

    private var groupedFooter: LocalizedStringKey? {
        switch preferences.groupedStyle {
        case .symbol: nil
        case .bars: "Üç çubuk sırasıyla CPU, bellek ve başlangıç diskinin doluluğunu gösterir."
        case .dial, .ring, .sparkline:
            "Gösterge, modülün kendi ayarlarında seçili değeri izler; eşiğe göre renk açıksa simge de renklenir. Hız gibi üst sınırı olmayan değerler son ölçümlerin en yükseğine göre oranlanır."
        }
    }

    // MARK: Units

    private var unitsCard: some View {
        StudioCard(title: "Birimler ve örnekleme", icon: "ruler",
                   footer: "Menü çubuğu ve ana pencere aynı ölçümleri kullanır. İzleme duraklatıldığında son değer korunur.") {
            StudioRow(title: "Boyut birimi", detail: preferences.binaryUnits ? "1 GB = 1024 MB" : "1 GB = 1000 MB") {
                Picker("Boyut birimi", selection: $store.preferences.binaryUnits) {
                    Text("İkili (1024)").tag(true)
                    Text("Ondalık (1000)").tag(false)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            StudioRow(title: "Yenileme", detail: "Daha kısa aralık daha canlı grafik, biraz daha fazla işlemci kullanımı demektir.") {
                Picker("Yenileme", selection: $model.refreshSeconds) {
                    Text("1 sn").tag(1.0); Text("2 sn").tag(2.0); Text("5 sn").tag(5.0); Text("10 sn").tag(10.0)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
        }
    }
}

/// One of the two layouts, drawn as a miniature menu bar with its real items.
private struct LayoutOption: View {
    let layout: MenuBarLayout
    let selected: Bool
    let surface: MenuBarSurface
    let images: [NSImage]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                ZStack(alignment: .trailing) {
                    LinearGradient(colors: surface.wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing)
                    surface.barFill
                    HStack(spacing: 6) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                            Image(nsImage: surface.flatten(image)).resizable().interpolation(.high).scaledToFit()
                                .frame(height: image.size.height * 1.2)
                        }
                    }
                    .padding(.horizontal, PocketSpacing.m)
                }
                .frame(height: 38)
                .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous).strokeBorder(PocketTheme.line) }
                HStack {
                    Text(layout == .grouped ? "Gruplu" : "Ayrı").font(.headline)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(layout == .grouped ? "Tek simge, modüller açılır pencerede sekmelerde." : "Her modül kendi öğesinde, kendi açılır penceresiyle.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PocketSpacing.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.06 : 0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : PocketTheme.line, lineWidth: selected ? 2 : 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(layout == .grouped ? Text("Gruplu") : Text("Ayrı"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

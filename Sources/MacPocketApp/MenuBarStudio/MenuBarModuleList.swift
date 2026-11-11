import MacPocketCore
import SwiftUI

/// The modules, in menu bar order. Rows reorder by dragging (or with the VoiceOver actions and the context menu),
/// switch on and off in place, and select the module whose options the inspector shows.
struct MenuBarModuleList: View {
    @Binding var pane: MenuBarPane
    @ObservedObject var store: MenuBarSettingsStore
    let provider: MenuBarImageProvider

    private var enabled: [MenuBarModule] { store.preferences.enabledModules }
    private var disabled: [MenuBarModule] { store.preferences.order.filter { !store.preferences.enabled.contains($0) } }

    var body: some View {
        List(selection: Binding<MenuBarPane?>(get: { pane }, set: { if let value = $0 { pane = value } })) {
            Section {
                generalRow.tag(MenuBarPane.general)
            }
            Section {
                ForEach(enabled) { module in row(module, isOn: true) }
                    .onMove { store.moveEnabled(from: $0, to: $1) }
                if enabled.isEmpty {
                    Text("Hiçbir modül açık değil. MacPocket simgesi yine de menü çubuğunda kalır.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, PocketSpacing.xs)
                }
            } header: {
                Text("Menü çubuğunda")
            }
            if !disabled.isEmpty {
                Section {
                    ForEach(disabled) { module in row(module, isOn: false) }
                } header: {
                    Text("Kapalı")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .animation(.snappy(duration: 0.22), value: store.preferences.order)
        .animation(.snappy(duration: 0.22), value: store.preferences.enabled)
        .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous).strokeBorder(PocketTheme.line) }
        .clipShape(RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
    }

    private var generalRow: some View {
        HStack(spacing: PocketSpacing.s) {
            PocketIconTile(symbol: "slider.horizontal.3", tint: Color(hex: 0x5F6B7E), size: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Genel").font(.body)
                Text(store.preferences.layout == .grouped ? "Gruplu yerleşim" : "Ayrı yerleşim")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PocketSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func row(_ module: MenuBarModule, isOn: Bool) -> some View {
        HStack(spacing: PocketSpacing.s) {
            PocketIconTile(symbol: module.symbol, tint: module.tint, size: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(module.title).font(.body).lineLimit(1)
                Text(isOn ? provider.readingText(module) : String(localized: "Kapalı"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
            Spacer(minLength: PocketSpacing.xs)
            Toggle(isOn: Binding(get: { store.preferences.enabled.contains(module) }, set: { value in
                store.enabled(module).wrappedValue = value
                if value { pane = .module(module) }
            })) { Text(module.title) }
            .toggleStyle(.switch).controlSize(.small).labelsHidden()
            .help(Text("Menü çubuğunda"))
        }
        .padding(.vertical, PocketSpacing.xs)
        .tag(MenuBarPane.module(module))
        .contextMenu {
            if isOn {
                Button("Yukarı Taşı", systemImage: "arrow.up") { store.move(module, by: -1) }
                    .disabled(enabled.first == module)
                Button("Aşağı Taşı", systemImage: "arrow.down") { store.move(module, by: 1) }
                    .disabled(enabled.last == module)
                Divider()
            }
            Button(isOn ? "Menü Çubuğundan Kaldır" : "Menü Çubuğuna Ekle", systemImage: isOn ? "minus.circle" : "plus.circle") {
                store.enabled(module).wrappedValue = !isOn
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(pane == .module(module) ? .isSelected : [])
        .accessibilityAction(named: Text("Yukarı Taşı")) { if isOn { store.move(module, by: -1) } }
        .accessibilityAction(named: Text("Aşağı Taşı")) { if isOn { store.move(module, by: 1) } }
    }
}

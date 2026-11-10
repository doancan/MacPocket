import AppKit
import Combine
import MacPocketCore
import MacPocketAIUsage
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Menü Çubuğu: a live mock of the menu bar. Items render exactly as they will in the real menu bar,
/// reorder by dragging, open their options on click, and move to and from the shelf of switched-off modules.
struct MenuBarEditor: View {
    var model: PocketModel
    @Binding var selection: MenuBarModule?
    @ObservedObject private var store = MenuBarSettingsStore.shared
    @ObservedObject private var history = MenuBarHistory.shared
    @ObservedObject private var aiUsage = AIUsageService.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var appearance: PreviewAppearance = .system
    @State private var dragging: MenuBarModule?
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, tolerance: 5, on: .main, in: .common).autoconnect()

    enum PreviewAppearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: String(localized: "Sistem")
            case .light: String(localized: "Açık")
            case .dark: String(localized: "Koyu")
            }
        }
    }

    private var dark: Bool { appearance == .system ? systemScheme == .dark : appearance == .dark }
    private var preferences: MenuBarPreferences { store.preferences }
    private var disabled: [MenuBarModule] { preferences.order.filter { !preferences.enabled.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            canvas
            shelf
            HStack(spacing: PocketSpacing.s) {
                Label("Sürükleyerek sırala, rafa bırakarak kapat; ayarlamak için öğeye tıkla.", systemImage: "hand.draw")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: PocketSpacing.s)
                Picker("Önizleme", selection: $appearance) {
                    ForEach(PreviewAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
        .onReceive(clock) { now = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: preferences.order)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: preferences.enabled)
    }

    // MARK: Canvas

    private var canvas: some View {
        let foreground: Color = dark ? .white : .black
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: dark ? [Color(hex: 0x1B2A5E), Color(hex: 0x3A2470), Color(hex: 0x0E1430)]
                                                  : [Color(hex: 0x8FB4FF), Color(hex: 0xB9A4FF), Color(hex: 0xDCE6FF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 0) {
                bar(foreground)
                if !preferences.visible {
                    Label("Menü çubuğu öğesi gizli", systemImage: "eye.slash")
                        .font(.callout.weight(.medium)).foregroundStyle(foreground.opacity(0.8))
                        .padding(.top, PocketSpacing.l)
                } else if preferences.layout == .grouped {
                    groupedTabs(foreground)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: preferences.layout == .grouped ? 132 : 70)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PocketTheme.line) }
        // Dropping a shelf module anywhere on the canvas switches it on at the end.
        .onDrop(of: [.text], delegate: EnableDropDelegate(dragging: $dragging, store: store, selection: $selection))
    }

    private func bar(_ foreground: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "applelogo").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 6)
            Text(verbatim: "MacPocket").font(.system(size: 12.5, weight: .bold))
            Text("Dosya").font(.system(size: 12.5)).padding(.leading, 8).opacity(0.85)
            Text("Görünüm").font(.system(size: 12.5)).padding(.leading, 8).opacity(0.85)
            Spacer(minLength: PocketSpacing.m)
            if preferences.visible {
                if preferences.layout == .separate && !preferences.enabledModules.isEmpty {
                    ForEach(preferences.enabledModules) { module in
                        barItem(module, image: moduleImage(module), foreground: foreground)
                    }
                } else {
                    groupedItem(foreground)
                    ForEach([MenuBarModule.weather, .aiUsage].filter { preferences.enabled.contains($0) }) { module in
                        barItem(module, image: moduleImage(module), foreground: foreground)
                    }
                }
            }
            Image(systemName: "switch.2").font(.system(size: 12, weight: .medium)).padding(.horizontal, 7)
            Text(now.formatted(date: .omitted, time: .shortened)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                .padding(.trailing, 10)
        }
        .foregroundStyle(foreground)
        .frame(height: 30)
        .background(dark ? Color.black.opacity(0.38) : Color.white.opacity(0.55))
    }

    private func barItem(_ module: MenuBarModule, image: NSImage, foreground: Color) -> some View {
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5).frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(foreground.opacity(selection == module ? 0.22 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: selection == module ? 1.5 : 0)
            }
            .opacity(dragging == module ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture { selection = module }
            .onDrag {
                dragging = module
                return NSItemProvider(object: module.rawValue as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(target: module, dragging: $dragging, store: store, selection: $selection))
            .help(module.title)
            .accessibilityLabel(Text(module.title))
            .accessibilityAddTraits(selection == module ? [.isButton, .isSelected] : .isButton)
    }

    private func groupedItem(_ foreground: Color) -> some View {
        let attention = MenuBarAttention.isNeeded(model.system, diskFreeThreshold: ResourceAlertSettings.load(from: .standard).diskFreePercent)
        let image = MenuBarRenderer.grouped(MenuBarRenderer.groupedState(preferences: preferences, snapshot: model.system,
                                                                         history: history, attention: attention))
        return Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5).frame(height: 24)
            .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(foreground.opacity(0.22)) }
            .help(String(localized: "Gruplu simge"))
    }

    /// Grouped layout: the popover's tab strip hanging under the icon; its order is the module order.
    private func groupedTabs(_ foreground: Color) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Açılır pencere sekmeleri").font(.caption.weight(.semibold)).foregroundStyle(foreground.opacity(0.75))
            HStack(spacing: 6) {
                if preferences.enabledModules.isEmpty {
                    Text("Raftan modül sürükle").font(.caption).foregroundStyle(foreground.opacity(0.7))
                }
                ForEach(preferences.enabledModules) { module in
                    chip(module, selected: selection == module, onCanvas: true)
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(target: module, dragging: $dragging, store: store, selection: $selection))
                }
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 10).padding(.trailing, 70)
    }

    // MARK: Shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            Text("Kapalı modüller").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if disabled.isEmpty {
                    Text("Tüm modüller menü çubuğunda. Kapatmak için buraya sürükle.").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                ForEach(disabled) { module in
                    chip(module, selected: selection == module, onCanvas: false)
                        .onTapGesture {
                            store.enabled(module).wrappedValue = true
                            selection = module
                        }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(dragging.map { preferences.enabled.contains($0) } == true ? 0.09 : 0.04),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(PocketTheme.line)
            }
            .onDrop(of: [.text], delegate: DisableDropDelegate(dragging: $dragging, store: store))
        }
    }

    private func chip(_ module: MenuBarModule, selected: Bool, onCanvas: Bool) -> some View {
        HStack(spacing: 5) {
            PocketIconTile(symbol: module.symbol, tint: module.tint, size: 18)
            Text(module.title).font(.callout)
            if !onCanvas { Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(selected ? 0.12 : 0.06), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0) }
        .opacity(dragging == module ? 0.35 : 1)
        .contentShape(Capsule())
        .onTapGesture { selection = module }
        .onDrag {
            dragging = module
            return NSItemProvider(object: module.rawValue as NSString)
        }
        .help(onCanvas ? module.title : String(localized: "Menü çubuğuna eklemek için tıkla veya sürükle"))
    }

    private func moduleImage(_ module: MenuBarModule) -> NSImage {
        var settings = preferences.settings(for: module)
        if module == .aiUsage {
            settings.warningThreshold = aiUsage.settings.warning; settings.criticalThreshold = aiUsage.settings.critical
            if let image = AIUsageMenuBarImage.make(service: aiUsage, settings: settings, dark: dark) { return image }
        }
        let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: model.system, binaryUnits: preferences.binaryUnits, weather: WeatherService.shared.snapshot, aiUsage: aiUsage.menuBarReading)
        return MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: model.system, history: history)
    }
}

// MARK: - Drop handling

extension MenuBarSettingsStore {
    /// Moves `module` to `target`'s place among the enabled modules, switching it on if needed.
    func place(_ module: MenuBarModule, at target: MenuBarModule) {
        guard module != target else { return }
        var order = preferences.order
        let movingRight = (order.firstIndex(of: module) ?? 0) < (order.firstIndex(of: target) ?? 0)
            && preferences.enabled.contains(module)
        order.removeAll { $0 == module }
        guard let targetIndex = order.firstIndex(of: target) else { return }
        order.insert(module, at: movingRight ? targetIndex + 1 : targetIndex)
        var updated = preferences
        updated.order = order
        updated.enabled.insert(module)
        preferences = updated
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let target: MenuBarModule
    @Binding var dragging: MenuBarModule?
    let store: MenuBarSettingsStore
    @Binding var selection: MenuBarModule?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        MainActor.assumeIsolated { store.place(dragging, at: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let dragging { selection = dragging }
        dragging = nil
        return true
    }
}

private struct EnableDropDelegate: DropDelegate {
    @Binding var dragging: MenuBarModule?
    let store: MenuBarSettingsStore
    @Binding var selection: MenuBarModule?

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let module = dragging else { return false }
        MainActor.assumeIsolated {
            if !store.preferences.enabled.contains(module) { store.enabled(module).wrappedValue = true }
        }
        selection = module
        dragging = nil
        return true
    }
}

private struct DisableDropDelegate: DropDelegate {
    @Binding var dragging: MenuBarModule?
    let store: MenuBarSettingsStore

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let module = dragging else { return false }
        MainActor.assumeIsolated { store.enabled(module).wrappedValue = false }
        dragging = nil
        return true
    }
}

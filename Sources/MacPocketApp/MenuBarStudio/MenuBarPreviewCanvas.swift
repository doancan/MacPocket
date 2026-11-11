import AppKit
import MacPocketCore
import SwiftUI

/// What the page's inspector shows: the layout-wide options, or one module's.
enum MenuBarPane: Hashable {
    case general
    case module(MenuBarModule)

    var module: MenuBarModule? {
        if case .module(let module) = self { module } else { nil }
    }
}

/// A live copy of the menu bar on a wallpaper. Items are drawn by the real renderer in the chosen appearance and
/// are buttons: clicking one opens its options. The light and dark renditions are independent of the window's.
struct MenuBarPreviewCanvas: View {
    let provider: MenuBarImageProvider
    @Binding var pane: MenuBarPane
    @AppStorage(MenuBarPreviewAppearance.storageKey) private var appearance = MenuBarPreviewAppearance.system
    @AppStorage("MacPocket.menubar.previewZoom") private var zoom = 1.5
    @Environment(\.colorScheme) private var systemScheme
    @State private var width: CGFloat = 640

    private static let zoomSteps: [Double] = [1, 1.5, 2]
    private var preferences: MenuBarPreferences { provider.preferences }
    private var surface: MenuBarSurface { MenuBarSurface(dark: appearance.isDark(system: systemScheme)) }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            controls
            canvas
        }
        .pocketCard()
    }

    // MARK: Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PocketSpacing.m) { title; Spacer(minLength: PocketSpacing.s); pickers }
            VStack(alignment: .leading, spacing: PocketSpacing.s) { title; pickers }
        }
    }

    private var title: some View {
        PocketSectionHeader("Önizleme", icon: "menubar.rectangle")
            .fixedSize()
    }

    private var pickers: some View {
        HStack(spacing: PocketSpacing.m) {
            Picker("Önizleme görünümü", selection: $appearance) {
                ForEach(MenuBarPreviewAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Önizlemeyi açık veya koyu menü çubuğunda göster")
            Picker("Yakınlaştırma", selection: $zoom) {
                ForEach(Self.zoomSteps, id: \.self) { step in Text(verbatim: step == 1.5 ? "1,5×" : "\(Int(step))×").tag(step) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Önizlemeyi büyüt")
        }
    }

    // MARK: Canvas

    private var items: [MenuBarModule] {
        guard preferences.visible else { return [] }
        if preferences.layout == .separate && !preferences.enabledModules.isEmpty { return preferences.enabledModules }
        return preferences.enabledModules.filter { !$0.isSystemMetric }
    }

    private var showsGroupedItem: Bool {
        preferences.visible && !(preferences.layout == .separate && !preferences.enabledModules.isEmpty)
    }

    /// Item images for the current preferences, rendered once per body evaluation.
    private var rendered: [(module: MenuBarModule?, image: NSImage)] {
        var result: [(MenuBarModule?, NSImage)] = []
        if showsGroupedItem { result.append((nil, surface.flatten(provider.grouped()))) }
        for module in items { result.append((module, surface.flatten(provider.image(module)))) }
        return result
    }

    /// Largest zoom at which every item fits next to the system icons and clock.
    private func effectiveZoom(for images: [(module: MenuBarModule?, image: NSImage)]) -> CGFloat {
        let natural = images.reduce(CGFloat(0)) { $0 + $1.image.size.width + 10 }
        let room = max(120, width - 150)
        return min(CGFloat(zoom), room / max(1, natural))
    }

    private var canvas: some View {
        let images = rendered
        let scale = effectiveZoom(for: images)
        let foreground = surface.foregroundColor
        let spare = width - 150 - images.reduce(CGFloat(0)) { $0 + ($1.image.size.width + 10) * scale }
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                .fill(LinearGradient(colors: surface.wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 0) {
                bar(images, scale: scale, foreground: foreground, showsMenus: spare > 260)
                if !preferences.visible {
                    hiddenNotice(foreground)
                } else if preferences.layout == .grouped {
                    tabStrip(foreground)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: preferences.visible && preferences.layout == .grouped ? 120 + 36 * CGFloat(zoom - 1) : 74 + 28 * CGFloat(zoom - 1))
        .clipShape(RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous).strokeBorder(PocketTheme.line) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.colorScheme, surface.dark ? .dark : .light)
        .animation(.snappy(duration: 0.22), value: preferences.order)
        .animation(.snappy(duration: 0.22), value: preferences.enabled)
    }

    private func bar(_ images: [(module: MenuBarModule?, image: NSImage)], scale: CGFloat, foreground: Color, showsMenus: Bool) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "applelogo").font(.system(size: 13 * scale, weight: .semibold)).padding(.horizontal, 8 * scale)
            if showsMenus {
                Text(verbatim: "MacPocket").font(.system(size: 12.5 * scale, weight: .bold))
                ForEach(["Dosya", "Görünüm"], id: \.self) { name in
                    Text(LocalizedStringKey(name)).font(.system(size: 12.5 * scale)).opacity(0.88).padding(.leading, 9 * scale)
                }
            }
            Spacer(minLength: 8)
            ForEach(Array(images.enumerated()), id: \.offset) { _, entry in
                CanvasItemButton(image: entry.image, scale: scale, foreground: foreground,
                                 selected: isSelected(entry.module), label: label(for: entry.module)) {
                    pane = entry.module.map { .module($0) } ?? .general
                }
            }
            Image(systemName: "switch.2").font(.system(size: 12 * scale, weight: .medium)).padding(.horizontal, 8 * scale)
                .accessibilityHidden(true)
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12.5 * scale, weight: .medium)).monospacedDigit()
            }
            .padding(.trailing, 10 * scale)
            .accessibilityHidden(true)
        }
        .foregroundStyle(foreground)
        .lineLimit(1)
        .frame(height: 28 * scale)
        .background(surface.barFill)
        .overlay(alignment: .bottom) { Rectangle().fill(foreground.opacity(0.10)).frame(height: 0.5) }
    }

    private func isSelected(_ module: MenuBarModule?) -> Bool {
        module.map { pane == .module($0) } ?? (pane == .general)
    }

    private func label(for module: MenuBarModule?) -> Text {
        module.map { Text($0.title) } ?? Text("Gruplu simge")
    }

    private func hiddenNotice(_ foreground: Color) -> some View {
        Label("Menü çubuğu öğesi gizli", systemImage: "eye.slash")
            .font(.callout.weight(.medium)).foregroundStyle(foreground.opacity(0.9))
            .padding(.top, PocketSpacing.l)
    }

    /// Grouped layout: the popover's tab strip hanging under the icon; its order is the module order.
    private func tabStrip(_ foreground: Color) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Açılır pencere sekmeleri").font(.caption.weight(.semibold)).foregroundStyle(foreground.opacity(0.85))
            HStack(spacing: 6) {
                if preferences.enabledModules.isEmpty {
                    Text("Aşağıdaki listeden bir modül aç").font(.caption).foregroundStyle(foreground.opacity(0.85))
                }
                ForEach(preferences.enabledModules) { module in
                    Button { pane = .module(module) } label: {
                        HStack(spacing: 5) {
                            PocketIconTile(symbol: module.symbol, tint: module.tint, size: 16)
                            Text(module.title).font(.caption).lineLimit(1)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(foreground.opacity(pane == .module(module) ? 0.2 : 0.08), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: pane == .module(module) ? 1.5 : 0) }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(foreground)
                    .accessibilityAddTraits(pane == .module(module) ? .isSelected : [])
                }
            }
            .padding(6)
            .background(surface.barFill, in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 10).padding(.trailing, 14)
    }
}

/// One menu bar item: hover and selection highlight like a real status item, and a real button for VoiceOver.
private struct CanvasItemButton: View {
    let image: NSImage
    let scale: CGFloat
    let foreground: Color
    let selected: Bool
    let label: Text
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: image)
                .resizable().interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .padding(.horizontal, 5 * scale)
                .background {
                    RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                        .fill(foreground.opacity(selected ? 0.22 : hovering ? 0.12 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

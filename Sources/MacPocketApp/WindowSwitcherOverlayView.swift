import AppKit
import MacPocketCore
import SwiftUI

/// The transient keyboard switcher, modelled on Windows 11 Alt+Tab: a row of large live thumbnails,
/// each with only its app icon and window title, and a selection frame that glides between items.
/// Configuration and the detail table live in Tools.
struct WindowSwitcherOverlayView: View {
    @ObservedObject var model: WindowSwitcherModel
    @ObservedObject var controller: WindowSwitcherHotkeyController
    let choose: (String) -> Void
    @PocketReduceMotion private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selectionSpace
    @State private var appeared = false

    private static let radius: CGFloat = 20

    var body: some View {
        let layout = controller.layout
        surface(layout)
            .frame(width: layout.panelSize.width, height: layout.panelSize.height)
            .onAppear { withAnimation(reduceMotion ? .linear(duration: 0.05) : .spring(response: 0.22, dampingFraction: 0.86)) { appeared = true } }
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88), value: model.filtered.map(\.id))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pencere geçişi")
    }

    /// The panel is a Liquid Glass HUD that materializes over the desktop; the selection frame,
    /// hover fills and search pill on it are plain fills (no glass on glass).
    @ViewBuilder private func surface(_ layout: SwitcherLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        GlassEffectContainer {
            if appeared {
                panel(layout)
                    .glassEffect(.regular, in: shape)
                    .glassEffectTransition(.materialize)
            }
        }
    }

    private func panel(_ layout: SwitcherLayout) -> some View {
        let windows = model.filtered
        let style = controller.style
        return VStack(spacing: PocketSpacing.s) {
            if windows.isEmpty {
                emptyState
            } else {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        grid(windows, layout: layout, style: style).padding(4)
                    }
                    .scrollIndicators(layout.rows > 1 ? .automatic : .never)
                    .onChange(of: model.selection) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { reader.scrollTo(id) }
                    }
                    .onAppear { if let id = model.selection { reader.scrollTo(id) } }
                }
            }
            statusLine
        }
        .padding(SwitcherLayout.padding)
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .overlay(alignment: .top) { searchPill.padding(.top, 8) }
    }

    /// Search appears only while typing, floating over the panel's top edge. It sits on the panel's
    /// surface, so it is an accent-tinted fill rather than a second layer of glass or material.
    @ViewBuilder private var searchPill: some View {
        if !model.sessionSearch.isEmpty {
            HStack(spacing: PocketSpacing.xs) {
                Image(systemName: "magnifyingglass")
                Text(model.sessionSearch).fontWeight(.semibold)
                    .contentTransition(.interpolate)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.16), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1) }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel("Arama: \(model.sessionSearch)")
        }
    }

    /// One quiet line, shown only when something limits the result (permissions).
    @ViewBuilder private var statusLine: some View {
        if !model.trusted {
            Label("Pencere başlıkları için Erişilebilirlik izni gerekli", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary).frame(height: 16)
        } else if !WindowPreviewProvider.permitted {
            Label("Canlı önizleme için Ekran Kaydı izni gerekli", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary).frame(height: 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: PocketSpacing.s) {
            Image(systemName: model.sessionSearch.isEmpty ? "macwindow" : "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text(model.busy ? "Pencereler okunuyor…" as LocalizedStringKey
                 : model.sessionSearch.isEmpty ? "Açık pencere yok" : "Eşleşen pencere yok")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(_ windows: [SwitchableWindow], layout: SwitcherLayout, style: SwitcherStyle) -> some View {
        let columns = Array(repeating: GridItem(.fixed(layout.itemSize.width), spacing: SwitcherLayout.spacing), count: layout.columns)
        return LazyVGrid(columns: columns, spacing: style == .titles ? 4 : SwitcherLayout.spacing) {
            ForEach(windows) { window in
                SwitcherItem(window: window, style: style, size: layout.itemSize,
                             selected: model.selection == window.id, thumbnail: model.thumbnails[window.id],
                             selectionSpace: selectionSpace, reduceMotion: reduceMotion,
                             choose: { choose(window.id) },
                             hover: { controller.hover(window.id) },
                             close: { controller.act(.close, on: window.id) })
                    .id(window.id)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: model.selection)
    }
}

private struct SwitcherItem: View {
    let window: SwitchableWindow
    let style: SwitcherStyle
    let size: CGSize
    let selected: Bool
    let thumbnail: NSImage?
    let selectionSpace: Namespace.ID
    let reduceMotion: Bool
    let choose: () -> Void
    let hover: () -> Void
    let close: () -> Void
    @State private var hovering = false

    private var radius: CGFloat { style == .titles ? 8 : 12 }

    var body: some View {
        Button(action: choose) {
            content
                .frame(width: size.width, height: size.height)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            ZStack {
                if hovering && !selected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.primary.opacity(0.06))
                }
                if selected {
                    // A single frame moves between items (matched geometry), like Windows' sliding highlight.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: style == .titles ? 2 : 2.5)
                        }
                        .matchedGeometryEffect(id: "selection", in: selectionSpace)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering && window.canClose && style != .titles {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Pencereyi kapat")
                .accessibilityLabel("Pencereyi kapat")
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovering = inside }
            if inside { hover() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.application), \(window.title)")
        .accessibilityValue(stateDescription)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Pencereyi kapat") { close() }
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .thumbnails: thumbnailCard
        case .icons: iconCard
        case .titles: titleRow
        }
    }

    /// Windows 11 layout: icon + title on one line above a large preview.
    private var thumbnailCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PocketAppIcon(url: window.applicationURL, size: 16)
                Text(window.isRealWindow ? window.title : window.application)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if let symbol = stateSymbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 22)
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().interpolation(.high).scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .opacity(window.minimized ? 0.6 : 1)
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.05))
                    PocketAppIcon(url: window.applicationURL, size: min(64, size.height * 0.38))
                        .opacity(window.minimized || window.hidden ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: thumbnail != nil)
        }
        .padding(8)
    }

    private var iconCard: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                PocketAppIcon(url: window.applicationURL, size: min(size.width * 0.58, 76))
                    .opacity(window.minimized || window.hidden ? 0.6 : 1)
                if let symbol = stateSymbol {
                    Image(systemName: symbol).font(.caption2.weight(.bold))
                        .padding(3).background(.regularMaterial, in: Circle())
                }
            }
            .frame(maxHeight: .infinity)
            Text(window.isRealWindow ? window.title : window.application).font(.caption)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(8)
    }

    private var titleRow: some View {
        HStack(spacing: PocketSpacing.s) {
            PocketAppIcon(url: window.applicationURL, size: 22)
            Text(window.isRealWindow ? window.title : window.application).font(.callout)
                .fontWeight(selected ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: PocketSpacing.s)
            Text(window.application).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let symbol = stateSymbol { Image(systemName: symbol).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, PocketSpacing.s)
    }

    /// At most one small glyph; the full meaning is in the VoiceOver value, not on screen.
    private var stateSymbol: String? {
        if window.minimized { return "minus.rectangle" }
        if window.hidden { return "eye.slash" }
        if window.otherSpace { return "rectangle.on.rectangle" }
        if window.fullScreen { return "arrow.up.left.and.arrow.down.right" }
        return nil
    }

    private var stateDescription: String {
        if window.minimized { return String(localized: "Küçültülmüş") }
        if window.hidden { return String(localized: "Gizli") }
        if window.otherSpace { return String(localized: "Diğer masaüstünde") }
        if window.fullScreen { return String(localized: "Tam ekran") }
        return window.isRealWindow ? "" : String(localized: "Penceresiz uygulama")
    }
}

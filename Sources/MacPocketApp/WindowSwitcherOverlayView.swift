import AppKit
import MacPocketCore
import SwiftUI

/// The transient keyboard switcher, modelled on Windows 11 Alt+Tab: a row of large live thumbnails,
/// each with only its app icon and window title, and a selection frame that glides between items.
/// Only that frame animates: card contents change without animation, so a Tab press interpolates one
/// shape's position instead of cross-fading the display lists of two cards.
/// Configuration and the detail table live in Tools.
struct WindowSwitcherOverlayView: View {
    var model: WindowSwitcherModel
    @ObservedObject var controller: WindowSwitcherHotkeyController
    let choose: (String) -> Void
    let thumbnailSessionID: UUID
    var reduceTransparencyOverride: Bool? = nil
    @PocketReduceMotion private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    private static let radius: CGFloat = 20

    var body: some View {
        let layout = controller.layout
        surface(layout)
            .frame(width: layout.panelSize.width, height: layout.panelSize.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pencere geçişi")
    }

    /// One glass surface; selection is a single moving frame rather than another glass layer.
    /// Reduced transparency uses an opaque native window color, including action buttons.
    @ViewBuilder private func surface(_ layout: SwitcherLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        if reduceTransparency {
            panel(layout).background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(.primary.opacity(0.18), lineWidth: 1) }
        } else {
            GlassEffectContainer {
                panel(layout).glassEffect(.regular, in: shape)
            }
        }
    }

    private func panel(_ layout: SwitcherLayout) -> some View {
        let windows = model.filtered
        let style = controller.style
        // Read here, not inside the lazy closures below: one selection change then updates the grid,
        // the selection frame and both cards in a single transaction.
        let selection = model.selection
        return VStack(spacing: PocketSpacing.s) {
            if windows.isEmpty {
                emptyState
            } else {
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        grid(windows, layout: layout, style: style, selection: selection).padding(4)
                    }
                    .scrollIndicators(layout.rows > 1 ? .automatic : .never)
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        reader.scrollTo(id)
                    }
                    .onAppear { if let selection { reader.scrollTo(selection) } }
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
        if model.isSearching {
            HStack(spacing: PocketSpacing.xs) {
                Image(systemName: "magnifyingglass")
                if model.sessionSearch.isEmpty { Text("Aramak için yaz").foregroundStyle(.secondary) }
                else { Text(model.sessionSearch).fontWeight(.semibold).contentTransition(.interpolate) }
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
        if let failure = model.failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(1).help(failure)
        } else if !model.trusted {
            Label("Pencere başlıkları için Erişilebilirlik izni gerekli", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary).frame(height: 16)
        } else if !WindowPreviewProvider.permitted {
            Label("Canlı önizleme için Ekran Kaydı izni gerekli", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary).frame(height: 16)
        } else {
            Text(controller.sessionHint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    private func grid(_ windows: [SwitchableWindow], layout: SwitcherLayout, style: SwitcherStyle, selection: String?) -> some View {
        let columns = Array(repeating: GridItem(.fixed(layout.itemSize.width), spacing: SwitcherLayout.spacing), count: layout.columns)
        return LazyVGrid(columns: columns, spacing: style == .titles ? 4 : SwitcherLayout.spacing) {
            ForEach(windows) { window in
                SwitcherItem(window: window, style: style, size: layout.itemSize,
                             badge: controller.presentation.showBadges ? model.applicationBadge(for: window) : nil,
                             selected: selection == window.id, thumbnail: model.thumbnailSlot(for: window.id),
                             actionBusy: model.actionBusy, presentation: controller.presentation,
                             reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                             choose: { choose(window.id) },
                             hover: { controller.hover(window.id) },
                             act: { controller.act($0, on: window.id) })
                    // Only cards whose inputs changed re-run: a Tab press redraws the old and new selection.
                    .equatable()
                    .id(window.id)
                    .onAppear { model.thumbnailVisibilityChanged(window.id, visible: true, sessionID: thumbnailSessionID) }
                    .onDisappear { model.thumbnailVisibilityChanged(window.id, visible: false, sessionID: thumbnailSessionID) }
            }
        }
        .backgroundPreferenceValue(SwitcherSelectionAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor]
                    SwitcherSelectionFrame(style: style)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            // Scoped to the frame: card contents (title weight, captions) switch instantly.
            .animation(selectionMotion, value: selection)
        }
    }

    private var selectionMotion: Animation? {
        let duration = SwitcherMotionPlan(presentation: controller.presentation, reduceMotion: reduceMotion).selection
        return duration > 0 ? .easeOut(duration: duration) : nil
    }
}

/// Bounds of the selected card, published by that card for the grid's single selection frame.
private struct SwitcherSelectionAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

private struct SwitcherSelectionFrame: View {
    let style: SwitcherStyle
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .titles ? 8 : 12, style: .continuous)
        shape.fill(Color.primary.opacity(0.10))
            .overlay { shape.strokeBorder(Color.accentColor, lineWidth: style == .titles ? 2 : 2.5) }
            .allowsHitTesting(false)
    }
}

private struct SwitcherItem: View, Equatable {
    let window: SwitchableWindow
    let style: SwitcherStyle
    let size: CGSize
    let badge: DockApplicationBadge?
    let selected: Bool
    /// Observed here, not in the grid, so a new capture redraws this card alone.
    let thumbnailSlot: SwitcherThumbnailSlot
    let actionBusy: Bool
    let presentation: SwitcherPresentation
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let choose: () -> Void
    let hover: () -> Void
    let act: (WindowAction) -> Void
    @State private var hovering = false

    init(window: SwitchableWindow, style: SwitcherStyle, size: CGSize, badge: DockApplicationBadge?, selected: Bool,
         thumbnail: SwitcherThumbnailSlot, actionBusy: Bool, presentation: SwitcherPresentation, reduceMotion: Bool,
         reduceTransparency: Bool, choose: @escaping () -> Void,
         hover: @escaping () -> Void, act: @escaping (WindowAction) -> Void) {
        self.window = window; self.style = style; self.size = size; self.badge = badge; self.selected = selected
        self.thumbnailSlot = thumbnail; self.actionBusy = actionBusy; self.presentation = presentation
        self.reduceMotion = reduceMotion; self.reduceTransparency = reduceTransparency
        self.choose = choose; self.hover = hover; self.act = act
    }

    /// The closures only forward this card's window id (part of `window`) to the long-lived controller.
    nonisolated static func == (lhs: SwitcherItem, rhs: SwitcherItem) -> Bool {
        lhs.window == rhs.window && lhs.style == rhs.style && lhs.size == rhs.size && lhs.badge == rhs.badge
            && lhs.selected == rhs.selected && lhs.thumbnailSlot === rhs.thumbnailSlot && lhs.actionBusy == rhs.actionBusy
            && lhs.presentation == rhs.presentation && lhs.reduceMotion == rhs.reduceMotion
            && lhs.reduceTransparency == rhs.reduceTransparency
    }

    private var thumbnail: NSImage? { thumbnailSlot.image }
    private var thumbnailUnavailable: Bool { thumbnailSlot.unavailable || !window.canCapturePreview }

    private var radius: CGFloat { style == .titles ? 8 : 12 }
    private var showsActions: Bool { presentation.showActions && hovering && (window.canClose || window.canMinimize || window.canFullScreen) }

    var body: some View {
        Button(action: choose) {
            content
                .frame(width: size.width, height: size.height)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            if hovering && !selected {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.primary.opacity(0.06))
            }
        }
        // The grid draws one selection frame behind the cards at these bounds.
        .anchorPreference(key: SwitcherSelectionAnchor.self, value: .bounds) { selected ? $0 : nil }
        .overlay(alignment: .topTrailing) { if style != .thumbnails { actionControls } }
        .onHover { inside in
            withAnimation(reduceMotion || !presentation.animateSelection ? nil : .easeOut(duration: 0.12)) { hovering = inside }
            if inside { hover() }
        }
        .help("\(window.application), \(window.title)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.application), \(window.title)")
        .accessibilityValue(stateDescription)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityActions {
            if window.canClose { Button("Pencereyi kapat") { act(.close) } }
            if window.canMinimize {
                Button(window.minimized ? "Pencereyi geri getir" : "Pencereyi küçült") { act(window.minimized ? .restore : .minimize) }
            }
            if window.canFullScreen {
                Button(window.fullScreen ? "Tam ekrandan çık" : "Tam ekrana geç") { act(.toggleFullScreen) }
            }
        }
    }

    @ViewBuilder private var actionControls: some View {
        if showsActions {
            HStack(spacing: 2) {
                if window.canFullScreen {
                    actionButton(window.fullScreen ? "Tam ekrandan çık" : "Tam ekrana geç",
                                 symbol: window.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 action: .toggleFullScreen)
                }
                if window.canMinimize {
                    actionButton(window.minimized ? "Pencereyi geri getir" : "Pencereyi küçült",
                                 symbol: window.minimized ? "plus" : "minus", action: window.minimized ? .restore : .minimize)
                }
                if window.canClose { actionButton("Pencereyi kapat", symbol: "xmark", action: .close) }
            }
            .disabled(actionBusy)
            .padding(3)
            .background {
                if reduceTransparency { RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)) }
                else { RoundedRectangle(cornerRadius: 8).fill(.regularMaterial) }
            }
            .padding(style == .titles ? 4 : style == .icons ? 1 : 6)
            .transition(.opacity)
        }
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: WindowAction) -> some View {
        Button { act(action) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(labels.primary).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .lineLimit(1).truncationMode(truncation)
                    if let secondary = labels.secondary { Text(secondary).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(truncation) }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                notificationBadge
                tabLabel
                if let symbol = stateSymbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().interpolation(.high).scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .opacity(window.minimized ? 0.6 : 1)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.05))
                    VStack(spacing: 6) {
                        PocketAppIcon(url: window.applicationURL, size: min(64, size.height * 0.38))
                            .opacity(window.minimized || window.hidden ? 0.55 : 1)
                        if selected && window.isRealWindow {
                            if window.minimized {
                                Text("Küçültülmüş").font(.caption2).foregroundStyle(.secondary)
                            } else if window.nativeTab?.selected == false {
                                Text("Henüz sekme görüntüsü yok").font(.caption2).foregroundStyle(.secondary)
                            } else if thumbnailUnavailable {
                                Text("Önizleme alınamadı").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { actionControls }
            .overlay(alignment: .bottomTrailing) { spaceBadge.padding(4) }
            .overlay(alignment: .bottomLeading) {
                if thumbnail != nil && (window.minimized || thumbnailUnavailable) {
                    Label("Son görüntü", systemImage: "clock").font(.caption2).foregroundStyle(.secondary)
                        .padding(4).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
        }
        .padding(8)
    }

    private var iconCard: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                PocketAppIcon(url: window.applicationURL, size: min(size.width * 0.58, 76, max(18, size.height - (labels.secondary == nil ? 44 : 62))))
                    .opacity(window.minimized || window.hidden ? 0.6 : 1)
                if let symbol = stateSymbol {
                    Image(systemName: symbol).font(.caption2.weight(.bold))
                        .padding(3).background(Color(nsColor: .windowBackgroundColor), in: Circle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if window.nativeTab != nil, !showsActions {
                    tabLabel
                        .padding(3).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .overlay(alignment: .topTrailing) { if !showsActions { notificationBadge } }
            .overlay(alignment: .bottomLeading) { if !showsActions { spaceBadge } }
            Text(labels.primary).font(.caption).fontWeight(selected ? .semibold : .regular)
                .lineLimit(1).truncationMode(truncation)
            if let secondary = labels.secondary { Text(secondary).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(truncation) }
        }
        .padding(8)
    }

    private var titleRow: some View {
        HStack(spacing: PocketSpacing.s) {
            PocketAppIcon(url: window.applicationURL, size: 22)
            Text(labels.primary).font(.callout).fontWeight(selected ? .semibold : .regular)
                .lineLimit(1).truncationMode(truncation).layoutPriority(1)
            Spacer(minLength: PocketSpacing.s)
            if let secondary = labels.secondary { Text(secondary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(truncation) }
            notificationBadge
            tabLabel
            spaceBadge
            if let symbol = stateSymbol { Image(systemName: symbol).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, PocketSpacing.s)
        .padding(.trailing, showsActions ? 88 : 0)
    }

    /// At most one small glyph; the full meaning is in the VoiceOver value, not on screen.
    private var labels: (primary: String, secondary: String?) { presentation.titleMode.labels(for: window, style: style) }
    private var truncation: Text.TruncationMode {
        switch presentation.truncation { case .head: .head; case .middle: .middle; case .tail: .tail }
    }
    @ViewBuilder private var tabLabel: some View {
        if let tab = window.nativeTab {
            Text(size.width < 220 && style != .titles ? String(localized: "\(tab.ordinal)/\(tab.count)") : tab.localizedDescription)
                .font(.caption2).foregroundStyle(.secondary).fixedSize()
                .help(tab.localizedDescription).accessibilityHidden(true)
        }
    }
    @ViewBuilder private var notificationBadge: some View {
        if let badge {
            Text(badge.displayText).font(.system(size: 10,weight: .semibold,design: .rounded))
                .foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.horizontal,5).padding(.vertical,2)
                .background(Color(red: 0.72,green: 0.10,blue: 0.14),in: Capsule())
                .help(badge.localizedDescription).accessibilityHidden(true)
        }
    }
    @ViewBuilder private var spaceBadge: some View {
        if presentation.showSpaces {
            Text(SwitcherSpaceBadge.text(window.spaceMembership)).font(.caption2.monospacedDigit())
                .lineLimit(1).padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .help(window.spaceMembership?.localizedDescription ?? String(localized: "Masaüstü bilgisi bilinmiyor"))
                .accessibilityHidden(true)
        }
    }
    private var stateSymbol: String? {
        guard presentation.showStatus else { return nil }
        if window.minimized { return "minus.rectangle" }
        if window.hidden { return "eye.slash" }
        if window.isOnAnotherSpace { return "rectangle.on.rectangle" }
        if window.fullScreen { return "arrow.up.left.and.arrow.down.right" }
        return nil
    }

    private var stateDescription: String {
        var parts: [String] = []
        if let badge { parts.append(badge.localizedDescription) }
        if window.minimized { parts.append(String(localized: "Küçültülmüş")) }
        if window.hidden { parts.append(String(localized: "Gizli")) }
        if window.isOnAnotherSpace { parts.append(String(localized: "Diğer masaüstünde")) }
        if let membership = window.spaceMembership { parts.append(membership.localizedDescription) }
        else if presentation.showSpaces { parts.append(String(localized: "Masaüstü bilgisi bilinmiyor")) }
        if let tab = window.nativeTab {
            parts.append(tab.localizedDescription)
            if !tab.selected { parts.append(String(localized: "Arka plan sekmesi")) }
        }
        if window.fullScreen { parts.append(String(localized: "Tam ekran")) }
        if !window.isRealWindow { parts.append(String(localized: "Penceresiz uygulama")) }
        if thumbnail != nil && (window.minimized || thumbnailUnavailable) { parts.append(String(localized: "Son görüntü")) }
        return parts.joined(separator: ", ")
    }
}

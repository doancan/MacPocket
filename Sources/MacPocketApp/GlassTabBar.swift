import AppKit
import SwiftUI

/// One tab of a `GlassTabBar`.
struct GlassTab<ID: Hashable>: Identifiable {
    let id: ID
    let title: Text
    var symbol: String?
    /// nil: the page's module color (`pocketTint`).
    var tint: Color?

    init(id: ID, title: LocalizedStringKey, symbol: String? = nil, tint: Color? = nil) {
        self.id = id; self.title = Text(title); self.symbol = symbol; self.tint = tint
    }

    /// Already-localized or user data text, shown verbatim.
    @_disfavoredOverload
    init<S: StringProtocol>(id: ID, title: S, symbol: String? = nil, tint: Color? = nil) {
        self.id = id; self.title = Text(title); self.symbol = symbol; self.tint = tint
    }
}

/// Segmented tab bar with a Liquid Glass selection lens.
///
/// - Click a tab, or press and drag: the lens lifts and grows, follows the pointer continuously, stretches
///   with the drag speed like a liquid drop, switches the selection (with a trackpad tick) as it crosses a
///   tab's midpoint, and on release springs onto the selected tab.
/// - The lens is an interactive `.glassEffect` inside a `GlassEffectContainer` with a
///   `glassEffectID`: tinted at rest, clear while held so the labels read through it as through a lens.
/// - Reduce Motion: no lens travel or scaling, the selection jumps. Reduce Transparency: solid fills.
/// - Each tab is a real button (keyboard focus, VoiceOver "selected" trait); arrow keys and ⌘1… are
///   handled by the owner through `GlassTabBar.keyboardShortcuts`.
struct GlassTabBar<ID: Hashable>: View {
    let tabs: [GlassTab<ID>]
    @Binding var selection: ID
    /// false: clear, untinted glass lens and monochrome labels, like the system segmented control.
    var tinted = true
    /// true when the owner installs `GlassTabKeyboardShortcuts`, so tooltips mention ⌘1…
    var showsShortcutHints = false
    /// false: symbols only (the title stays as tooltip and VoiceOver label), for narrow bars.
    var showsTitles = true

    @Namespace private var namespace
    @State private var trackWidth: CGFloat = 0
    /// Pointer x while pressing; nil when idle.
    @State private var dragX: CGFloat?
    /// 0…maxStretch, from the horizontal drag speed; widens and flattens the held lens.
    @State private var stretch: CGFloat = 0

    private static var maxStretch: CGFloat { 0.22 }
    /// Points per second of pointer speed that produce the full stretch.
    private static var fullStretchSpeed: CGFloat { 2400 }
    @PocketReduceMotion private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pocketTint) private var pageTint

    private let height: CGFloat = 34
    private let inset: CGFloat = 3

    private var selectedIndex: Int { tabs.firstIndex { $0.id == selection } ?? 0 }
    private var segmentWidth: CGFloat { tabs.isEmpty ? 0 : max(0, trackWidth - inset * 2) / CGFloat(tabs.count) }
    private var selectedTint: Color {
        guard tinted else { return .primary }
        return tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].tint ?? pageTint : pageTint
    }
    private var snapAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78) }

    /// Lens center: under the pointer while dragging (clamped to the track), else on the selected tab.
    private var lensCenter: CGFloat {
        let resting = inset + segmentWidth * (CGFloat(selectedIndex) + 0.5)
        guard let dragX, !reduceMotion else { return resting }
        return min(max(dragX, inset + segmentWidth / 2), trackWidth - inset - segmentWidth / 2)
    }

    var body: some View {
        content
            .frame(height: height)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { trackWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in trackWidth = width }
                }
            }
            .contentShape(Capsule())
            .highPriorityGesture(dragGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Modüller")
    }

    @ViewBuilder private var content: some View {
        if !reduceTransparency {
            // The popover is already glass, so the track is a quiet fill and only the
            // selection lens is (interactive, tinted) glass — no glass-on-glass.
            ZStack(alignment: .leading) {
                GlassEffectContainer {
                    lens
                        .glassEffect(lensGlass, in: .capsule)
                        .glassEffectID("selection", in: namespace)
                }
                .scaleEffect(x: lensScale.width, y: lensScale.height)
                .animation(snapAnimation, value: lifted)
                .offset(x: lensCenter - lensWidth / 2 - inset)
                labels
            }
            .padding(.horizontal, inset)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055), in: Capsule())
            .overlay { Capsule().strokeBorder(PocketTheme.line, lineWidth: 0.5) }
        } else {
            ZStack(alignment: .leading) {
                lens
                    .background(PocketTheme.panel, in: Capsule())
                    .overlay { Capsule().strokeBorder(tinted ? selectedTint.opacity(0.35) : PocketTheme.line, lineWidth: 0.75) }
                    .shadow(color: .black.opacity(dragX == nil ? 0.12 : 0.22), radius: dragX == nil ? 2 : 6, y: 1)
                    .scaleEffect(x: lensScale.width, y: lensScale.height)
                    .animation(snapAnimation, value: lifted)
                    .offset(x: lensCenter - lensWidth / 2 - inset)
                labels
            }
            .padding(.horizontal, inset)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .background(PocketTheme.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(PocketTheme.line) }
        }
    }

    private var lensGlass: Glass {
        if lifted { return .clear.interactive() }
        return tinted ? .regular.tint(selectedTint.opacity(colorScheme == .dark ? 0.32 : 0.2)).interactive() : .regular.interactive()
    }

    /// Held: grown, wider and flatter the faster it moves. At rest: its tab's exact size.
    private var lensScale: CGSize {
        guard lifted else { return CGSize(width: 1, height: 1) }
        return CGSize(width: 1.12 + stretch, height: 1.14 - stretch * 0.45)
    }

    private var lifted: Bool { dragX != nil && !reduceMotion }
    private var lensWidth: CGFloat { max(0, segmentWidth) }

    private var lens: some View {
        Color.clear
            .frame(width: lensWidth, height: height - inset * 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let isSelected = index == selectedIndex
                Button {
                    select(index)
                } label: {
                    HStack(spacing: 4) {
                        if let symbol = tab.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: showsTitles ? 11 : 13, weight: .semibold))
                                .foregroundStyle(isSelected ? (tinted ? tab.tint ?? pageTint : .primary) : .secondary)
                        }
                        if showsTitles || tab.symbol == nil {
                            tab.title
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(width: segmentWidth > 0 ? segmentWidth : nil, height: height - inset * 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityHint("Sekmeyi göster")
                .help(showsShortcutHints ? Text("\(tab.title) (⌘\(index + 1))") : tab.title)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard segmentWidth > 0 else { return }
                if reduceMotion {
                    dragX = value.location.x
                } else if dragX == nil {
                    // First contact: the lens glides to the finger, then tracks it 1:1.
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.8)) { dragX = value.location.x }
                } else {
                    var transaction = Transaction()
                    transaction.animation = .interactiveSpring(response: 0.16, dampingFraction: 0.86)
                    withTransaction(transaction) {
                        dragX = value.location.x
                        stretch = min(Self.maxStretch, abs(value.velocity.width) / Self.fullStretchSpeed * Self.maxStretch)
                    }
                }
                let index = index(at: value.location.x)
                if index != selectedIndex {
                    select(index, animated: false)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { value in
                let index = index(at: value.location.x)
                withAnimation(snapAnimation) {
                    selection = tabs[index].id
                    dragX = nil
                    stretch = 0
                }
            }
    }

    private func index(at x: CGFloat) -> Int {
        guard segmentWidth > 0, !tabs.isEmpty else { return selectedIndex }
        return min(tabs.count - 1, max(0, Int((x - inset) / segmentWidth)))
    }

    private func select(_ index: Int, animated: Bool = true) {
        guard tabs.indices.contains(index) else { return }
        if animated {
            withAnimation(snapAnimation) { selection = tabs[index].id }
        } else {
            selection = tabs[index].id
        }
    }
}

/// Invisible buttons that give a tab bar ←/→ and ⌘1…⌘9 shortcuts inside its window.
struct GlassTabKeyboardShortcuts<ID: Hashable>: View {
    let tabs: [GlassTab<ID>]
    @Binding var selection: ID
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        let index = tabs.firstIndex { $0.id == selection } ?? 0
        ZStack {
            Button("") { move(to: index - 1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { move(to: index + 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            ForEach(Array(tabs.prefix(9).enumerated()), id: \.element.id) { offset, _ in
                Button("") { move(to: offset) }
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func move(to index: Int) {
        guard tabs.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)) { selection = tabs[index].id }
    }
}

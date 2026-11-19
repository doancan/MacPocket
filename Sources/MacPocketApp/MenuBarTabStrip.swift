import MacPocketCore
import SwiftUI

/// The popover's tab strip: one chip per module with its symbol and name.
///
/// The strip adapts to the number of tabs instead of squeezing them: every chip shows its name while they fit,
/// then only the selected chip keeps its name, and past that the strip scrolls. The selection is a Liquid Glass
/// lens that flows from chip to chip; the popover itself is the glass surface, so the other chips are plain
/// labels with a hover fill (no glass on glass).
struct MenuBarTabStrip: View {
    let tabs: [GlassTab<MenuBarModule>]
    @Binding var selection: MenuBarModule

    @Namespace private var lens
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(titles: .all)
            strip(titles: .selected)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    strip(titles: .selected).padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, tab in
                    withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(tab, anchor: .center) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modüller")
    }

    private enum Titles { case all, selected }

    private func strip(titles: Titles) -> some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let selected = tab.id == selection
                    MenuBarTabChip(tab: tab, index: index, selected: selected, showsTitle: titles == .all || selected,
                                   lens: lens) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) { selection = tab.id }
                    }
                    .id(tab.id)
                }
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
    }
}

private struct MenuBarTabChip: View {
    let tab: GlassTab<MenuBarModule>
    let index: Int
    let selected: Bool
    let showsTitle: Bool
    let lens: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol = tab.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tab.tint ?? .accentColor)
                        .frame(width: 17, height: 17)
                }
                if showsTitle {
                    tab.title
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, showsTitle ? 10 : 8)
            .frame(height: 30)
            .background {
                if !selected && hovering {
                    Capsule().fill(Color.primary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(SelectionLens(active: selected, tint: tab.tint, lens: lens))
        .onHover { hovering = $0 }
        .help(Text("\(tab.title) (⌘\(index + 1))"))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The glass lens behind the selected chip; one glass ID, so the lens morphs to the next selection.
private struct SelectionLens: ViewModifier {
    let active: Bool
    let tint: Color?
    let lens: Namespace.ID
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if active {
            content
                .glassEffect(.regular.tint((tint ?? .accentColor).opacity(colorScheme == .dark ? 0.3 : 0.18)).interactive(), in: .capsule)
                .glassEffectID("selection", in: lens)
        } else {
            content
        }
    }
}

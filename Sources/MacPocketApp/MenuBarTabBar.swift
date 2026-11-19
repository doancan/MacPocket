import MacPocketCore
import SwiftUI

/// Horizontal tab bar of the grouped popover: compact capsules with a bold glyph and the tab's short name beside
/// it, centered as a group. The selected tab is an accent-filled capsule with a white glyph and name. When the
/// tabs no longer fit, the bar scrolls sideways (with faded edges) instead of shrinking them.
struct MenuBarTabBar: View {
    let tabs: [GlassTab<MenuBarModule>]
    @Binding var selection: MenuBarModule

    @Namespace private var highlight
    @PocketReduceMotion private var reduceMotion

    /// A click carries no momentum, so the highlight settles critically damped (no overshoot), at Apple's
    /// reposition response.
    static let highlightSpring = Animation.spring(response: 0.3, dampingFraction: 1)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row.frame(maxWidth: .infinity)
            ScrollViewReader { scroller in
                ScrollView(.horizontal) { row.padding(.horizontal, PocketSpacing.xs) }
                    .scrollIndicators(.never)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                               .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .onAppear { scroller.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, tab in
                        withAnimation(reduceMotion ? nil : Self.highlightSpring) { scroller.scrollTo(tab, anchor: .center) }
                    }
            }
        }
        .frame(height: MenuBarTabButton.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modüller")
    }

    private var row: some View {
        HStack(spacing: PocketSpacing.xs) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                MenuBarTabButton(tab: tab, index: index, selected: tab.id == selection, highlight: highlight) {
                    // Only the highlight moves; the content swaps at once, so nothing slides or resizes.
                    withAnimation(reduceMotion ? nil : Self.highlightSpring) { selection = tab.id }
                }
                .id(tab.id)
            }
        }
        .fixedSize()
    }
}

private struct MenuBarTabButton: View {
    let tab: GlassTab<MenuBarModule>
    let index: Int
    let selected: Bool
    let highlight: Namespace.ID
    let action: () -> Void

    @State private var hovering = false
    static let height: CGFloat = 30

    var body: some View {
        Button(action: action) {
            HStack(spacing: PocketSpacing.xs + 1) {
                Image(systemName: tab.symbol ?? "circle")
                    .font(.body.weight(.semibold))
                    .imageScale(.medium)
                tab.title
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, PocketSpacing.s + 2)
            .frame(height: Self.height)
            .background {
                if selected {
                    Capsule().fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                } else if hovering {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(MenuBarTabPressStyle())
        .onHover { hovering = $0 }
        .help(index < 9 ? Text("\(tab.title) (⌘\(index + 1))") : tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Feedback on press, not on release: the tab dims the moment the pointer goes down.
private struct MenuBarTabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

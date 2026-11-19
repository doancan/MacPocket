import MacPocketCore
import SwiftUI

/// Horizontal tab bar of the grouped popover, after the classic macOS preferences toolbar: each tab is a
/// monochrome glyph over its short name, legible on the glass in both appearances. The selected tab sits in an
/// accent-filled tile with a white glyph and name. Tabs share the width evenly; when there are more than fit,
/// the bar scrolls sideways instead of shrinking them.
struct MenuBarTabBar: View {
    let tabs: [GlassTab<MenuBarModule>]
    @Binding var selection: MenuBarModule

    @Namespace private var highlight
    @PocketReduceMotion private var reduceMotion

    /// Narrowest a tab may get before the bar scrolls instead.
    private static let minimumTabWidth: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let fits = CGFloat(tabs.count) * Self.minimumTabWidth <= proxy.size.width
            let tabWidth = fits ? proxy.size.width / CGFloat(max(1, tabs.count)) : Self.minimumTabWidth
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            MenuBarTabButton(tab: tab, index: index, selected: tab.id == selection, highlight: highlight) {
                                // Only the highlight moves; the content swaps at once, so nothing slides or resizes.
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { selection = tab.id }
                            }
                            .frame(width: tabWidth)
                            .id(tab.id)
                        }
                    }
                }
                .scrollDisabled(fits)
                .scrollIndicators(.never)
                .onAppear { scroller.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, tab in
                    guard !fits else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { scroller.scrollTo(tab, anchor: .center) }
                }
            }
        }
        .frame(height: MenuBarTabButton.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modüller")
    }
}

private struct MenuBarTabButton: View {
    let tab: GlassTab<MenuBarModule>
    let index: Int
    let selected: Bool
    let highlight: Namespace.ID
    let action: () -> Void

    @State private var hovering = false
    static let height: CGFloat = 48

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol ?? "circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                tab.title
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08))
                }
            }
            .padding(.horizontal, 2)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: Self.height)
        .onHover { hovering = $0 }
        .help(index < 9 ? Text("\(tab.title) (⌘\(index + 1))") : tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

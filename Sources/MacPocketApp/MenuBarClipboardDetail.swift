import MacPocketCore
import SwiftUI

/// Closes the menu bar popover. Equatable by identity, so putting it in the environment does not invalidate
/// every reader on each popover update the way a bare closure (never equal to itself) does.
struct MenuBarPopoverCloser: Equatable {
    private let id = UUID()
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void = {}) { self.action = action }

    @MainActor func callAsFunction() { action() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    /// Closes the menu bar popover the view is in; a no-op elsewhere.
    @Entry var closeMenuBarPopover = MenuBarPopoverCloser()
    /// The app that was in front when the popover opened: clicking in the popover activates MacPocket, so a
    /// paste must go back to this app.
    @Entry var menuBarPasteTarget: NSRunningApplication? = nil
}

/// Clipboard history in the menu bar popover: search, kind filter, and the recent items. Clicking an item (or
/// Return) closes the popover and pastes it into the app in front; the context menu copies, pins or removes.
struct ClipboardMenuDetail: View {
    var model: PocketModel
    @ObservedObject private var service = ClipboardService.shared
    @StateObject private var search = ClipboardSearchModel(service: .shared)
    @FocusState private var searchFocused: Bool
    @Environment(\.closeMenuBarPopover) private var close
    @Environment(\.menuBarPasteTarget) private var pasteTarget

    /// Rows shown at once; the list scrolls past this height.
    private static let listHeight: CGFloat = 330

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            if service.settings.enabled {
                searchField
                kindFilter
                list
                footer
            } else {
                disabledState
            }
        }
        .onAppear {
            search.start()
            searchFocused = true
        }
        .onDisappear { search.stop() }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Panoda ara", text: $search.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { search.move(by: 1); return .handled }
                .onKeyPress(.upArrow) { search.move(by: -1); return .handled }
                .onSubmit { if let item = search.selectedItem { paste(item) } }
            if !search.query.isEmpty {
                Button { search.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(MenuBarPlatter.fill, in: RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
    }

    private var kindFilter: some View {
        HStack(spacing: 4) {
            filterChip(nil, title: "Tümü", symbol: nil)
            ForEach([ClipboardContent.Kind.text, .link, .image, .files], id: \.self) { kind in
                filterChip(kind, title: LocalizedStringKey(kind.title), symbol: kind.symbol)
            }
        }
    }

    private func filterChip(_ kind: ClipboardContent.Kind?, title: LocalizedStringKey, symbol: String?) -> some View {
        let selected = search.kind == kind
        return Button { search.kind = kind } label: {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                Text(title).font(selected ? .subheadline.weight(.semibold) : .subheadline)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        let items = search.items
        let selectedID = search.selectedItem?.id
        if search.isSearching {
            PocketProgressRow(message: "Aranıyor…")
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if items.isEmpty {
            Text(search.query.isEmpty ? "Henüz kopyalanmış bir şey yok." : "Eşleşen öğe yok.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(MenuBarPlatter.fill, in: RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ClipboardMenuRow(item: item, service: service, selected: item.id == selectedID,
                                             paste: { paste(item) }, pastePlain: { paste(item, plain: true) }, copy: { copy(item) })
                                .id(item.id)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.automatic)
                .frame(height: min(Self.listHeight, CGFloat(items.count) * 46 + 8))
                .background(MenuBarPlatter.fill, in: RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(service.history.items.count) öğe").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let error = service.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1).help(error)
            }
            Spacer()
            Button("Tüm geçmiş") {
                close()
                model.navigation.open(.clipboard)
                model.openMainWindow?()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private var disabledState: some View {
        VStack(spacing: PocketSpacing.s) {
            Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.secondary)
            Text("Pano geçmişi kapalı").font(.headline)
            Text("Açıldığında kopyaladığın metin, bağlantı, görsel ve dosyalar burada listelenir.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Pano geçmişini aç") { service.settings.enabled = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PocketSpacing.m)
    }

    // MARK: Actions

    /// The popover closes first, so the paste keystroke reaches the app the user was working in.
    private func paste(_ item: ClipboardItem, plain: Bool = false) {
        close()
        service.paste(item, plain: plain, into: pasteTarget)
    }

    private func copy(_ item: ClipboardItem) {
        service.copy(item)
        close()
    }
}

/// A compact clipboard row for the 368-pt popover: preview, two lines of text, and actions on hover.
private struct ClipboardMenuRow: View {
    let item: ClipboardItem
    @ObservedObject var service: ClipboardService
    let selected: Bool
    let paste: () -> Void
    let pastePlain: () -> Void
    let copy: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: paste) {
            HStack(spacing: PocketSpacing.s + 2) {
                preview.frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(item.content.kind == .link ? .middle : .tail)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: PocketSpacing.xs)
                if item.pinned {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Sabitlenmiş")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.06) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Yapıştırmak için tıkla")
        .contextMenu {
            Button("Yapıştır", action: paste)
            Button("Düz metin olarak yapıştır", action: pastePlain)
            Button("Kopyala", action: copy)
            Divider()
            Button(item.pinned ? "Sabitlemeyi kaldır" : "Sabitle") { service.setPinned(!item.pinned, item) }
            Button("Sil", role: .destructive) { service.remove(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case let .image(reference):
            if let image = service.image(for: reference) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                kindIcon
            }
        case let .files(urls):
            PocketAppIcon(url: urls.first, size: 28)
        default:
            kindIcon
        }
    }

    private var kindIcon: some View {
        Image(systemName: item.content.kind.symbol)
            .font(.body)
            .foregroundStyle(item.content.kind.tint)
            .frame(width: 30, height: 30)
            .background(item.content.kind.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    private var subtitle: String {
        let date = item.copiedAt.formatted(.relative(presentation: .named).locale(pocketLocale))
        return [item.sourceName, date].compactMap { $0 }.joined(separator: " · ")
    }
}

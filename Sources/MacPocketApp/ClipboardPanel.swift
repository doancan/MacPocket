import AppKit
import MacPocketCore
import SwiftUI

/// A key panel that doesn't activate MacPocket, so the app in front keeps focus and receives the paste.
private final class ClipboardPanelWindow: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

@MainActor
final class ClipboardPanelController {
    private unowned let service: ClipboardService
    private var window: ClipboardPanelWindow?
    private var state: ClipboardSearchModel?
    private var keyMonitor: Any?

    static let size = NSSize(width: 580, height: 460)

    init(service: ClipboardService) { self.service = service }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        let state = ClipboardSearchModel(service: service)
        self.state = state
        window.contentView = NSHostingView(rootView: ClipboardPanelView(state: state, choose: { [weak self] item, plain in
            self?.choose(item, plain: plain)
        }))
        window.setFrame(frame(on: screenUnderPointer()), display: true)
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        state?.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window?.onResign = nil
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        window?.contentView = nil
        window?.onResign = { [weak self] in self?.close() }
        state = nil
    }

    private func choose(_ item: ClipboardItem, plain: Bool) {
        close()
        service.paste(item, plain: plain)
    }

    private func makeWindow() -> ClipboardPanelWindow {
        let window = ClipboardPanelWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                          styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.title = String(localized: "Pano Geçmişi")
        window.onResign = { [weak self] in self?.close() }
        return window
    }

    private func screenUnderPointer() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Horizontally centered, in the upper part of the screen, like Spotlight.
    private func frame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let origin = NSPoint(x: area.midX - Self.size.width / 2, y: area.minY + area.height * 0.62 - Self.size.height / 2)
        return NSRect(origin: origin, size: Self.size)
    }

    private func installKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed: Bool = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns true when the key was used by the panel.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let state else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case 53: close(); return true // esc
        case 125: state.move(by: 1); return true // ↓
        case 126: state.move(by: -1); return true // ↑
        case 36, 76: // ↩, enter
            guard let item = state.selectedItem else { return true }
            choose(item, plain: flags.contains(.option))
            return true
        default: break
        }
        guard flags == .command else { return false }
        if let digit = Self.digitKeys[event.keyCode] {
            let items = state.items
            if items.indices.contains(digit - 1) { choose(items[digit - 1], plain: false) }
            return true
        }
        switch event.keyCode {
        case 35: // ⌘P
            if let item = state.selectedItem { service.setPinned(!item.pinned, item) }
            return true
        case 51: // ⌘⌫
            if let item = state.selectedItem { service.remove(item) }
            return true
        default:
            return false
        }
    }

    private static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
}

// MARK: - Panel view

struct ClipboardPanelView: View {
    @ObservedObject var state: ClipboardSearchModel
    @ObservedObject private var service: ClipboardService
    let choose: (ClipboardItem, Bool) -> Void
    @FocusState private var searchFocused: Bool
    @PocketReduceMotion private var reduceMotion

    init(state: ClipboardSearchModel, choose: @escaping (ClipboardItem, Bool) -> Void) {
        self.state = state
        service = state.service
        self.choose = choose
    }

    private static let radius: CGFloat = 22

    var body: some View {
        let items = state.items
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            if state.isSearching {
                ProgressView("Aranıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                list(items)
            }
            Divider().opacity(0.5)
            hints
        }
        .frame(width: ClipboardPanelController.size.width, height: ClipboardPanelController.size.height)
        .modifier(ClipboardPanelSurface(radius: Self.radius))
        .onAppear { searchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pano geçmişi")
    }

    private var searchBar: some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: "doc.on.clipboard").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Pano geçmişinde ara", text: $state.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
            Picker(selection: $state.kind) {
                Text("Tümü").tag(ClipboardContent.Kind?.none)
                ForEach(ClipboardContent.Kind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(Optional(kind))
                }
            } label: {
                Text("Tür")
            }
            .labelsHidden()
            .fixedSize()
                .pocketMenuPicker()
        }
        .padding(.horizontal, PocketSpacing.l)
        .frame(height: 54)
    }

    private func list(_ items: [ClipboardItem]) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRow(item: item, service: service, shortcutNumber: index < 9 ? index + 1 : nil,
                                         selected: index == state.selectedIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { choose(item, false) }
                            .onTapGesture { state.selectedIndex = index }
                    }
                }
                .padding(PocketSpacing.s)
            }
            .onChange(of: state.selectedIndex) { _, index in
                guard items.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { reader.scrollTo(items[index].id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: PocketSpacing.s) {
            Image(systemName: state.query.isEmpty ? "clipboard" : "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text(state.query.isEmpty && service.history.items.isEmpty ? "Henüz kopyalanan bir şey yok" as LocalizedStringKey
                                                                         : "Eşleşen öğe yok")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hints: some View {
        Text("↩ yapıştır · ⌥↩ düz metin · ⌘1–9 hızlı seç · ⌘P sabitle · ⌘⌫ sil · esc kapat")
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
    }
}

/// A Liquid Glass HUD (functional layer over whatever is on screen); rows on it use fills.
private struct ClipboardPanelSurface: ViewModifier {
    let radius: CGFloat
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.glassEffect(.regular, in: shape)
    }
}

// MARK: - Row

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject var service: ClipboardService
    var shortcutNumber: Int?
    var selected = false

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            preview
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(item.content.kind == .text ? 2 : 1)
                    .truncationMode(item.content.kind == .link ? .middle : .tail)
                Text(subtitle).font(.caption).foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
            }
            Spacer(minLength: PocketSpacing.s)
            if service.canClean(item) {
                Image(systemName: "link.badge.plus").foregroundStyle(.orange)
                    .help("Bu bağlantıda izleme parametreleri var")
                    .accessibilityLabel("İzleme parametresi içeriyor")
            }
            if item.pinned {
                Image(systemName: "pin.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Sabitlenmiş")
            }
            if let shortcutNumber {
                Text(verbatim: "⌘\(shortcutNumber)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PocketSpacing.s)
        .padding(.vertical, PocketSpacing.xs + 2)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.2))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case let .image(reference):
            if let image = service.image(for: reference) {
                Image(nsImage: image).resizable().scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                kindIcon
            }
        case let .files(urls):
            PocketAppIcon(url: urls.first, size: 30)
        default:
            kindIcon
        }
    }

    private var kindIcon: some View {
        Image(systemName: item.content.kind.symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(item.content.kind.tint)
            .frame(width: 34, height: 34)
            .background(item.content.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var subtitle: String {
        let date = item.copiedAt.formatted(.relative(presentation: .named).locale(pocketLocale))
        return [item.content.kind.title, item.sourceName, date].compactMap { $0 }.joined(separator: " · ")
    }
}

extension ClipboardContent.Kind {
    var title: String {
        switch self {
        case .text: String(localized: "Metin")
        case .link: String(localized: "Bağlantı")
        case .image: String(localized: "Görsel")
        case .files: String(localized: "Dosya")
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "doc"
        }
    }

    var tint: Color {
        switch self {
        case .text: PocketTheme.brand
        case .link: Color(hex: 0x00A6C8)
        case .image: Color(hex: 0xE8458B)
        case .files: PocketTheme.disk
        }
    }
}

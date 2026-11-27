import AppKit
import MacPocketCore
import SwiftUI

private final class ShelfWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ShelfPanelController: NSWindowController, NSWindowDelegate {
    private unowned let service: ShelfService
    private let filePreview = ShelfFilePreview()
    var isVisible: Bool { window?.isVisible == true }

    init(service: ShelfService) { self.service = service; super.init(window: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show(focus: Bool) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        if window == nil {
            let panel = ShelfWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
                                    styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Dosya Rafı")
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.minSize = NSSize(width: 560, height: 380)
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentView = nil
            window = panel
        }
        guard let window else { return }
        if window.contentView == nil { window.contentView = NSHostingView(rootView: ShelfView(service: service).pocketAppearanceRoot()) }
        if !window.isVisible {
            let area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let point = NSEvent.mouseLocation
            let size = NSSize(width: min(window.frame.width, area.width), height: min(window.frame.height, area.height))
            window.setFrame(NSRect(x: max(area.minX, min(point.x - size.width / 2, area.maxX - size.width)),
                                   y: max(area.minY, min(point.y - size.height / 2, area.maxY - size.height)),
                                   width: size.width, height: size.height), display: true)
        }
        if focus { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
    }

    override func close() {
        filePreview.close()
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        window?.contentView = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }

    func preview(_ urls: [URL]) { filePreview.show(urls, near: window) }
    #if DEBUG
    var diagnosticWindow: NSWindow? { window }
    var diagnosticPreviewOwned: Bool { filePreview.isVisible }
    var diagnosticPreviewWindow: NSWindow? { filePreview.diagnosticWindow }
    var diagnosticPreviewURL: URL? { filePreview.diagnosticURL }
    #endif
}

struct ShelfView: View {
    @ObservedObject var service: ShelfService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Dosya Rafı", systemImage: "tray.2").font(.headline)
                Spacer()
                Text("\(service.shelf.items.count) / 100").monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("\(service.shelf.items.count) raf öğesi")
                Button { service.chooseFiles() } label: { Label("Dosya Ekle…", systemImage: "plus") }
                    .disabled(!service.acceptsItems)
                Button("Yapıştır") { service.accept(.general) }.disabled(!service.acceptsItems)
            }
            .padding(PocketSpacing.m)
            Divider()
            ZStack {
                ShelfNativeTable(service: service)
                if service.loading {
                    ProgressView("Raf yükleniyor…")
                } else if service.rows.isEmpty {
                    VStack(spacing: PocketSpacing.s) {
                        Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Dosyaları buraya bırak").font(.headline)
                        Text("Metin, bağlantı ve görseller de ekleyebilirsin.")
                            .foregroundStyle(.secondary)
                        Text("Öğeleri seçip başka uygulamaya sürükle veya kopyala.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding().allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: PocketSpacing.m) {
                Button { service.previewSelection() } label: { Label("Önizle", systemImage: "eye") }
                    .disabled(!service.canUseSelection || !service.selectedRows.contains { $0.url?.isFileURL == true })
                Button { service.togglePins() } label: { Label("Sabitle / Çöz", systemImage: "pin") }
                    .disabled(service.selection.isEmpty)
                ShelfShareButton(service: service).frame(width: 70, height: 24)
                    .disabled(!service.canUseSelection)
                Spacer(minLength: 0)
                Menu {
                    Button("Kopyala") { service.copySelection() }.disabled(!service.canUseSelection)
                    Button("Finder’da Göster") { service.revealSelection() }
                        .disabled(!service.selectedRows.contains { $0.url?.isFileURL == true })
                    Button("Dosya Durumunu Yenile") { service.refreshRows() }
                    Divider()
                    Button("Seçilenleri Raftan Kaldır") { service.removeSelection() }.disabled(service.selection.isEmpty)
                    Button("Sabitlenmeyenleri Temizle") { service.clearUnpinned() }
                        .disabled(!service.shelf.items.contains { !$0.pinned })
                } label: { Label("İşlemler", systemImage: "ellipsis.circle") }
                .fixedSize()
            }
            .padding(PocketSpacing.m)
            if service.preparing > 0 {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Dosyalar hazırlanıyor…")
                    Spacer()
                    Button("İptal Et") { service.cancelPreparation() }
                }
                .padding(.horizontal, PocketSpacing.m).padding(.bottom, PocketSpacing.s)
            }
            if let message = service.message {
                HStack(alignment: .top) {
                    Text(message).font(.callout).textSelection(.enabled)
                    if service.canRetryLoad { Button("Tekrar Yükle") { service.retryLoad() } }
                }
                .padding(.horizontal, PocketSpacing.m).padding(.bottom, PocketSpacing.s)
            }
            Text("Raf bu Mac’te saklanır. Raftan kaldırmak kaynak dosyayı silmez.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, PocketSpacing.m).padding(.bottom, PocketSpacing.m)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ShelfNativeTable: NSViewRepresentable {
    @ObservedObject var service: ShelfService
    func makeCoordinator() -> Coordinator { Coordinator(service: service) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = ShelfTable()
        table.service = service
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.headerView = nil
        table.rowHeight = 54
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .fullWidth
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.minWidth = 100
        table.addTableColumn(column)
        table.setAccessibilityLabel(String(localized: "Raf öğeleri"))
        table.setAccessibilityIdentifier("shelf.items")
        table.registerForDraggedTypes(ShelfService.readableTypes)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        let menu = NSMenu()
        for (title, action) in [(String(localized: "Kopyala"), #selector(Coordinator.copyItems)),
                                (String(localized: "Önizle"), #selector(Coordinator.preview)),
                                (String(localized: "Finder’da Göster"), #selector(Coordinator.reveal)),
                                (String(localized: "Sabitle / Çöz"), #selector(Coordinator.pin)),
                                (String(localized: "Seçilenleri Raftan Kaldır"), #selector(Coordinator.remove))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = context.coordinator
        }
        table.menu = menu
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.updating = true
        table.usesAlternatingRowBackgroundColors = !service.rows.isEmpty
        if coordinator.rows != service.rows { coordinator.rows = service.rows; table.reloadData() }
        let selection = IndexSet(service.rows.indices.filter { service.selection.contains(service.rows[$0].id) })
        if table.selectedRowIndexes != selection { table.selectRowIndexes(selection, byExtendingSelection: false) }
        coordinator.updating = false
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let service: ShelfService
        var rows: [ShelfRow] = []
        var updating = false
        weak var table: NSTableView?
        init(service: ShelfService) { self.service = service }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            let item = rows[row]
            let cell = NSTableCellView()
            let icon = NSImageView(image: NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = item.unavailable ? .systemOrange : .secondaryLabelColor
            let title = NSTextField(labelWithString: item.title)
            title.font = .preferredFont(forTextStyle: .body)
            title.lineBreakMode = item.symbol == "text.alignleft" ? .byTruncatingTail : .byTruncatingMiddle
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let detail = NSTextField(labelWithString: item.detail)
            detail.font = .preferredFont(forTextStyle: .caption1)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingMiddle
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let labels = NSStackView(views: [title, detail])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 2
            let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: String(localized: "Sabitlenmiş")) ?? NSImage())
            pin.isHidden = !item.pinned
            for view in [icon, labels, pin] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
                labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), labels.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                labels.trailingAnchor.constraint(equalTo: pin.leadingAnchor, constant: -8),
                title.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
                detail.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
                pin.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14), pin.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                pin.widthAnchor.constraint(equalToConstant: 16), pin.heightAnchor.constraint(equalToConstant: 16),
            ])
            cell.textField = title
            cell.toolTip = item.title + "\n" + item.detail
            cell.setAccessibilityLabel(item.title + (item.pinned ? ", " + String(localized: "Sabitlenmiş") : "") + ", " + item.detail)
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            service.selection = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            rows.indices.contains(row) ? service.writer(for: rows[row].id) : nil
        }
        func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard info.draggingSource as? NSTableView !== tableView, service.canAccept(info.draggingPasteboard),
                  info.draggingSourceOperationMask.contains(.copy) else { return [] }
            tableView.setDropRow(-1, dropOperation: .on)
            return .copy
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool { service.accept(info.draggingPasteboard, promises: true) }
        @objc func copyItems() { service.copySelection() }
        @objc func preview() { service.previewSelection() }
        @objc func reveal() { service.revealSelection() }
        @objc func pin() { service.togglePins() }
        @objc func remove() { service.removeSelection() }
    }
}

private final class ShelfTable: NSTableView {
    weak var service: ShelfService?
    override func keyDown(with event: NSEvent) {
        guard let service else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if flags == .command {
            switch event.keyCode {
            case 8: service.copySelection()
            return
            case 9: service.accept(.general)
            return
            default: break
            }
        }
        if flags.isEmpty {
            switch event.keyCode {
            case 49, 36: service.previewSelection()
            return
            case 51, 117: service.removeSelection()
            return
            case 53: service.close()
            return
            default: break
            }
        }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return super.menu(for: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isKeyWindow == true else { return }
            self.window?.initialFirstResponder = self
            self.window?.makeFirstResponder(self)
        }
    }
}

private struct ShelfShareButton: NSViewRepresentable {
    @ObservedObject var service: ShelfService
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        NSButton(title: String(localized: "Paylaş"), target: context.coordinator, action: #selector(Coordinator.share(_:)))
    }
    func updateNSView(_ view: NSButton, context: Context) {
        context.coordinator.service = service
        view.isEnabled = service.canUseSelection && context.environment.isEnabled
    }
    @MainActor final class Coordinator: NSObject {
        weak var service: ShelfService?
        var picker: NSSharingServicePicker?
        @objc func share(_ sender: NSButton) {
            guard let service else { return }
            service.refreshRows()
            guard service.canUseSelection else { return }
            let items = service.shareItems
            guard items.count == service.selection.count else { return }
            let picker = NSSharingServicePicker(items: items)
            self.picker = picker
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

struct ShelfSettingsView: View {
    @ObservedObject private var service = ShelfService.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Dosya Rafı", subtitle: "Dosya, metin ve bağlantıları topla; başka uygulamalara birlikte taşı.", icon: "tray.2") {
                    Button("Dosya Rafı’nı Aç") { service.show() }.buttonStyle(.borderedProminent)
                }
                Form {
                    Section("Erişim") {
                        HStack {
                            Text("Klavye kısayolu")
                            Spacer()
                            KeyComboRecorder(combo: $service.shortcut, allowsClearing: true, recording: { service.recordingShortcut = $0 })
                        }
                        if service.shortcut != nil, !service.shortcutRegistered {
                            Text("Kısayol kaydedilemedi. Başka bir tuş birleşimi seç.").foregroundStyle(.orange)
                        }
                        Toggle("Sürüklerken fareyi sallayınca rafı aç", isOn: $service.shakeToOpen)
                    }
                    Section("Kullanım") {
                        Text("Dosyaları, metinleri ve bağlantıları rafa bırak. Birden çok öğe seçip dışarı sürükle veya ⌘C ile kopyala.")
                        Text("Boşluk ile dosyayı önizle; Delete ile yalnız raf kaydını kaldır. Sabitlenmiş öğeler toplu temizlemede korunur.")
                        Text("Raf bu Mac’te saklanır. Raftan kaldırmak kaynak dosyayı silmez.")
                        Text("Raf en fazla 100 öğe tutar. Modülü kapatmak kayıtlı öğeleri silmez.")
                    }
                }
                .pocketFormPage()
                // Sits on the page backdrop like the rest of the window, not on an opaque sheet.
                .scrollContentBackground(.hidden)
            }
            .padding(PocketSpacing.page)
        }
    }
}

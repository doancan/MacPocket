import AppKit
import MacPocketCore
import SwiftUI

private final class CommandBarWindow: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onResign?() }
}

@MainActor
final class CommandBarPanelController {
    private unowned let service: CommandBarService
    private var window: CommandBarWindow?
    private var keyMonitor: Any?
    var isVisible: Bool { window?.isVisible == true }
    #if DEBUG
    private(set) var diagnosticResign: [String: Bool]?
    #endif

    init(service: CommandBarService) { self.service = service }

    func show() {
        #if DEBUG
        diagnosticResign = nil
        #endif
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let window = self.window ?? makeWindow()
        self.window = window
        window.contentView = NSHostingView(rootView: CommandBarView(service: service).pocketAppearanceRoot())
        let area = screen.visibleFrame
        let size = NSSize(width: min(700, area.width - 32), height: min(520, area.height - 32))
        window.setFrame(NSRect(x: area.midX - size.width / 2, y: min(area.maxY - size.height - 16, area.midY - size.height * 0.25),
                               width: size.width, height: size.height), display: true)
        window.makeKeyAndOrderFront(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        // Input methods keep ownership of Return and arrows while composing marked text.
        if let editor = window?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        if event.keyCode == 53 { service.close(); return true }
        let responder = window?.firstResponder
        guard responder is NSTextView || responder is NSTextField || responder === window else { return false }

        switch event.keyCode {
        case 53: service.close(); return true
        case 125: service.move(by: 1); return true
        case 126: service.move(by: -1); return true
        case 36, 76: service.executeSelected(); return true
        default: return false
        }
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window?.onResign = nil
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        window?.contentView = nil
        window?.onResign = { [weak self] in self?.resigned() }
    }

    private func resigned() {
        #if DEBUG
        diagnosticResign = ["appActive": NSApp.isActive, "windowVisible": window?.isVisible == true]
        #endif
        service.close()
    }

    private func makeWindow() -> CommandBarWindow {
        let window = CommandBarWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.title = String(localized: "Komut Çubuğu")
        window.onResign = { [weak self] in self?.resigned() }
        return window
    }

    #if DEBUG
    var diagnosticWindow: NSWindow? { window }
    var diagnosticResources: [String: Int] { ["keyMonitor": keyMonitor == nil ? 0 : 1, "visiblePanel": isVisible ? 1 : 0] }
    #endif
}

struct CommandBarView: View {
    @ObservedObject var service: CommandBarService
    @State private var focusRequest = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PocketSpacing.m) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                CommandSearchInput(text: $service.query, focusRequest: focusRequest)
                    .frame(height: 28)
                if service.loading { ProgressView().controlSize(.small).accessibilityLabel("Sonuçlar yükleniyor") }
                Button { service.close() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Komut Çubuğu’nu kapat")
            }
            .padding(PocketSpacing.l)
            Divider()
            HStack {
                Text("Komut Çubuğu").font(.headline)
                Spacer()
                Picker("Sonuç türü", selection: $service.kind) {
                    Text("Tümü").tag(CommandSearchEntry.Kind?.none)
                    ForEach(CommandSearchEntry.Kind.allCases, id: \.self) { kind in Text(kind.localizedTitle).tag(Optional(kind)) }
                }
                .labelsHidden().frame(maxWidth: 170)
                .accessibilityLabel("Sonuç türü")
            }
            .padding(.horizontal, PocketSpacing.l).padding(.vertical, PocketSpacing.s)
            if let message = service.message {
                Text(verbatim: message).font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, PocketSpacing.l).textSelection(.enabled)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(service.results) { row in
                            resultRow(row).id(row.id)
                        }
                        if service.results.isEmpty, !service.loading {
                            ContentUnavailableView {
                                Label("Sonuç bulunamadı", systemImage: "magnifyingglass")
                            } description: {
                                Text("Başka bir sözcük dene veya sonuç türünü Tümü yap.")
                            } actions: {
                                Button("Aramayı Temizle") { service.query = ""; service.kind = nil; focusRequest += 1 }
                            }
                            .padding(.top, PocketSpacing.l)
                        }
                    }
                    .padding(.horizontal, PocketSpacing.s).padding(.bottom, PocketSpacing.s)
                }
                .onChange(of: service.selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
            Divider()
            HStack {
                Text("↑↓ gezin · ↩ çalıştır · esc kapat")
                Spacer()
                Text("\(service.results.count) sonuç")
            }
            .font(.caption).foregroundStyle(.secondary).padding(PocketSpacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PocketRadius.large))
        .clipShape(RoundedRectangle(cornerRadius: PocketRadius.large))
    }

    private func resultRow(_ row: CommandBarService.Entry) -> some View {
        HStack(spacing: 0) {
            Button { service.execute(row) } label: {
                HStack(spacing: PocketSpacing.m) {
                    Image(systemName: row.symbol).font(.title3).frame(width: 28).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: row.search.title).font(.body).lineLimit(1)
                        Text(verbatim: row.search.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: PocketSpacing.s)
                    Text(row.search.kind.localizedTitle).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, PocketSpacing.s).padding(.horizontal, PocketSpacing.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: row.search.title))
            .accessibilityHint(Text(verbatim: row.search.subtitle))
            .accessibilityAddTraits(service.selectedID == row.id ? .isSelected : [])
            .help(row.search.title + "\n" + row.search.subtitle)
            if row.canRemember {
                Button { service.togglePin(row) } label: {
                    Image(systemName: service.pinned.contains(row.id) ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless).padding(.trailing, PocketSpacing.m)
                .accessibilityLabel(service.pinned.contains(row.id) ? Text("“\(row.search.title)” sabitlemesini kaldır") : Text("“\(row.search.title)” komutunu sabitle"))
            }
        }
        .background(service.selectedID == row.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: PocketRadius.small))
    }
}

extension CommandSearchEntry.Kind {
    var localizedTitle: String {
        switch self {
        case .tool: String(localized: "Araçlar")
        case .action: String(localized: "İşlemler")
        case .application: String(localized: "Uygulamalar")
        case .window: String(localized: "Pencereler")
        case .clipboard: String(localized: "Pano")
        case .snippet: String(localized: "Metin Kısaltmaları")
        }
    }
}

struct CommandBarSettingsView: View {
    @ObservedObject private var service = CommandBarService.shared
    @AppStorage("MacPocket.commandBar.applications") private var applications = true
    @AppStorage("MacPocket.commandBar.windows") private var windows = true
    @AppStorage("MacPocket.commandBar.clipboard") private var clipboard = true
    @AppStorage("MacPocket.commandBar.snippets") private var snippets = true

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Komut Çubuğu", subtitle: "Araçlarını, uygulamalarını ve pencerelerini tek aramadan aç; pano ve metin kısaltmalarını kullan.", icon: "command") {
                Button("Komut Çubuğu’nu Aç") { service.show() }
            }
            Form {
                Section {
                    LabeledContent("Global kısayol") {
                        KeyComboRecorder(combo: $service.shortcut, allowsClearing: true, recording: { service.recordingShortcut = $0 })
                    }
                    if service.shortcut != nil, !service.shortcutRegistered {
                        Text("Kısayol kaydedilemedi. Başka bir uygulama kullanıyor olabilir; farklı bir kısayol seç.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Parlaklık 40 veya uyanık tut 30 dk yazarak doğrudan komut çalıştırabilirsin. Parlaklık, imlecin bulunduğu harici ekrana uygulanır.")
                        .foregroundStyle(.secondary)
                } header: { Text("Kısayol ve kullanım") }
                Section {
                    Toggle("Uygulamaları ara", isOn: $applications)
                    Toggle("Açık pencereleri ara", isOn: $windows)
                    Toggle("Pano geçmişini ara", isOn: $clipboard)
                    Toggle("Metin kısaltmalarını ara", isOn: $snippets)
                    Text("Pano ve metin kısaltmaları yalnız ilgili modül açıksa görünür. Arama içeriği kaydedilmez; son kullanılan komutların kimlikleri ve sabitlenenler bu Mac’te tutulur.")
                        .foregroundStyle(.secondary)
                    Button("Son Kullanılanları Temizle") { service.clearRecent() }
                } header: { Text("Arama kaynakları") }
            }
            .formStyle(.grouped)
        }
        .pocketPage()
    }
}

private struct CommandSearchInput: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, focusRequest: focusRequest) }

    func makeNSView(context: Context) -> SearchField {
        let field = SearchField()
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.font = NSFont.preferredFont(forTextStyle: .title3)
        field.placeholderString = String(localized: "Araç, uygulama, pencere veya pano öğesi ara…")
        field.setAccessibilityLabel(String(localized: "Komut ara"))
        field.setAccessibilityIdentifier("command.search")
        return field
    }

    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            field.stringValue = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.requestFocus()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var focusRequest: Int
        init(text: Binding<String>, focusRequest: Int) { self.text = text; self.focusRequest = focusRequest }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            text.wrappedValue = field.stringValue
        }
    }

    final class SearchField: NSTextField {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); requestFocus() }
        func requestFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                window.initialFirstResponder = self
                window.makeFirstResponder(self)
            }
        }
    }
}

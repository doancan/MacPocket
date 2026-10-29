import AppKit
import Combine
import MacPocketCore
import SwiftUI

@MainActor
final class WindowSwitcherModel: ObservableObject {
    @Published var windows: [SwitchableWindow] = []
    @Published var trusted = false
    @Published var partial = false
    @Published var busy = false
    @Published var failure: String?
    @Published var selection: String?
    @Published var search = ""
    @Published var preview: NSImage?
    @Published var previewBusy = false
    @Published var previewMessage: String?
    var foregroundPID: Int32?
    private let catalog = WindowCatalog()
    private let previews = WindowPreviewProvider()
    private var activationObserver: AnyCancellable?
    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in await self?.catalog.noteApplicationActivation(pid) }
            }
    }
    var filtered: [SwitchableWindow] {
        let defaults = UserDefaults.standard
        let excludes = Set((defaults.string(forKey: "switcher.excludedPaths") ?? "").split(separator: "\n").map(String.init))
        return WindowFiltering.apply(windows, search: search,
            includeMinimized: defaults.object(forKey: "switcher.includeMinimized") as? Bool ?? true,
            includeHidden: defaults.object(forKey: "switcher.includeHidden") as? Bool ?? true,
            includeWindowless: defaults.object(forKey: "switcher.includeWindowless") as? Bool ?? true,
            currentApplication: defaults.bool(forKey: "switcher.currentApplication") ? foregroundPID : nil,
            excludedBundlePaths: excludes,
            order: WindowSortOrder(rawValue: defaults.string(forKey: "switcher.sort") ?? "recent") ?? .recent)
    }
    var selected: SwitchableWindow? { filtered.first { $0.id == selection } }
    func refresh() async {
        guard !busy else { return }; busy = true
        if foregroundPID == nil { foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let old = selection, report = await catalog.snapshot()
        windows = report.windows; trusted = report.accessibilityGranted; partial = report.partial
        if foregroundPID == ProcessInfo.processInfo.processIdentifier || foregroundPID == nil {
            foregroundPID = windows.first?.processID
        }
        selection = filtered.contains { $0.id == old } ? old : filtered.first?.id; busy = false
    }
    func focus() async {
        guard let selected else { return }
        do { try await catalog.focus(selected.id); failure = nil }
        catch { failure = error.localizedDescription }
    }
    func action(_ action: WindowAction, id: String? = nil) async {
        guard !busy, let target = id ?? selected?.id else { return }
        do { try await catalog.perform(action, on: target); failure = nil; await refresh() }
        catch { failure = error.localizedDescription }
    }
    func cycle(backwards: Bool) {
        let rows = filtered; guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? (backwards ? 0 : -1)
        selection = rows[(current + (backwards ? -1 : 1) + rows.count) % rows.count].id
    }
    func capturePreview() async {
        guard !previewBusy, let selected, selected.windowAccessible else { return }
        previewBusy = true; preview = nil; previewMessage = nil
        let id = selected.id
        defer { previewBusy = false }
        do {
            let data = try await previews.preview(selected)
            guard selection == id else { return }
            preview = NSImage(data: data)
        } catch { if selection == id { previewMessage = error.localizedDescription } }
    }
    func excludeSelected() {
        guard let path = selected?.applicationURL?.path else { return }
        var paths = Set((UserDefaults.standard.string(forKey: "switcher.excludedPaths") ?? "").split(separator: "\n").map(String.init))
        paths.insert(path)
        UserDefaults.standard.set(paths.sorted().joined(separator: "\n"), forKey: "switcher.excludedPaths")
        selection = nil; objectWillChange.send()
    }
}

struct WindowSwitcherView: View {
    @StateObject private var model: WindowSwitcherModel
    @ObservedObject private var hotkey = WindowSwitcherHotkeyController.shared
    private let overlay: Bool
    private let onActivated: () -> Void
    @AppStorage("switcher.globalEnabled") private var globalEnabled = false
    @AppStorage("switcher.shortcut") private var shortcut = "controlOptionSpace"
    @AppStorage("switcher.releaseToChoose") private var releaseToChoose = true
    @AppStorage("switcher.includeMinimized") private var includeMinimized = true
    @AppStorage("switcher.includeHidden") private var includeHidden = true
    @AppStorage("switcher.includeWindowless") private var includeWindowless = true
    @AppStorage("switcher.currentApplication") private var currentApplication = false
    @AppStorage("switcher.sort") private var sort = "recent"
    @AppStorage("switcher.excludedPaths") private var excludedPaths = ""
    @AppStorage("switcher.showPreview") private var showPreview = true
    @State private var showOptions = false
    @State private var confirmClose = false
    @State private var pendingClose: SwitchableWindow?
    @FocusState private var searchFocused: Bool

    init(model: WindowSwitcherModel? = nil, overlay: Bool = false, onActivated: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: model ?? WindowSwitcherModel())
        self.overlay = overlay; self.onActivated = onActivated
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PocketPageHeading(title: "Pencere Geçişi", subtitle: overlay ? "Oklar / Tab: gezin · Enter: seç · Escape: vazgeç" : "Pencereler, klavye geçişi ve görünüm seçenekleri.", icon: "macwindow.on.rectangle")
                if !overlay { Button("Kısayol Penceresini Aç") { hotkey.show() } }
                Button("Seçenekler") { showOptions.toggle() }
            }
            if !model.trusted {
                HStack {
                    Text("Pencere başlıkları ve pencere işlemleri için Erişilebilirlik izni gerekir. Şimdilik uygulamalar listelenir.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Erişim İste…") { WindowCatalog.requestAccessibilityPermission() }
                }.padding(12).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            if let failure = model.failure { PocketMessage(failure, error: true) }
            if model.partial { Text("Liste süre/öğe sınırında kesildi. Yenileyebilirsin.").font(.caption).foregroundStyle(.orange) }
            HStack {
                TextField("Uygulama veya pencere ara…", text: $model.search).textFieldStyle(.roundedBorder)
                    .focused($searchFocused).frame(maxWidth: 360)
                Picker("Sırala", selection: $sort) {
                    Text("Son kullanılan").tag("recent"); Text("Uygulama").tag("application"); Text("Başlık").tag("title")
                }.frame(width: 220)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Yenile") { Task { await model.refresh() } }.disabled(model.busy)
            }
            HStack(spacing: 12) {
                Table(model.filtered, selection: $model.selection) {
                    TableColumn("Uygulama") { window in
                        HStack(spacing: 10) {
                            if let url = window.applicationURL { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24) }
                            Text(window.application).lineLimit(1)
                        }.padding(.vertical, 4)
                    }.width(min: 140, ideal: 210)
                    TableColumn("Pencere") { window in Text(window.title).lineLimit(1) }
                    TableColumn("Durum") { window in Text(window.hidden ? "Gizli" : (window.minimized ? "Küçültülmüş" : (window.fullScreen ? "Tam ekran" : (window.windowAccessible ? "Açık" : "Uygulama")))) }.width(95)
                }.tableStyle(.inset)
                    .contextMenu {
                        Button("Öne Getir") { activate() }.disabled(model.selected == nil)
                        Button("Uygulamayı Gizle") { Task { await model.action(.hideApplication) } }.disabled(model.selected == nil)
                        Button("Bu Uygulamayı Hariç Tut") { model.excludeSelected() }.disabled(model.selected?.applicationURL == nil)
                    }
                if showPreview && !overlay { previewPane.frame(width: 230) }
            }
            HStack {
                Menu("Pencere İşlemleri") {
                    Button(model.selected?.minimized == true ? "Küçültmeyi Geri Al" : "Küçült") { Task { await model.action(model.selected?.minimized == true ? .restore : .minimize) } }
                        .disabled(model.selected?.canMinimize != true)
                    Button(model.selected?.fullScreen == true ? "Tam Ekrandan Çık" : "Tam Ekrana Geç") { Task { await model.action(.toggleFullScreen) } }
                        .disabled(model.selected?.canFullScreen != true)
                    Button("Uygulamayı Gizle") { Task { await model.action(.hideApplication) } }.disabled(model.selected == nil)
                    Button("Pencereyi Kapat…", role: .destructive) { pendingClose = model.selected; confirmClose = true }.disabled(model.selected?.canClose != true)
                    Divider()
                    Button("Bu Uygulamayı Hariç Tut") { model.excludeSelected() }.disabled(model.selected?.applicationURL == nil)
                }
                Text("\(model.filtered.count) öğe").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.selected?.windowAccessible == true ? "Pencereyi Öne Getir" : "Uygulamayı Öne Getir", action: activate)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.selected == nil || model.busy)
            }
            if !overlay { Text("Space ve tam ekran geçişi macOS tarafından yönetilir. Son kullanılan sırası MacPocket’ın gözlemlediği etkinleştirmelerden oluşur.").font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.objectWillChange.send() }
        .onChange(of: model.selection) { _, _ in model.preview = nil; model.previewMessage = nil }
        .onChange(of: currentApplication) { _, _ in
            if currentApplication && model.foregroundPID == ProcessInfo.processInfo.processIdentifier {
                model.foregroundPID = model.windows.first(where: { $0.id == model.selection })?.processID ?? model.windows.first?.processID
            }
        }
        .sheet(isPresented: $showOptions) { options }
        .alert("Pencere kapatılsın mı?", isPresented: $confirmClose) {
            Button("Vazgeç", role: .cancel) {}
            Button("Pencereyi Kapat", role: .destructive) { if let id = pendingClose?.id { Task { await model.action(.close, id: id) } } }
        } message: { Text("\(pendingClose?.application ?? "Uygulama") · \(pendingClose?.title ?? "Pencere"). Kaydedilmemiş işler için uygulamanın kendi onayı açılabilir.") }
    }
    private func activate() {
        Task { await model.focus(); if model.failure == nil { onActivated() } }
    }
    private var previewPane: some View {
        VStack(spacing: 14) {
            if let image = model.preview { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 250) }
            else { Image(systemName: "macwindow").font(.system(size: 40)).foregroundStyle(.secondary) }
            if model.previewBusy { ProgressView().controlSize(.small) }
            if let message = model.previewMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if WindowPreviewProvider.permitted {
                Button("Seçili Pencereyi Önizle") { Task { await model.capturePreview() } }
                    .disabled(model.selected?.windowAccessible != true || model.previewBusy)
            } else {
                Text("Pencere önizlemeleri Ekran Kaydı izni gerektirir.").font(.caption).foregroundStyle(.secondary)
                Button("Ekran Kaydı İzni İste…") { WindowPreviewProvider.requestPermission() }
            }
            Text("Önizleme yalnız isteğinle alınır; diske kaydedilmez.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14).frame(maxHeight: .infinity).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Pencere Geçişi Seçenekleri").font(.title2.weight(.semibold)); Spacer(); Button("Kapat") { showOptions = false }.keyboardShortcut(.cancelAction) }
            Form {
                Section("Klavye") {
                    Toggle("Global kısayolu etkinleştir", isOn: $globalEnabled)
                    Picker("Kısayol", selection: $shortcut) {
                        Text("⌃⌥Space").tag("controlOptionSpace"); Text("⌥Tab").tag("optionTab"); Text("⌃Tab").tag("controlTab")
                    }.disabled(!globalEnabled)
                    Toggle("Tutulan değiştirici tuşlar bırakılınca seç", isOn: $releaseToChoose)
                    Text(hotkey.registrationMessage).font(.caption).foregroundStyle(.secondary)
                    Text("Aynı kısayolu kullanan AltTab gibi uygulamalarla çakışabilir. Varsayılan olarak kapalıdır.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Liste") {
                    Toggle("Küçültülmüş pencereleri göster", isOn: $includeMinimized)
                    Toggle("Gizli uygulamaları göster", isOn: $includeHidden)
                    Toggle("Penceresiz uygulamaları göster", isOn: $includeWindowless)
                    Toggle("Yalnız tek uygulama", isOn: $currentApplication)
                    if currentApplication {
                        Picker("Uygulama", selection: Binding(get: { model.foregroundPID ?? 0 }, set: { model.foregroundPID = $0; model.objectWillChange.send() })) {
                            ForEach(model.windows.filter { window in model.windows.first { $0.processID == window.processID }?.id == window.id }) { window in
                                Text(window.application).tag(window.processID)
                            }
                        }
                    }
                    Toggle("Önizleme alanını göster", isOn: $showPreview)
                }
                Section("Hariç Tutulan Uygulamalar") {
                    TextEditor(text: $excludedPaths).font(.caption.monospaced()).frame(height: 70)
                    Text("Her satıra tam .app yolu yaz. Listenin menüsünden de ekleyebilirsin.").font(.caption).foregroundStyle(.secondary)
                    Button("Hariç Tutma Listesini Temizle") { excludedPaths = "" }
                }
            }.formStyle(.grouped)
        }.padding(22).frame(width: 640, height: 650)
    }
}

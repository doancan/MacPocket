import AppKit
@preconcurrency import Carbon
import MacPocketCore
import SwiftUI

/// Tools → Pencere Geçişi: switcher settings and the detailed window table.
struct WindowSwitcherView: View {
    @ObservedObject private var controller = WindowSwitcherHotkeyController.shared
    @StateObject private var model = WindowSwitcherModel()
    @State private var section = Section.settings
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = WindowPreviewProvider.permitted

    private enum Section: String, CaseIterable {
        case settings, windows
        var title: LocalizedStringKey { self == .settings ? "Ayarlar" : "Pencereler" }
        var symbol: String { self == .settings ? "slider.horizontal.3" : "macwindow.on.rectangle" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Pencere Geçişi", subtitle: "Windows tarzı Alt+Tab: canlı küçük resimlerle pencereler arasında geçiş.",
                              icon: "macwindow.on.rectangle") {
                Button { controller.show() } label: { Label("Önizle", systemImage: "play.rectangle") }
                    .help("Pencere geçişini şimdi aç")
            }
            permissions
            GlassTabBar(tabs: Section.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol) }, selection: $section)
                .accessibilityLabel("Bölüm")
                .frame(maxWidth: 320)
            switch section {
            case .settings: SwitcherSettingsForm(controller: controller)
            case .windows: SwitcherWindowTable(model: model)
            }
        }
        .pocketPage()
        .onAppear { model.startObserving() }
        .onDisappear { model.stopObserving() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = WindowPreviewProvider.permitted
        }
    }

    private var permissions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PocketSpacing.m) { accessibilityCard; screenRecordingCard }
            VStack(spacing: PocketSpacing.m) { accessibilityCard; screenRecordingCard }
        }
    }

    private var accessibilityCard: some View {
        permissionCard(title: "Erişilebilirlik", granted: accessibility,
                       detail: "Pencere başlıkları, öne getirme, kapatma ve küçültme için.",
                       request: { WindowCatalog.requestAccessibilityPermission() },
                       settings: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private var screenRecordingCard: some View {
        permissionCard(title: "Ekran Kaydı", granted: screenRecording,
                       detail: "Canlı küçük resimler, tam boy önizleme ve diğer masaüstlerindeki pencereler için.",
                       request: { WindowPreviewProvider.requestPermission() },
                       settings: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func permissionCard(title: LocalizedStringKey, granted: Bool, detail: LocalizedStringKey, request: @escaping () -> Void, settings: String) -> some View {
        HStack(alignment: .top, spacing: PocketSpacing.m) {
            Image(systemName: granted ? "checkmark.seal.fill" : "lock.fill")
                .font(.title3).foregroundStyle(granted ? PocketTheme.disk : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                HStack {
                    Text(title).font(.headline)
                    PocketStatusBadge(text: granted ? "Verildi" : "Gerekli", tone: granted ? .success : .warning)
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PocketSpacing.s)
            if !granted {
                Menu("İzin Ver") {
                    Button("İzin İste") { request() }
                    Button("Sistem Ayarlarını Aç") { if let url = URL(string: settings) { NSWorkspace.shared.open(url) } }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard(padding: PocketSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings

private struct SwitcherSettingsForm: View {
    @ObservedObject var controller: WindowSwitcherHotkeyController
    @AppStorage("switcher.globalEnabled") private var enabled = true
    @AppStorage("switcher.style") private var style = SwitcherStyle.thumbnails.rawValue
    @AppStorage("switcher.autoSize") private var autoSize = true
    @AppStorage("switcher.size") private var size = 1.0
    @AppStorage("switcher.previewSelected") private var previewSelected = true
    @AppStorage("switcher.liveThumbnails") private var liveThumbnails = true
    @AppStorage("switcher.hoverSelects") private var hoverSelects = true
    @AppStorage("switcher.sort") private var sort = "recent"
    @AppStorage("switcher.excludedPaths") private var excludedPaths = ""
    @AppStorage("switcher.disabledApps") private var disabledApps = ""
    @AppStorage("switcher.gestureFingers") private var gestureFingers = 0

    var body: some View {
        Form {
            Section {
                Toggle("Global kısayolları etkinleştir", isOn: $enabled)
                ForEach(Array(controller.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    ShortcutRow(shortcut: shortcut, canDelete: controller.shortcuts.count > 1,
                                update: { replace(index, with: $0) }, delete: { remove(index) },
                                setRecording: controller.setRecording)
                }
                .disabled(!enabled)
                HStack {
                    Button { add() } label: { Label("Kısayol Ekle", systemImage: "plus") }
                        .disabled(!enabled || controller.shortcuts.count >= SwitcherShortcut.maximumCount)
                    Spacer()
                    Text("\(controller.shortcuts.count) / \(SwitcherShortcut.maximumCount)").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(controller.registrationMessage).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Kısayollar") } footer: {
                Text("Her kısayolun kendi filtreleri vardır; örneğin ⌥⇥ tüm pencereler, ⌥` yalnız öndeki uygulama. Shift ters yönde gezer.")
            }

            Section("Görünüm") {
LabeledContent("Stil") {
                    GlassTabBar(tabs: [GlassTab(id: SwitcherStyle.thumbnails.rawValue, title: "Küçük resimler", symbol: "rectangle.grid.2x2"),
                                       GlassTab(id: SwitcherStyle.icons.rawValue, title: "Uygulama simgeleri", symbol: "app.dashed"),
                                       GlassTab(id: SwitcherStyle.titles.rawValue, title: "Başlık listesi", symbol: "list.bullet")],
                                selection: $style)
                        .frame(maxWidth: 420)
                }
                Toggle("Otomatik boyut (pencere sayısına göre küçült)", isOn: $autoSize)
                Slider(value: $size, in: 0.6...1.4, step: 0.1) { Text("Boyut") } minimumValueLabel: { Text("Küçük") } maximumValueLabel: { Text("Büyük") }
                Toggle("Canlı küçük resimler (panel açıkken yenilenir)", isOn: $liveThumbnails)
                Toggle("Seçili pencereyi yerinde tam boy göster", isOn: $previewSelected)
                Picker("Sıralama", selection: $sort) {
                    Text("Son kullanılan").tag("recent"); Text("Uygulama").tag("application"); Text("Başlık").tag("title")
                }
                Text("Panel ekranın sistem görünümünü (açık/koyu) izler. Saydamlığı azalt tercihinde düz arka plan kullanılır.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section("Davranış") {
                Toggle("Fareyle üzerine gelince seç", isOn: $hoverSelects)
                LabeledContent("Klavye") {
                    Text("⇥ / ⇧⇥ / oklar gezinir · yazmak arar · ⌘W kapat · ⌘M küçült · ⌘F tam ekran · ⌘H gizle · ⌘Q çık · esc vazgeç")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }

            Section {
                AppListEditor(title: "Geçişte gösterme", storage: $excludedPaths, keyedByBundleID: false)
                AppListEditor(title: "Bu uygulama öndeyken kısayolları kapat", storage: $disabledApps, keyedByBundleID: true)
            } header: { Text("İstisnalar") } footer: {
                Text("Sanal makineler ve uzak masaüstü uygulamaları için kısayolları kapatmak, ⌥⇥’ın o uygulamaya iletilmesini sağlar.")
            }

            Section {
                Picker("Hareket", selection: $gestureFingers) {
                    Text("Kapalı").tag(0); Text("Üç parmakla kaydır").tag(3); Text("Dört parmakla kaydır").tag(4)
                }
                .disabled(!TrackpadSwipeMonitor.shared.isAvailable)
                Text(TrackpadSwipeMonitor.shared.isAvailable
                     ? "Sola/sağa kaydırma geçişi açar ve gezer, parmakları kaldırmak seçer. macOS aynı parmak sayısını masaüstleri arasında geçiş için kullanıyorsa Sistem Ayarları > Trackpad > Diğer Hareketler’den değiştir."
                     : "Bu macOS sürümünde trackpad hareket verisine erişilemiyor.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Trackpad") }

            Section("Komut satırı") {
                Text("macpocket-probe windows · macpocket-probe focus <windowID> · macpocket-probe thumbnail <windowID> <dosya.png>")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func replace(_ index: Int, with shortcut: SwitcherShortcut) {
        var list = controller.shortcuts
        guard list.indices.contains(index) else { return }
        list[index] = shortcut
        controller.saveShortcuts(list)
    }

    private func remove(_ index: Int) {
        var list = controller.shortcuts
        guard list.indices.contains(index), list.count > 1 else { return }
        list.remove(at: index)
        controller.saveShortcuts(list)
    }

    private func add() {
        var list = controller.shortcuts
        guard list.count < SwitcherShortcut.maximumCount else { return }
        // Suggest ⌥` (current app's windows), then ⌥1…⌥9 style combinations that are not yet used.
        let candidates: [SwitcherShortcut] = [.init(keyCode: SwitcherKeys.grave, modifiers: .option)]
            + [18, 19, 20, 21, 23, 22, 26, 28, 25].map { SwitcherShortcut(keyCode: $0, modifiers: [.control, .option]) }
        var next = candidates.first { candidate in !list.contains { $0.keyCode == candidate.keyCode && $0.modifiers == candidate.modifiers } }
            ?? .init(keyCode: SwitcherKeys.space, modifiers: [.control, .option, .command])
        if next.keyCode == SwitcherKeys.grave { next.filter.currentApplicationOnly = true }
        list.append(next)
        controller.saveShortcuts(list)
    }
}

private struct ShortcutRow: View {
    let shortcut: SwitcherShortcut
    let canDelete: Bool
    let update: (SwitcherShortcut) -> Void
    let delete: () -> Void
    let setRecording: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Button { recording ? stopRecording() : startRecording() } label: {
                (recording ? Text("Tuşlara bas…") : Text(shortcut.displayName))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(minWidth: 96)
            }
            .buttonStyle(.pocketSecondary)
            .tint(recording ? .accentColor : nil)
            .help("Yeni kısayolu kaydetmek için tıkla, ardından tuş birleşimine bas (esc: vazgeç)")
            .accessibilityLabel("Kısayol \(shortcut.displayName), değiştirmek için tıkla")

            Toggle("Bırakınca seç", isOn: binding(\.releaseToChoose)).toggleStyle(.checkbox)
                .help("Kapalıyken panel açık kalır; ↩ veya tıklamayla seçilir")
            Menu {
                Section("Uygulama") {
                    Picker("Uygulama", selection: binding(\.filter.currentApplicationOnly)) {
                        Text("Tüm uygulamalar").tag(false); Text("Yalnız öndeki uygulama").tag(true)
                    }
                }
                Section("Masaüstü") {
                    Picker("Masaüstü", selection: binding(\.filter.currentSpaceOnly)) {
                        Text("Tüm masaüstleri").tag(false); Text("Yalnız geçerli masaüstü").tag(true)
                    }
                }
                Section("Ekran") {
                    Picker("Ekran", selection: binding(\.filter.currentScreenOnly)) {
                        Text("Tüm ekranlar").tag(false); Text("Yalnız farenin bulunduğu ekran").tag(true)
                    }
                }
                Section("Göster") {
                    Toggle("Küçültülmüş pencereler", isOn: binding(\.filter.includeMinimized))
                    Toggle("Gizli uygulamalar", isOn: binding(\.filter.includeHidden))
                    Toggle("Penceresiz uygulamalar", isOn: binding(\.filter.includeWindowless))
                }
            } label: { Label(filterSummary, systemImage: "line.3.horizontal.decrease.circle") }
            .fixedSize()
            Spacer()
            Button(role: .destructive) { delete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(!canDelete)
                .help("Kısayolu sil").accessibilityLabel("Kısayolu sil")
        }
        .onDisappear { stopRecording() }
    }

    private var filterSummary: String {
        var parts: [String] = []
        parts.append(shortcut.filter.currentApplicationOnly ? String(localized: "Öndeki uygulama") : String(localized: "Tüm uygulamalar"))
        if shortcut.filter.currentSpaceOnly { parts.append(String(localized: "bu masaüstü")) }
        if shortcut.filter.currentScreenOnly { parts.append(String(localized: "bu ekran")) }
        return parts.joined(separator: " · ")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SwitcherShortcut, Value>) -> Binding<Value> {
        Binding(get: { shortcut[keyPath: keyPath] }, set: { value in
            var copy = shortcut
            copy[keyPath: keyPath] = value
            update(copy)
        })
    }

    private func startRecording() {
        recording = true
        setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode, flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated { () -> Bool in
                if Int(keyCode) == kVK_Escape { stopRecording(); return true }
                let modifiers: SwitcherModifiers = [flags.contains(.control) ? .control : [], flags.contains(.option) ? .option : [],
                                                    flags.contains(.command) ? .command : []]
                guard !modifiers.isEmpty, SwitcherKeys.isSupported(keyCode) else { NSSound.beep(); return true }
                var copy = shortcut
                copy.keyCode = keyCode
                copy.modifiers = modifiers
                stopRecording()
                update(copy)
                return true
            }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        setRecording(false)
    }
}

/// Newline-separated app list stored in user defaults (bundle paths or bundle identifiers).
private struct AppListEditor: View {
    let title: LocalizedStringKey
    @Binding var storage: String
    let keyedByBundleID: Bool

    private var entries: [String] { storage.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack {
                Text(title)
                Spacer()
                Menu {
                    let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                    ForEach(running, id: \.processIdentifier) { app in
                        if let key = key(for: app.bundleURL) {
                            Button(app.localizedName ?? key) { add(key) }.disabled(entries.contains(key))
                        }
                    }
                    Divider()
                    Button("Uygulama Seç…") { choose() }
                } label: { Label("Ekle", systemImage: "plus") }
                .fixedSize()
            }
            if entries.isEmpty {
                Text("Liste boş.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.self) { entry in
                    HStack(spacing: PocketSpacing.s) {
                        PocketAppIcon(url: url(for: entry), size: 18)
                        Text(displayName(entry)).lineLimit(1)
                        Spacer()
                        Button { storage = entries.filter { $0 != entry }.joined(separator: "\n") } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Listeden çıkar").accessibilityLabel("\(displayName(entry)) listeden çıkar")
                    }
                }
            }
        }
    }

    private func key(for url: URL?) -> String? {
        guard let url else { return nil }
        return keyedByBundleID ? Bundle(url: url)?.bundleIdentifier : url.path
    }

    private func url(for entry: String) -> URL? {
        keyedByBundleID ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry) : URL(fileURLWithPath: entry)
    }

    private func displayName(_ entry: String) -> String {
        guard let url = url(for: entry) else { return entry }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func add(_ key: String) {
        guard !entries.contains(key) else { return }
        storage = (entries + [key]).joined(separator: "\n")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Ekle")
        guard panel.runModal() == .OK, let key = key(for: panel.url) else { return }
        add(key)
    }
}

// MARK: - Window table

private struct SwitcherWindowTable: View {
    @ObservedObject var model: WindowSwitcherModel
    @State private var confirmClose = false
    @State private var pendingClose: SwitchableWindow?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            if let failure = model.failure { PocketMessage(failure, error: true) }
            if model.partial { PocketMessage("Liste süre veya öğe sınırında kesildi. Yenileyebilirsin.", tone: .warning) }
            if model.trusted && !model.otherSpacesVisible {
                PocketMessage("Diğer masaüstlerindeki pencereleri listelemek için Ekran Kaydı izni gerekir.", tone: .neutral)
            }
            HStack {
                PocketSearchField("Uygulama veya pencere ara…", text: $model.search, focus: $searchFocused).frame(maxWidth: 360)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }.disabled(model.busy)
            }
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                Table(model.filtered, selection: $model.selection) {
                    TableColumn("Uygulama") { window in
                        HStack(spacing: PocketSpacing.s) {
                            PocketAppIcon(url: window.applicationURL, size: 22)
                            Text(window.application).lineLimit(1)
                        }
                    }.width(min: 140, ideal: 200)
                    TableColumn("Pencere") { window in Text(window.title).lineLimit(1) }
                    TableColumn("Durum") { window in Text(state(window)).foregroundStyle(.secondary) }.width(120)
                }
                .tableStyle(.inset)
                .contextMenu {
                    Button("Öne Getir") { Task { await model.focus() } }.disabled(model.selected == nil)
                    Button("Uygulamayı Gizle") { Task { await model.action(.hideApplication) } }.disabled(model.selected == nil)
                    Button("Bu Uygulamayı Hariç Tut") { model.excludeSelected() }.disabled(model.selected?.applicationURL == nil)
                }
                previewPane.frame(width: 240)
            }
            HStack {
                Menu("Pencere İşlemleri") {
                    Button(model.selected?.minimized == true ? "Küçültmeyi Geri Al" : "Küçült") {
                        Task { await model.action(model.selected?.minimized == true ? .restore : .minimize) }
                    }.disabled(model.selected?.canMinimize != true)
                    Button(model.selected?.fullScreen == true ? "Tam Ekrandan Çık" : "Tam Ekrana Geç") { Task { await model.action(.toggleFullScreen) } }
                        .disabled(model.selected?.canFullScreen != true)
                    Button("Uygulamayı Gizle") { Task { await model.action(.hideApplication) } }.disabled(model.selected == nil)
                    Button("Pencereyi Kapat…", role: .destructive) { pendingClose = model.selected; confirmClose = true }
                        .disabled(model.selected?.canClose != true)
                    Divider()
                    Button("Bu Uygulamayı Hariç Tut") { model.excludeSelected() }.disabled(model.selected?.applicationURL == nil)
                }
                .fixedSize()
                Text("\(model.filtered.count) öğe").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(model.selected?.isRealWindow == true ? "Pencereyi Öne Getir" : "Uygulamayı Öne Getir") { Task { await model.focus() } }
                    .buttonStyle(.pocketPrimary).keyboardShortcut(.defaultAction).disabled(model.selected == nil || model.busy)
            }
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onChange(of: model.selection) { _, _ in model.preview = nil; model.previewMessage = nil }
        .alert("Pencere kapatılsın mı?", isPresented: $confirmClose) {
            Button("Vazgeç", role: .cancel) {}
            Button("Pencereyi Kapat", role: .destructive) { if let id = pendingClose?.id { Task { await model.action(.close, id: id) } } }
        } message: {
            let application = pendingClose?.application ?? String(localized: "Uygulama")
            let title = pendingClose?.title ?? String(localized: "Pencere")
            Text("\(application) · \(title). Kaydedilmemiş işler için uygulamanın kendi onayı açılabilir.")
        }
    }

    private func state(_ window: SwitchableWindow) -> String {
        if window.hidden { return String(localized: "Gizli") }
        if window.minimized { return String(localized: "Küçültülmüş") }
        if window.otherSpace { return String(localized: "Diğer masaüstü") }
        if window.fullScreen { return String(localized: "Tam ekran") }
        return window.isRealWindow ? String(localized: "WindowState.open", defaultValue: "Açık") : String(localized: "Penceresiz")
    }

    private var previewPane: some View {
        VStack(spacing: PocketSpacing.m) {
            if let image = model.preview {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small))
            } else {
                Image(systemName: "macwindow").font(.system(size: 40)).foregroundStyle(.secondary)
            }
            if model.previewBusy { ProgressView().controlSize(.small) }
            if let message = model.previewMessage { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            if WindowPreviewProvider.permitted {
                Button("Seçili Pencereyi Önizle") { Task { await model.capturePreview() } }
                    .disabled(model.selected?.windowID == nil || model.previewBusy)
            } else {
                Text("Önizleme Ekran Kaydı izni gerektirir.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Görüntüler yalnız bellekte tutulur; diske kaydedilmez.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pocketCard(padding: PocketSpacing.m)
    }
}

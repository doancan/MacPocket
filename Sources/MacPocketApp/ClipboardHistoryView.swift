import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

/// Tools → Pano Geçmişi: browse the history and configure capture, privacy and the panel shortcut.
struct ClipboardHistoryView: View {
    private enum Section: String, CaseIterable { case history, settings }

    @ObservedObject private var service = ClipboardService.shared
    @State private var section = Section.history

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Pano Geçmişi",
                              subtitle: "Kopyaladıkların aranabilir bir geçmişte kalır; kısayolla açıp istediğini yapıştır.",
                              icon: "doc.on.clipboard") {
                Toggle("Pano geçmişi", isOn: $service.settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(service.settings.enabled ? "Pano geçmişini kapat" : "Pano geçmişini aç")
            }
            if let error = service.lastError {
                HStack(alignment: .top) {
                    PocketMessage(error, tone: .warning)
                    Button { service.dismissError() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Uyarıyı kapat")
                }
            }
            if !service.settings.enabled {
                PocketMessage("Pano geçmişi kapalı. Açtığında MacPocket kopyaladığın metin, bağlantı, görsel ve dosyaları bu Mac’te saklar; parola yöneticilerinin gizli olarak işaretlediği içerikler hiçbir zaman kaydedilmez.",
                              tone: .neutral)
            } else {
                shortcutStatus
            }
            GlassTabBar(tabs: [GlassTab(id: Section.history, title: "Geçmiş", symbol: "clock"),
                               GlassTab(id: Section.settings, title: "Ayarlar", symbol: "slider.horizontal.3")],
                        selection: $section)
                .accessibilityLabel("Bölüm")
                .frame(maxWidth: 320)
            switch section {
            case .history: ClipboardHistoryBrowser(service: service)
            case .settings: ClipboardSettingsForm(service: service)
            }
        }
        .pocketPage()
    }

    @ViewBuilder private var shortcutStatus: some View {
        if service.shortcutRegistered {
            Label("Paneli açmak için \(service.settings.shortcut.displayName)", systemImage: "keyboard")
                .font(.callout).foregroundStyle(.secondary)
        } else if !service.recordingShortcut {
            PocketMessage("\(service.settings.shortcut.displayName) kaydedilemedi; başka bir uygulama kullanıyor olabilir. Ayarlar’dan başka bir kısayol seç.",
                          tone: .warning)
        }
    }
}

// MARK: - History

private struct ClipboardHistoryBrowser: View {
    @ObservedObject var service: ClipboardService
    @StateObject private var search: ClipboardSearchModel
    @State private var confirmClear = false

    init(service: ClipboardService) {
        self.service = service
        _search = StateObject(wrappedValue: ClipboardSearchModel(service: service))
    }

    var body: some View {
        let items = search.items
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Geçmişte ara…", text: $search.query).frame(maxWidth: 280)
                Picker(selection: $search.kind) {
                    Text("Tüm türler").tag(ClipboardContent.Kind?.none)
                    ForEach(ClipboardContent.Kind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(Optional(kind))
                    }
                } label: { Text("Tür") }
                .labelsHidden()
                .fixedSize()
                    .pocketMenuPicker()
                Spacer(minLength: PocketSpacing.s)
                Text("\(service.history.items.count) öğe").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Button(role: .destructive) { confirmClear = true } label: { Label("Temizle", systemImage: "trash") }
                    .disabled(service.history.items.isEmpty)
                    .confirmationDialog("Pano geçmişi temizlensin mi?", isPresented: $confirmClear) {
                        Button("Sabitlenenler kalsın") { service.clearHistory(includingPinned: false) }
                        Button("Hepsini sil", role: .destructive) { service.clearHistory(includingPinned: true) }
                    } message: {
                        Text("Silinen öğeler geri alınamaz. Sistem panosundaki içerik değişmez.")
                    }
            }
            if search.isSearching {
                PocketProgressRow(message: "Aranıyor…")
            } else if items.isEmpty {
                ContentUnavailableView(search.query.isEmpty ? "Geçmiş boş" : "Eşleşen öğe yok",
                                       systemImage: search.query.isEmpty ? "clipboard" : "magnifyingglass",
                                       description: Text(service.settings.enabled ? "Bir şey kopyaladığında burada görünür."
                                                                                   : "Pano geçmişini başlıktaki anahtarla aç."))
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .pocketCard()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ClipboardItemRow(item: item, service: service)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { service.copy(item) }
                                .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(PocketSpacing.s)
                }
                .pocketCard(padding: 0)
            }
        }
        .onAppear { search.start() }
        .onDisappear { search.stop() }
    }

    @ViewBuilder private func menu(for item: ClipboardItem) -> some View {
        Button("Kopyala") { service.copy(item) }
        if item.content.kind != .image {
            Button("Düz metin olarak kopyala") { service.copy(item, plain: true) }
        }
        Button(item.pinned ? "Sabitlemeyi kaldır" : "Sabitle") { service.setPinned(!item.pinned, item) }
        if service.canClean(item) {
            Button("İzleme parametrelerini temizle") { service.cleanLink(item) }
        }
        if case let .files(urls) = item.content {
            Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
        Divider()
        Button("Sil", role: .destructive) { service.remove(item) }
    }
}

// MARK: - Settings

private struct ClipboardSettingsForm: View {
    @ObservedObject var service: ClipboardService
    @State private var parameters = ""
    @State private var confirmErase = false
    @State private var accessibility = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                LabeledContent("Paneli aç") {
                    KeyComboRecorder(combo: Binding(get: { service.settings.shortcut },
                                                    set: { if let combo = $0 { service.settings.shortcut = combo } }),
                                     recording: { service.recordingShortcut = $0 })
                }
                Toggle("Seçilen öğeyi öndeki uygulamaya yapıştır", isOn: $service.settings.pasteOnSelect)
                if service.settings.pasteOnSelect && !accessibility {
                    HStack {
                        Text("Doğrudan yapıştırmak için Erişilebilirlik izni gerekir; izin yokken öğe yalnız kopyalanır.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("İzin ver…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            } header: { Text("Panel") }

            Section {
                Picker("En fazla", selection: $service.settings.capacity) {
                    ForEach(ClipboardSettings.capacityChoices, id: \.self) { Text("\($0) öğe").tag($0) }
                }
                    .pocketMenuPicker()
                Picker("Saklama süresi", selection: $service.settings.retentionDays) {
                    ForEach(ClipboardSettings.retentionChoices, id: \.self) { days in
                        Text(days.map { "\($0) gün" as LocalizedStringKey } ?? "Süresiz").tag(days)
                    }
                }
                    .pocketMenuPicker()
                Toggle("Görselleri de sakla", isOn: $service.settings.keepImages)
                Toggle("Geçmişi diske kaydet", isOn: $service.settings.saveToDisk)
                Text(service.settings.saveToDisk
                     ? "Geçmiş yalnız senin erişebildiğin bir klasörde (Application Support/MacPocket/Clipboard) tutulur. Sabitlenen öğeler süre ve sınırdan etkilenmez."
                     : "Geçmiş yalnız bellekte tutulur ve MacPocket kapanınca silinir; diskteki kopya silindi.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Kayıt") }

            Section {
                ForEach(service.settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: PocketSpacing.s) {
                        PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), size: 20)
                        Text(applicationName(bundleID))
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { service.settings.excludedBundleIDs.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(applicationName(bundleID)) uygulamasını listeden çıkar")
                    }
                }
                Button { chooseApplication() } label: { Label("Uygulama ekle…", systemImage: "plus") }
            } header: {
                Text("Kaydedilmeyen uygulamalar")
            } footer: {
                Text("Bu uygulamalardan kopyalananlar geçmişe girmez. Gizli olarak işaretlenen içerik (parolalar, tek kullanımlık kodlar) hangi uygulamadan gelirse gelsin kaydedilmez.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section {
                Picker("Sistem panosunu boşalt", selection: $service.settings.clearClipboardAfterMinutes) {
                    ForEach(ClipboardSettings.clearAfterChoices, id: \.self) { minutes in
                        Text(minutes.map { "\($0) dk sonra" as LocalizedStringKey } ?? "Hiçbir zaman").tag(minutes)
                    }
                }
                    .pocketMenuPicker()
                Toggle("Uykuya geçince ve ekran kilitlenince boşalt", isOn: $service.settings.clearClipboardOnSleepOrLock)
                Text("Yalnız sistem panosu boşaltılır; geçmişteki kopya kalır. Kopyaladığın parolanın panoda unutulmasını önler.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Tüm geçmişi kalıcı olarak sil…", role: .destructive) { confirmErase = true }
                    .confirmationDialog("Tüm pano geçmişi silinsin mi?", isPresented: $confirmErase) {
                        Button("Sabitlenenler dahil hepsini sil", role: .destructive) { service.eraseEverything() }
                    } message: {
                        Text("Diskteki geçmiş dosyası ve kaydedilen görseller silinir. Bu işlem geri alınamaz.")
                    }
            } header: { Text("Gizlilik") }

            Section {
                Toggle("Kopyalanan bağlantılardan izleme parametrelerini temizle", isOn: $service.settings.cleanCopiedLinks)
                LabeledContent("Ek parametreler") {
                    TextField("ör. ref, partner", text: $parameters)
                        .frame(maxWidth: 260)
                        .onSubmit(saveParameters)
                }
                Text("utm_*, fbclid, gclid gibi bilinen izleme parametreleri ile YouTube, Spotify, Amazon ve LinkedIn’e özgü olanlar kaldırılır; bağlantının geri kalanı ve sırası korunur. Kapalıyken de geçmişte izleme içeren bağlantıları sağ tıkla temizleyebilirsin.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Bağlantılar") }
        }
        .formStyle(.grouped)
        .onAppear {
            parameters = service.settings.extraTrackingParameters.joined(separator: ", ")
            accessibility = AXIsProcessTrusted()
        }
        .onDisappear(perform: saveParameters)
    }

    private func saveParameters() {
        service.settings.extraTrackingParameters = parameters.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func applicationName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        service.settings.excludedBundleIDs.append(contentsOf: ids.filter { !service.settings.excludedBundleIDs.contains($0) })
    }
}

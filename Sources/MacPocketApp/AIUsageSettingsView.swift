import AppKit
import MacPocketAIUsage
import MacPocketCore
import SwiftUI
import UsageCore

struct AIUsageSettingsView: View {
    var embedded = false
    @ObservedObject var service = AIUsageService.shared
    @ObservedObject private var bar = MenuBarSettingsStore.shared
    @State private var page = AIUsageWorkspacePage.overview
    @State private var adding = false
    @State private var removing: AIUsageAccount?
    @State private var error: String?
    @Environment(\.openWindow) private var openWindow

    init(embedded: Bool = false, service: AIUsageService = .shared, initiallyAdding: Bool = false) {
        self.embedded = embedded; self.service = service
        _adding = State(initialValue: initiallyAdding)
    }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Birden çok Claude, Codex ve Grok hesabını ayrı kotalarla takip et.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Hesapları ve Kota Ayarlarını Aç") { openWindow(id: "ai-usage") }
                }
            } else {
                workspace
            }
        }
        .sheet(isPresented: $adding) { AIUsageAddAccountSheet(service: service) }
        .confirmationDialog("Hesap takibi kaldırılsın mı?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        )) {
            Button("Takibi Kaldır", role: .destructive) {
                if let removing { service.remove(removing.id) }
                removing = nil
            }
        } message: { Text("Bu işlem hesabı MacPocket listesinden kaldırır. CLI oturumu kendi uygulamasında yönetilir.") }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Kotaları").font(.system(size: 25, weight: .semibold))
                    Text("Hesapların ve limitlerin, tek bakışta.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await service.refresh(manual: true) } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(!service.active || !service.refreshing.isEmpty)
                Button("Hesap Ekle", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
            Picker("Kota görünümü", selection: $page) {
                ForEach(AIUsageWorkspacePage.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 22).padding(.bottom, 14)
            Divider()
            Group {
                switch page {
                case .overview: AIUsageDashboardView(service: service) { adding = true }
                case .accounts: Form { accountSection }.formStyle(.grouped)
                case .settings: Form { quotaSettings }.formStyle(.grouped)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                if service.active {
                    Text("Abonelik kotası · API harcaması dahil değil.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Takip duraklatıldı", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                    Button("Takibi Başlat") { AIUsageIntegration.shared.enableMenuBar() }.controlSize(.small)
                }
                Spacer()
                Picker("Yüzde gösterimi", selection: setting(\.mode)) {
                    ForEach(AIUsageDisplayMode.allCases) { Text($0.localizedTitle).tag($0) }
                }.labelsHidden().pocketMenuPicker().fixedSize().controlSize(.small)
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var accountSection: some View {
        Section {
            HStack {
                Text("Her hesap ayrı izlenir. Hesabını adlandır ve eklerken oturum kaynağını seç.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            if service.settings.accounts.isEmpty {
                Text("Henüz hesap eklenmedi.").foregroundStyle(.secondary)
            }
            ForEach(service.settings.accounts) { account in
                accountRow(account)
            }
        } header: { Text("AI Hesapları") }
    }

    @ViewBuilder private var quotaSettings: some View {

        Section {
            Toggle("Menü çubuğunda göster", isOn: Binding(get: {
                bar.preferences.visible && bar.preferences.enabled.contains(.aiUsage)
            }, set: { enabled in
                var preferences = bar.preferences
                if enabled { preferences.enabled.insert(.aiUsage); preferences.visible = true }
                else { preferences.enabled.remove(.aiUsage) }
                bar.preferences = preferences
            }))
            Picker("Yüzde gösterimi", selection: setting(\.mode)) {
                ForEach(AIUsageDisplayMode.allCases) { Text($0.localizedTitle).tag($0) }
            }
                .pocketMenuPicker()
            Picker("Menü çubuğu görünümü", selection: Binding(
                get: { bar.preferences.settings(for: .aiUsage).style },
                set: { value in var s = bar.preferences.settings(for: .aiUsage); s.style = value; bar.preferences.modules[.aiUsage] = s }
            )) {
                Text("Hesap adları ve yüzdeler").tag(MenuBarDisplayStyle.value)
                Text("Yalnız simge").tag(MenuBarDisplayStyle.icon)
            }
                .pocketMenuPicker()
            Toggle("Kota eşiğine göre renklendir", isOn: Binding(
                get: { bar.preferences.settings(for: .aiUsage).colorMode == .thresholds },
                set: { value in var s = bar.preferences.settings(for: .aiUsage); s.colorMode = value ? .thresholds : .monochrome; bar.preferences.modules[.aiUsage] = s }
            ))
            Text("İşaretlenen ilk üç hesap menü çubuğunda gösterilir; tüm hesaplar ayrıntı panelinde bulunur.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Yüzen kota panelini göster", isOn: setting(\.floatingPanel))
            if service.settings.floatingPanel {
                Toggle("Yüzen paneli yatay yerleştir", isOn: setting(\.floatingHorizontal))
            }
        } header: { Text("Gösterim") }

        Section {
            Picker("Kota yenileme aralığı", selection: setting(\.refreshMinutes)) {
                Text("5 dakika").tag(5)
                Text("10 dakika").tag(10)
                Text("15 dakika").tag(15)
                Text("30 dakika").tag(30)
                Text("60 dakika").tag(60)
            }
                .pocketMenuPicker()
            HStack {
                Button("Şimdi Yenile", systemImage: "arrow.clockwise") { Task { await service.refresh(manual: true) } }
                    .disabled(!service.active || !service.refreshing.isEmpty || service.enabledAccounts.isEmpty)
                if !service.refreshing.isEmpty { ProgressView().controlSize(.small) }
            }
            Text("Sağlayıcının bekleme süresi dolmadan yeni istek gönderilmez. Bağlantı sorunu varsa son değerlerin durumu belirtilir.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("Yenileme") }

        Section {
            Toggle("Kota eşiklerinde bildirim gönder", isOn: Binding(
                get: { service.settings.alertsEnabled },
                set: { enabled in
                    if !enabled { var s = service.settings; s.alertsEnabled = false; service.setSettings(s) }
                    else {
                        Task {
                            let allowed = await AIUsageIntegration.shared.requestAlerts()
                            var s = service.settings; s.alertsEnabled = allowed; service.setSettings(s)
                            if !allowed { error = String(localized: "Bildirim izni verilmedi. Sistem Ayarları’ndan MacPocket bildirimlerini açabilirsin.") }
                        }
                    }
                }
            ))
            Stepper(value: setting(\.warning), in: 1...98, step: 1) {
                let percent = AIUsageService.percent(service.settings.warning)
                Text("Uyarı: kullanılan \(percent)")
            }
            Stepper(value: setting(\.critical), in: (service.settings.warning + 1)...100, step: 1) {
                let percent = AIUsageService.percent(service.settings.critical)
                Text("Kritik: kullanılan \(percent)")
            }
            Text("Bildirimler her hesap ve kota dönemi için ayrı takip edilir.").font(.caption).foregroundStyle(.secondary)
        } header: { Text("Uyarılar") }

        Section {
            Text("Claude profilleri ayrı yapılandırma klasörleriyle açılır. MacPocket oturum verisini ilgili CLI veya Anahtar Zinciri kaydından okur.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Abonelik kotası gösterilir; API harcaması ve Grok web kotası farklı olabilir.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Kota bağlantıları sağlayıcıların herkese açık API sözleşmesinde yer almaz; sağlayıcı değişiklikleri erişimi etkileyebilir.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Tanılama Özetini Kopyala") { AIUsageIntegration.shared.copyDiagnostics() }
                .help("Tanılama özeti oturum anahtarı içermez.")
            if let error = error ?? service.storageError { Text(error).foregroundStyle(.orange).font(.callout) }
        } header: { Text("Oturum ve Tanılama") }
    }

    private func setting<Value>(_ path: WritableKeyPath<AIUsageSettings, Value>) -> Binding<Value> {
        Binding(get: { service.settings[keyPath: path] }, set: { value in
            var updated = service.settings; updated[keyPath: path] = value; service.setSettings(updated)
        })
    }

    private func accountRow(_ account: AIUsageAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle(account.provider.localizedTitle, isOn: Binding(get: {
                    service.settings.accounts.first { $0.id == account.id }?.enabled ?? false
                }, set: { enabled in var a = account; a.enabled = enabled; service.update(a) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .accessibilityLabel(account.provider.localizedTitle + ": " + account.name)
                AIUsageProviderIcon(provider: account.provider, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Hesap adı", text: Binding(get: {
                        service.settings.accounts.first { $0.id == account.id }?.name ?? account.name
                    }, set: { value in var a = account; a.name = value; service.update(a) }))
                    .font(.headline).textFieldStyle(.plain).labelsHidden().multilineTextAlignment(.leading)
                    Text(account.provider.localizedTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Menüde", isOn: Binding(get: {
                    service.settings.accounts.first { $0.id == account.id }?.showInMenuBar ?? false
                }, set: { shown in var a = account; a.showInMenuBar = shown; service.update(a) }))
                .toggleStyle(.checkbox)
                Button { removing = account } label: { Label("Hesap Takibini Kaldır", systemImage: "minus.circle") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            HStack {
                Text(AIUsageText.status(service.snapshot(for: account))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if case .claudeProfile = account.source {
                    Button("Profile Giriş Yap") {
                        do { try AIUsageIntegration.shared.beginClaudeLogin(account) }
                        catch { self.error = String(localized: "Giriş penceresi açılamadı. Claude Code’un kurulu olduğunu kontrol et.") }
                    }
                }
                Button("Yenile") { Task { await service.refresh(manual: true, only: account.id) } }
                    .disabled(!service.active || !account.enabled || service.refreshing.contains(account.id))
            }
            DisclosureGroup("Oturum Kaynağı") {
                Text(account.source.location).font(.caption.monospaced()).textSelection(.enabled)
                    .lineLimit(2).truncationMode(.middle)
                Text(account.provider.loginHelp).font(.caption).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct AIUsageAddAccountSheet: View {
    @ObservedObject var service: AIUsageService
    @Environment(\.dismiss) private var dismiss
    @State private var provider = AIUsageProvider.claude
    @State private var name = ""
    @State private var newProfile = false
    @State private var selectedPath = ""
    @State private var keychainID = ""
    @State private var entries: [ClaudeKeychainEntry] = []
    @State private var error: String?
    @State private var newID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AIUsageProviderIcon(provider: provider, size: 28)
                Text("AI Hesabı Ekle").font(.title2.bold())
            }
            HStack(spacing: 8) {
                ForEach(AIUsageProvider.allCases) { item in
                    Button { provider = item } label: {
                        HStack(spacing: 7) {
                            AIUsageProviderIcon(provider: item, size: 16)
                            Text(item.localizedTitle).font(.system(size: 12, weight: .medium))
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(provider == item ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(provider == item ? Color.accentColor.opacity(0.5) : Color.clear) }
                    }.buttonStyle(.plain).accessibilityAddTraits(provider == item ? [.isSelected] : [])
                }
            }.accessibilityLabel("Sağlayıcı")
            Form {
                TextField("Hesap adı (ör. Kişisel, İş)", text: $name)
                if provider == .claude {
                    Picker("Claude hesabı", selection: $newProfile) {
                        Text("Mevcut hesabı kullan").tag(false)
                        Text("Yeni hesaba giriş yap").tag(true)
                    }.pickerStyle(.segmented)
                    if newProfile {
                        Text("Bu hesap için ayrı bir profil klasörü oluşturulur. Giriş Claude Code’un kendi penceresinde tamamlanır.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ClaudeProfileSelector(directory: $selectedPath, accounts: service.settings.accounts, home: profileHome)
                        DisclosureGroup("Gelişmiş: Anahtar Zinciri") {
                            Picker("Anahtar Zinciri kaydı", selection: $keychainID) {
                                Text("Profilin kendi oturumunu bul").tag("")
                                ForEach(entries) { Text($0.service).tag($0.id) }
                            }
                                .pocketMenuPicker()
                        }.font(.caption)
                    }
                } else {
                    pathPicker(directory: false)
                    Button("Geçerli CLI oturumunu kullan") {
                        selectedPath = provider == .codex ? FileCodexAuthReader.defaultURL.path : FileGrokAuthReader.defaultURL.path
                    }
                    Text(provider.loginHelp).font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.orange).font(.callout) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(provider == .claude && newProfile ? "Ekle ve Giriş Yap" : "Hesabı Ekle") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 600)
        .onAppear { entries = AIUsageCredentials.claudeEntries() }
        .onChange(of: provider) { _, _ in selectedPath = ""; keychainID = ""; error = nil }
        .onChange(of: selectedPath) { _, _ in keychainID = ""; error = nil }
    }

    private var profileHome: URL {
        #if DEBUG
        if AIUsageFixtures.requested { return AIUsageFixtures.profileSearchHome }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func pathPicker(directory: Bool) -> some View {
        HStack {
            Text(selectedPath.isEmpty ? String(localized: "Oturum kaynağı seçilmedi") : selectedPath)
                .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(directory ? "Klasör Seç…" : "auth.json Seç…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
                panel.allowsMultipleSelection = false
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                if panel.runModal() == .OK, let url = panel.url { selectedPath = url.path }
            }
        }
    }
    private func add() {
        let source: AIUsageSource
        if provider == .claude {
            if newProfile {
                let path = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/Application Support/MacPocket/AIUsage/ClaudeProfiles/\(newID.uuidString)").path
                source = .claudeProfile(directory: path, service: nil)
            } else {
                let input = selectedPath.trimmingCharacters(in: .whitespacesAndNewlines)
                let selected = entries.first { $0.id == keychainID }
                if input.isEmpty {
                    source = .claudeKeychain(service: selected?.service ?? "Claude Code-credentials", account: selected?.account ?? NSUserName())
                } else {
                    guard let folder = ClaudeProfileDiscovery.folderURL(input, home: profileHome) else {
                        error = String(localized: "Geçerli bir klasör yolu gir veya listeden bir profil seç."); return
                    }
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        error = String(localized: "Bu klasör bulunamadı. Yolu kontrol et veya Klasör Seç’i kullan."); return
                    }
                    source = selected.map { .claudeProfile(directory: folder.path, service: $0.service) }
                        ?? ClaudeProfileDiscovery.source(for: folder, home: profileHome, entries: entries)
                }
            }
        } else {
            guard !selectedPath.isEmpty else { error = String(localized: "Önce bu hesabın auth.json dosyasını seç."); return }
            source = provider == .codex ? .codexFile(path: selectedPath) : .grokFile(path: selectedPath)
        }
        let account = AIUsageAccount(id: newID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), source: source)
        guard service.add(account) else { error = String(localized: "Bu oturum kaynağı zaten ekli veya hesap bilgileri geçersiz."); return }
        AIUsageIntegration.shared.enableMenuBar()
        if provider == .claude && newProfile {
            do { try AIUsageIntegration.shared.beginClaudeLogin(account) }
            catch { /* The account remains available with its Profile Login action. */ }
        }
        dismiss()
    }
}

private enum AIUsageWorkspacePage: String, CaseIterable, Identifiable {
    case overview, accounts, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: String(localized: "Genel Bakış")
        case .accounts: String(localized: "Hesaplar")
        case .settings: String(localized: "Ayarlar")
        }
    }
}

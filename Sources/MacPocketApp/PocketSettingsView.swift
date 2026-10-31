import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

struct PocketSettingsView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        TabView {
            PocketGeneralSettings(model: model, loginItem: loginItem)
                .tabItem { Label("Genel", systemImage: "gearshape") }
            PocketAppearanceSettings()
                .tabItem { Label("Görünüm", systemImage: "paintbrush") }
            StatusBarPreferencesView(model: model)
                .tabItem { Label("Menü Çubuğu", systemImage: "menubar.rectangle") }
            PocketMonitoringSettings(model: model)
                .tabItem { Label("İzleme", systemImage: "waveform.path.ecg") }
            PocketAdvancedSettings(model: model)
                .tabItem { Label("Gelişmiş", systemImage: "gearshape.2") }
        }
        .frame(width: 640, height: 520)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}

// MARK: - General

private struct PocketGeneralSettings: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var loginItem: LoginItemController
    @State private var language = AppLanguage.stored
    @AppStorage(MenuBarPreferences.visibleKey) private var showMenuBar = true
    @AppStorage("MacPocket.menuBarCPU") private var menuBarCPU = true
    @AppStorage(PocketPreferenceKey.showInDock) private var showInDock = true
    @AppStorage(PocketPreferenceKey.showWindowAtLaunch) private var showWindowAtLaunch = true
    @AppStorage(PocketPreferenceKey.launchPage) private var launchPage = PocketPage.overview
    @AppStorage(PocketPreferenceKey.confirmQuitWhileAwake) private var confirmQuitWhileAwake = true

    var body: some View {
        Form {
            Section {
                Picker("Dil / Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .onChange(of: language) { _, value in value.save(to: .standard) }
                if language != PocketRelaunch.languageAtLaunch {
                    HStack {
                        Text("Yeni dil MacPocket yeniden başlatılınca uygulanır.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Yeniden Başlat / Relaunch") { PocketRelaunch.relaunch() }
                    }
                } else {
                    Text("Sistem, macOS dil sırasını izler. Türkçe ve İngilizce desteklenir.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: { Text("Dil") }

            Section {
                Toggle("Oturum açıldığında MacPocket’ı başlat", isOn: Binding(
                    get: { loginItem.status.isRegistered },
                    set: { value in Task { await loginItem.setEnabled(value) } }
                ))
                .disabled(loginItem.isUpdating)
                HStack {
                    if loginItem.isUpdating { ProgressView().controlSize(.small) }
                    Text(loginItemDescription).font(.callout).foregroundStyle(.secondary)
                }
                if loginItem.status == .requiresApproval {
                    Button("Giriş Öğeleri Ayarlarını Aç…") { loginItem.openSystemSettings() }
                }
                if let error = loginItem.error {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
                Toggle("Ana pencereyi açılışta göster", isOn: $showWindowAtLaunch)
                Picker("Açılışta açılacak sayfa", selection: $launchPage) {
                    ForEach(PocketPage.allCases) { Text($0.localizedTitle).tag($0) }
                }
            } header: { Text(String(localized: "Settings.startupSection", defaultValue: "Başlangıç")) }

            Section {
                Toggle("Dock’ta göster", isOn: $showInDock)
                    .disabled(!showMenuBar)
                    .onChange(of: showInDock) { PocketDock.apply() }
                Toggle("Menü çubuğunda MacPocket’ı göster", isOn: $showMenuBar)
                    .onChange(of: showMenuBar) { PocketDock.apply() }
                Toggle("Menü çubuğunda CPU yüzdesini göster", isOn: $menuBarCPU)
                    .disabled(!showMenuBar)
                Text(showMenuBar
                     ? "Pencereyi kapattığında izleme menü çubuğunda sürer. Dock simgesi gizliyken MacPocket’a menü çubuğundan ulaşırsın."
                     : "Menü çubuğu öğesi gizliyken Dock simgesi her zaman gösterilir; böylece MacPocket’a ulaşabilirsin.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Dock ve Menü Çubuğu") }

            Section {
                Toggle("Mac uyanık tutulurken çıkmadan önce sor", isOn: $confirmQuitWhileAwake)
                Text("Tamamen kapatmak için MacPocket > MacPocket’tan Çık’ı kullan.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Çıkış") }

            Section {
                LabeledContent("Pencere Geçişi") {
                    Button("Pencere Geçişi Ayarlarını Aç…") {
                        model.navigation.open(.windowSwitcher)
                        model.openMainWindow?()
                    }
                }
                LabeledContent("Sürüm") { Text(verbatim: Self.versionDescription) }
                Text("MacPocket tüm ölçümleri bu Mac’te tutar; veri göndermez.").font(.callout).foregroundStyle(.secondary)
            } header: { Text("Hakkında") }
        }
        .formStyle(.grouped)
    }

    private static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? String(localized: "geliştirme")
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var loginItemDescription: LocalizedStringKey {
        switch loginItem.status {
        case .enabled: "macOS kaydı etkin. Sonraki oturum açılışında başlatılır."
        case .notRegistered: "Otomatik başlatma kapalı."
        case .requiresApproval: "Etkinleşmesi için macOS Giriş Öğeleri bölümünde onay gerekiyor."
        case .notFound: "macOS bu uygulamanın giriş kaydını bulamadı."
        case .unknown: "Otomatik başlatma durumu okunamadı."
        }
    }
}

// MARK: - Appearance

private struct PocketAppearanceSettings: View {
    @AppStorage("MacPocket.appearance") private var appearance = PocketAppearance.defaultValue
    @AppStorage(PocketPreferenceKey.accentStyle) private var accent = PocketAccentStyle.brand
    @AppStorage(PocketPreferenceKey.sidebarIcons) private var sidebarIcons = PocketSidebarIconStyle.colorful
    @AppStorage(PocketPreferenceKey.density) private var density = PocketDensity.comfortable
    @AppStorage(PocketPreferenceKey.reduceMotion) private var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Form {
            Section {
LabeledContent("Görünüm") {
                    GlassTabBar(tabs: PocketAppearance.allCases.map { GlassTab(id: $0, title: $0.localizedTitle) }, selection: $appearance)
                        .frame(maxWidth: 300)
                }
                Picker("Vurgu rengi", selection: $accent) {
                    ForEach(PocketAccentStyle.allCases) { style in
                        Label { Text(style.localizedTitle) } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(style == .brand ? PocketTheme.cobalt : Color.accentColor)
                        }
                        .tag(style)
                    }
                }
                Text("Sistem vurgu rengi, macOS Sistem Ayarları > Görünüm’deki rengi kullanır.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Tema") }

            Section {
LabeledContent("Kenar çubuğu simgeleri") {
                    GlassTabBar(tabs: PocketSidebarIconStyle.allCases.map { GlassTab(id: $0, title: $0.localizedTitle) }, selection: $sidebarIcons)
                        .frame(maxWidth: 300)
                }
LabeledContent("Kart yoğunluğu") {
                    GlassTabBar(tabs: PocketDensity.allCases.map { GlassTab(id: $0, title: $0.localizedTitle) }, selection: $density)
                        .frame(maxWidth: 220)
                }
                Text("Sıkı yoğunluk kart ve sayfa boşluklarını azaltır; küçük ekranlarda daha çok bilgi gösterir.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Yerleşim") }

            Section {
                Toggle("Hareketleri azalt", isOn: $reduceMotion)
                    .disabled(systemReduceMotion)
                Text(systemReduceMotion
                     ? "macOS Erişilebilirlik ayarlarında Hareketi azalt açık; sayfa geçişleri ve pencere geçişi animasyonları zaten azaltılıyor."
                     : "Sayfa geçişlerini ve pencere geçişi animasyonlarını sadeleştirir.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text(String(localized: "Settings.motionSection", defaultValue: "Hareket")) }

            Section {
                Label("Sistemle bütünleşik gezinme ve kontroller", systemImage: "rectangle.3.group")
                if #available(macOS 26.0, *) {
                    Text("Liquid Glass; kenar çubuğu, araç çubuğu ve hızlı kontrollerde kullanılır. Saydamlığı azalt tercihin macOS Erişilebilirlik ayarlarından takip edilir.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Bu macOS sürümünde sistem materyalleri kullanılır. Liquid Glass macOS 26 ve üzerinde etkinleşir.")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Materyaller") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Monitoring

private struct PocketMonitoringSettings: View {
    @ObservedObject var model: PocketModel
    @AppStorage("manager.showUser") private var showUser = true
    @AppStorage("manager.showThreads") private var showThreads = true
    @AppStorage(ProcessCPUScale.key) private var cpuScale = ProcessCPUScale.defaultValue
    @AppStorage(PowerHistoryRetention.key) private var historyDays = PowerHistoryRetention.defaultDays
    @AppStorage(ResourceAlertSettings.enabledKey(.lowDisk)) private var alertDisk = false
    @AppStorage(ResourceAlertSettings.enabledKey(.thermal)) private var alertThermal = false
    @AppStorage(ResourceAlertSettings.enabledKey(.memoryPressure)) private var alertMemory = false
    @AppStorage(ResourceAlertSettings.diskThresholdKey) private var diskThreshold = 10.0
    @AppStorage(ResourceAlertSettings.enabledKey(.sustainedCPU)) private var alertCPU = false
    @AppStorage(ResourceAlertSettings.cpuThresholdKey) private var cpuThreshold = 85.0
    @AppStorage(ResourceAlertSettings.cpuMinutesKey) private var cpuMinutes = 5
    @AppStorage(ResourceAlertSettings.enabledKey(.lowBattery)) private var alertBattery = false
    @AppStorage(ResourceAlertSettings.batteryThresholdKey) private var batteryThreshold = 15.0
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                Picker("Yenileme aralığı", selection: $model.refreshSeconds) {
                    Text("1 saniye").tag(1.0)
                    Text("2 saniye").tag(2.0)
                    Text("5 saniye").tag(5.0)
                    Text("10 saniye").tag(10.0)
                }
                Text("Daha uzun aralıklar izleme yükünü azaltır. Pencere kapalıyken menü çubuğu için yalnız sistem özeti güncellenir.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Örnekleme") }

            Section {
                Picker("Güç geçmişini sakla", selection: $historyDays) {
                    ForEach(PowerHistoryRetention.dayChoices, id: \.self) { days in
                        Text("\(days) gün").tag(days)
                    }
                }
                Text("Pil ve güç olayları dakikada en çok bir kez kaydedilir. Süreyi kısaltmak eski kayıtları siler.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Geçmiş") }

            Section {
                alertToggle(.lowDisk, isOn: $alertDisk)
                Picker("Boş alan eşiği", selection: $diskThreshold) {
                    ForEach(ResourceAlertSettings.diskThresholdChoices, id: \.self) { value in
                        Text(verbatim: pocketPercent(value)).tag(value)
                    }
                }
                .disabled(!alertDisk)
                alertToggle(.thermal, isOn: $alertThermal)
                alertToggle(.memoryPressure, isOn: $alertMemory)
                alertToggle(.sustainedCPU, isOn: $alertCPU)
                HStack {
                    Picker("Eşik", selection: $cpuThreshold) {
                        ForEach(ResourceAlertSettings.cpuThresholdChoices, id: \.self) { Text(verbatim: pocketPercent($0)).tag($0) }
                    }
                    Picker("Süre", selection: $cpuMinutes) {
                        ForEach(ResourceAlertSettings.cpuMinuteChoices, id: \.self) { Text("\($0) dk").tag($0) }
                    }
                }
                .disabled(!alertCPU)
                alertToggle(.lowBattery, isOn: $alertBattery)
                Picker("Pil eşiği", selection: $batteryThreshold) {
                    ForEach(ResourceAlertSettings.batteryThresholdChoices, id: \.self) { Text(verbatim: pocketPercent($0)).tag($0) }
                }
                .disabled(!alertBattery)
                if notificationsDenied {
                    HStack {
                        Label("MacPocket’ın bildirim izni kapalı.", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Bildirim Ayarlarını Aç…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } else if !PocketAlertNotifier.isAvailable {
                    Text("Bildirimler yalnız paketlenmiş MacPocket uygulamasında çalışır.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Koşul sürdükçe her uyarı en çok saatte bir gönderilir.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Uyarılar") }

            Section {
                Toggle("Kullanıcı sütununu göster", isOn: $showUser)
                Toggle("İş parçacığı sütununu göster", isOn: $showThreads)
                Picker("Süreç CPU yüzdesi", selection: $cpuScale) {
                    ForEach(ProcessCPUScale.allCases) { Text($0.title).tag($0) }
                }
                Text("Tüm Mac: her süreç %0–100 arasında, tüm çekirdeklere oranla gösterilir. Çekirdek başına: Unix/Linux ve Etkinlik Monitörü gibi; birden çok çekirdeği kullanan süreç %100’ü aşabilir.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Görev Yöneticisi") }
        }
        .formStyle(.grouped)
        .task {
            guard alertDisk || alertThermal || alertMemory || alertCPU || alertBattery else { return }
            notificationsDenied = await PocketAlertNotifier.authorizationDenied()
        }
    }

    private func alertToggle(_ kind: ResourceAlertKind, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(kind.localizedTitle) }
            .onChange(of: isOn.wrappedValue) { _, enabled in
                guard enabled else { return }
                Task {
                    let allowed = await PocketAlertNotifier.requestAuthorization()
                    notificationsDenied = PocketAlertNotifier.isAvailable && !allowed
                }
            }
    }
}

// MARK: - Advanced

private struct PocketAdvancedSettings: View {
    @ObservedObject var model: PocketModel
    @State private var message: PocketSettingsMessage?
    @State private var confirmReset = false
    @State private var confirmClearHistory = false
    @State private var needsRelaunch = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Ayar dosyası") {
                    HStack {
                        Button("Dışa Aktar…", action: exportSettings)
                        Button("İçe Aktar…", action: importSettings)
                    }
                }
                Text("Görünüm, menü çubuğu, izleme ve pencere geçişi ayarları JSON dosyasına yazılır. İçe aktarma mevcut ayarların yerini alır.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Sıfırla") {
                    Button("Tüm Ayarları Sıfırla…", role: .destructive) { confirmReset = true }
                }
                if let message {
                    PocketMessage(message.text, tone: message.tone)
                }
                if needsRelaunch {
                    HStack {
                        Text("Bazı ayarlar MacPocket yeniden başlatılınca uygulanır.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Yeniden Başlat") { PocketRelaunch.relaunch() }
                    }
                }
            } header: { Text("Ayarlar") }

            Section {
                LabeledContent("Güç geçmişi") {
                    Button("Güç Geçmişini Temizle…", role: .destructive) { confirmClearHistory = true }
                        .disabled(model.powerHistory.isEmpty)
                }
                LabeledContent("Veri konumu") {
                    Button("Finder’da Göster", action: revealDataFolder)
                }
                Text("MacPocket tüm ölçümleri bu Mac’te tutar; veri göndermez.").font(.callout).foregroundStyle(.secondary)
            } header: { Text("Veriler") }
        }
        .formStyle(.grouped)
        .confirmationDialog("Tüm ayarlar sıfırlansın mı?", isPresented: $confirmReset) {
            Button("Ayarları Sıfırla", role: .destructive, action: resetSettings)
        } message: {
            Text("Görünüm, menü çubuğu, izleme ve pencere geçişi ayarları varsayılanlara döner. Dil seçimi ve güç geçmişi korunur.")
        }
        .confirmationDialog("Güç geçmişi temizlensin mi?", isPresented: $confirmClearHistory) {
            Button("Geçmişi Temizle", role: .destructive) {
                Task {
                    await model.clearPowerHistory()
                    message = model.powerHistoryError.map { PocketSettingsMessage(verbatim: $0, tone: .critical) }
                        ?? PocketSettingsMessage(key: "Güç geçmişi temizlendi.", tone: .success)
                }
            }
        } message: {
            Text("Kaydedilen pil ve güç olayları silinir. Bu işlem geri alınamaz.")
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "MacPocket Ayarları") + ".json"
        panel.prompt = String(localized: "Dışa Aktar")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try SettingsTransfer.exportData(from: SettingsTransfer.currentValues(.standard, domain: PocketDefaults.domain))
            try data.write(to: url, options: .atomic)
            message = PocketSettingsMessage(key: "Ayarlar dışa aktarıldı.", tone: .success)
        } catch {
            message = PocketSettingsMessage(verbatim: error.localizedDescription, tone: .critical)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "İçe Aktar")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try SettingsTransfer.importValues(from: Data(contentsOf: url))
            SettingsTransfer.apply(values, to: .standard, domain: PocketDefaults.domain)
            settingsDidChange()
            message = PocketSettingsMessage(key: "Ayarlar içe aktarıldı.", tone: .success)
        } catch {
            message = PocketSettingsMessage(verbatim: error.localizedDescription, tone: .critical)
        }
    }

    private func resetSettings() {
        SettingsTransfer.reset(.standard, domain: PocketDefaults.domain)
        settingsDidChange()
        message = PocketSettingsMessage(key: "Tüm ayarlar varsayılanlara döndü.", tone: .success)
    }

    /// Most settings follow UserDefaults live; these are read once and are refreshed here.
    private func settingsDidChange() {
        let interval = UserDefaults.standard.double(forKey: "MacPocket.refreshSeconds")
        model.refreshSeconds = [1.0, 2.0, 5.0, 10.0].contains(interval) ? interval : 2
        PocketDock.apply()
        needsRelaunch = true
    }

    private func revealDataFolder() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPocket", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.open(folder.deletingLastPathComponent())
        }
    }
}

private struct PocketSettingsMessage {
    let text: String
    let tone: PocketTone

    init(key: String.LocalizationValue, tone: PocketTone) {
        text = String(localized: key); self.tone = tone
    }

    init(verbatim: String, tone: PocketTone) {
        text = verbatim; self.tone = tone
    }
}

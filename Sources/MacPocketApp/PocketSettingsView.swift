import AppKit
import MacPocketCore
import SwiftUI

struct PocketSettingsView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var loginItem: LoginItemController
    @AppStorage("MacPocket.appearance") private var appearance = PocketAppearance.dark
    @AppStorage("MacPocket.showMenuBar") private var showMenuBar = true
    @AppStorage("MacPocket.menuBarCPU") private var menuBarCPU = true
    @AppStorage("manager.showUser") private var showUser = true
    @AppStorage("manager.showThreads") private var showThreads = true

    var body: some View {
        TabView {
            general.tabItem { Label("Genel", systemImage: "gearshape") }
            appearanceSettings.tabItem { Label("Görünüm", systemImage: "paintbrush") }
            monitoring.tabItem { Label("İzleme", systemImage: "waveform.path.ecg") }
        }
        .frame(width: 620, height: 440)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var general: some View {
        Form {
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
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            } header: { Text("Başlangıç") }
            Section {
                Toggle("Menü çubuğunda MacPocket’ı göster", isOn: $showMenuBar)
                Toggle("Menü çubuğunda CPU yüzdesini göster", isOn: $menuBarCPU)
                    .disabled(!showMenuBar)
                Text("Pencereyi kapattığında izleme menü çubuğunda sürer. Tamamen kapatmak için MacPocket > MacPocket’tan Çık’ı kullan.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Menü Çubuğu") }
        }.formStyle(.grouped)
    }

    private var appearanceSettings: some View {
        Form {
            Section {
                Picker("Görünüm", selection: $appearance) {
                    ForEach(PocketAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            } header: { Text("Tema") }
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
        }.formStyle(.grouped)
    }

    private var monitoring: some View {
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
                Toggle("Kullanıcı sütununu göster", isOn: $showUser)
                Toggle("İş parçacığı sütununu göster", isOn: $showThreads)
            } header: { Text("Görev Yöneticisi") }
        }.formStyle(.grouped)
    }

    private var loginItemDescription: String {
        switch loginItem.status {
        case .enabled: "macOS kaydı etkin. Sonraki oturum açılışında başlatılır."
        case .notRegistered: "Otomatik başlatma kapalı."
        case .requiresApproval: "Etkinleşmesi için macOS Giriş Öğeleri bölümünde onay gerekiyor."
        case .notFound: "macOS bu uygulamanın giriş kaydını bulamadı."
        case .unknown: "Otomatik başlatma durumu okunamadı."
        }
    }
}

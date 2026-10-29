import MacPocketCore
import SwiftUI

@MainActor
struct ToolsHubView: View {
    let sleepController: SleepController
    var openTool: (String) -> Void = { _ in }
    @AppStorage("MacPocket.tools.favorites") private var favorites = ""
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var category: HubCategory = .all
    @State private var favoritesOnly = false
    @State private var showAwake = false
    @State private var showDiagnostics = false
    @State private var awakeSession: AwakeSession?
    @State private var now = Date()
    @State private var duration: HubAwakeDuration = .hour
    @State private var customMinutes = "45"
    @State private var keepDisplayAwake = false
    @State private var changingAwake = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heading
                filters
                if let session = awakeSession, session.active {
                    activeAwakeBanner(session)
                }
                if visibleTools.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: favoritesOnly ? "star" : "magnifyingglass")
                            .font(.system(size: 28))
                        Text(favoritesOnly && favoriteIDs.isEmpty ? "Henüz favori eklemedin" : "Araç bulunamadı")
                            .font(.system(size: 16, weight: .medium))
                        Text(favoritesOnly && favoriteIDs.isEmpty
                             ? "Araç kutularındaki yıldızlarla kendi kısayollarını oluştur."
                             : "Aramayı veya kategori seçimini değiştirin.")
                            .font(.system(size: 12)).foregroundStyle(HubColors.secondary)
                        Button("Tüm Araçları Göster") {
                            search = ""
                            category = .all
                            favoritesOnly = false
                        }.buttonStyle(.bordered).padding(.top, 4)
                    }.frame(maxWidth: .infinity).padding(.vertical, 70)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)],
                              alignment: .leading, spacing: 18) {
                        ForEach(visibleCategories) { group in
                            categorySection(group)
                        }
                    }
                }
            }.padding(24)
        }
        .background(HubColors.background).foregroundStyle(HubColors.text)
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .task {
            while !Task.isCancelled {
                awakeSession = await sleepController.status()
                now = Date()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { break }
            }
        }
        .sheet(isPresented: $showAwake) { awakeSheet }
        .sheet(isPresented: $showDiagnostics) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Kapat") { showDiagnostics = false }.keyboardShortcut(.cancelAction)
                }.padding(12).background(HubColors.surface)
                SystemToolsView()
            }.frame(width: 1000, height: 680)
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("Tamam", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Tools").font(.system(size: 26, weight: .semibold))
                Text("Kategorilerine göre araçlarını bul, favorilerine hızlıca ulaş.")
                    .font(.system(size: 12)).foregroundStyle(HubColors.secondary)
            }
            Spacer()
            Text("\(HubTool.catalog.count) ARAÇ · \(HubCategory.groups.count) KATEGORİ")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1).foregroundStyle(HubColors.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(HubColors.surface, in: Capsule())
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HubColors.secondary)
                    TextField("Araç ara…", text: $search).textFieldStyle(.plain)
                        .accessibilityLabel("Araç ara").focused($searchFocused)
                }
                .padding(10).frame(maxWidth: 320)
                .background(HubColors.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(HubColors.border))
                Spacer(minLength: 0)
                Toggle(isOn: $favoritesOnly) {
                    Label("Favoriler", systemImage: "star")
                }
                .toggleStyle(.button).tint(HubColors.accent)
            }
            ScrollView(.horizontal) {
                Picker("Araç kategorisi", selection: $category) {
                    ForEach(HubCategory.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 4)
            }.scrollIndicators(.hidden)
        }
        .font(.system(size: 11))
    }

    private func categorySection(_ group: HubCategory) -> some View {
        let tools = visibleTools.filter { $0.category == group }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(group.rawValue, systemImage: group.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(tools.count)").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HubColors.secondary)
                    .accessibilityLabel("\(tools.count) araç")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142, maximum: 180), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(tools) { tool in toolCard(tool) }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(HubColors.group, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HubColors.border.opacity(0.7)))
    }

    private func toolCard(_ tool: HubTool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: tool.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tool.id == "keep-awake" ? HubColors.accent : HubColors.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button { toggleFavorite(tool.id) } label: {
                    Image(systemName: favoriteIDs.contains(tool.id) ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(favoriteIDs.contains(tool.id) ? HubColors.accent : HubColors.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(favoriteIDs.contains(tool.id) ? "Favorilerden çıkar" : "Favorilere ekle")
                .accessibilityLabel("\(tool.title): favori seçimini değiştir")
                .accessibilityValue(favoriteIDs.contains(tool.id) ? "Favori" : "Favori değil")
            }
            Text(tool.title).font(.system(size: 12, weight: .medium))
                .lineLimit(3).frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                .accessibilityHint(tool.description)
            HStack {
                if tool.id == "keep-awake" {
                    Label(awakeSession?.active == true ? "Etkin" : "Hazır",
                          systemImage: awakeSession?.active == true ? "circle.fill" : "checkmark.circle")
                        .foregroundStyle(HubColors.accent)
                    Spacer(minLength: 4)
                    Button(awakeSession?.active == true ? "Yönet" : "Aç") { showAwake = true }
                        .buttonStyle(.bordered).tint(HubColors.accent)
                        .accessibilityLabel("Mac'i Uyanık Tut: \(awakeSession?.active == true ? "Yönet" : "Aç")")
                } else if workingTools.contains(tool.id) {
                    Text(tool.id == "login-items" || tool.id == "background-items" ? "macOS" : "Kullanılabilir").foregroundStyle(HubColors.accent)
                    Spacer(minLength: 4)
                    Button("Aç") { openTool(tool.id) }.buttonStyle(.bordered)
                } else if tool.id == "maintenance" {
                    Text("Salt okunur").foregroundStyle(HubColors.secondary)
                    Spacer(minLength: 4)
                    Button("Raporlar") { showDiagnostics = true }.buttonStyle(.bordered)
                        .help("Mevcut salt okunur sistem raporlarını aç")
                } else {
                    Text(tool.integration ? "Entegrasyon gerekli" : "Hazırlanıyor")
                        .foregroundStyle(HubColors.secondary)
                    Spacer(minLength: 0)
                }
            }
            .font(.system(size: 9)).controlSize(.small)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(HubColors.surface, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            tool.id == "keep-awake" && awakeSession?.active == true ? HubColors.accent.opacity(0.7) : HubColors.border
        ))
        .help(tool.description)
    }

    private func activeAwakeBanner(_ session: AwakeSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 22))
            VStack(alignment: .leading, spacing: 5) {
                Text("Mac'in uyanık tutuluyor").font(.system(size: 13, weight: .semibold))
                Text("\(remainingTime(session)) · \(session.keepDisplayAwake ? "Ekran açık tutuluyor" : "Ekran normal davranır")")
                    .font(.system(size: 11)).foregroundStyle(HubColors.secondary)
            }
            Spacer()
            Button(changingAwake ? "Durduruluyor…" : "Durdur", action: stopAwake)
                .buttonStyle(.bordered).disabled(changingAwake)
        }
        .foregroundStyle(HubColors.accent)
        .padding(16).background(HubColors.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(HubColors.accent.opacity(0.3)))
    }

    private var awakeSheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Mac'i Uyanık Tut", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Mac'in otomatik uyumasını geçici olarak engelle.")
                        .font(.system(size: 12)).foregroundStyle(HubColors.secondary)
                }
                Spacer()
                Button { showAwake = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            Divider().overlay(HubColors.border)
            if let session = awakeSession, session.active {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Etkin oturum", systemImage: "circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(HubColors.accent)
                    Text(remainingTime(session)).font(.system(size: 22, weight: .medium, design: .monospaced))
                    Text(session.keepDisplayAwake ? "Ekran da açık tutuluyor." : "Ekranın kapanması engellenmiyor.")
                        .font(.system(size: 12)).foregroundStyle(HubColors.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(HubColors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                Button(changingAwake ? "Durduruluyor…" : "Oturumu Durdur", action: stopAwake)
                    .buttonStyle(.borderedProminent).tint(HubColors.accent)
                    .disabled(changingAwake)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Süre").font(.system(size: 12, weight: .semibold))
                    Picker("Süre", selection: $duration) {
                        ForEach(HubAwakeDuration.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    if duration == .custom {
                        HStack {
                            TextField("Dakika", text: $customMinutes).textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("dakika · 1–1440").font(.system(size: 11)).foregroundStyle(HubColors.secondary)
                        }
                    }
                    Toggle("Ekranı da açık tut", isOn: $keepDisplayAwake).toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
                .disabled(changingAwake)
                Text("Süre dolduğunda veya uygulama kapandığında uyanık tutma sona erer.")
                    .font(.system(size: 11)).foregroundStyle(HubColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Vazgeç") { showAwake = false }.buttonStyle(.bordered)
                    Button(changingAwake ? "Başlatılıyor…" : "Başlat", action: startAwake)
                        .buttonStyle(.borderedProminent).tint(HubColors.accent)
                        .disabled(changingAwake || !validDuration)
                }
            }
        }
        .padding(26).frame(width: 480)
        .background(HubColors.background).foregroundStyle(HubColors.text)
        .interactiveDismissDisabled(changingAwake)
    }

    private var workingTools: Set<String> {
        ["screen-cleaning", "similar-images", "app-leftovers", "mac-utilities", "time-machine", "launch-jobs", "listening-ports", "disk-info", "spotlight", "dns", "routes", "os-updates", "security", "permissions", "task-manager", "system-reports", "window-switcher", "uninstaller", "app-updater", "downloads", "duplicates", "large-old", "system-junk", "trash", "login-items", "background-items"]
    }

    private var favoriteIDs: Set<String> { Set(favorites.split(separator: ",").map(String.init)) }

    private var visibleTools: [HubTool] {
        HubTool.catalog.filter { tool in
            (category == .all || tool.category == category)
                && (!favoritesOnly || favoriteIDs.contains(tool.id))
                && (search.isEmpty || "\(tool.title) \(tool.description) \(tool.category.rawValue)"
                    .localizedCaseInsensitiveContains(search))
        }
    }

    private var visibleCategories: [HubCategory] {
        HubCategory.groups.filter { group in visibleTools.contains { $0.category == group } }
    }

    private var validDuration: Bool {
        guard duration == .custom else { return true }
        guard let minutes = Double(customMinutes.replacingOccurrences(of: ",", with: ".")) else { return false }
        return minutes.isFinite && (1...1440).contains(minutes)
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if !ids.insert(id).inserted { ids.remove(id) }
        favorites = ids.sorted().joined(separator: ",")
    }

    private func remainingTime(_ session: AwakeSession) -> String {
        guard let end = session.endsAt else { return "Sen durdurana kadar" }
        let total = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return String(format: "%02d:%02d:%02d kaldı", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func startAwake() {
        guard !changingAwake, validDuration else { return }
        let seconds = duration == .custom
            ? Double(customMinutes.replacingOccurrences(of: ",", with: ".")).map { $0 * 60 }
            : duration.seconds
        changingAwake = true
        Task { @MainActor in
            defer { changingAwake = false }
            do {
                awakeSession = try await sleepController.start(durationSeconds: seconds, keepDisplayAwake: keepDisplayAwake)
                now = Date()
            } catch { failure = error.localizedDescription }
        }
    }

    private func stopAwake() {
        guard !changingAwake else { return }
        changingAwake = true
        Task { @MainActor in
            defer { changingAwake = false }
            do {
                try await sleepController.stop()
                awakeSession = await sleepController.status()
                now = Date()
            } catch { failure = error.localizedDescription }
        }
    }
}

private enum HubCategory: String, CaseIterable, Identifiable {
    case all = "Tümü", productivity = "Üretkenlik", system = "Sistem ve Bakım"
    case applications = "Uygulamalar", files = "Dosyalar ve Disk"
    case privacy = "Gizlilik ve Güvenlik", online = "Çevrimiçi"
    var id: String { rawValue }
    static var groups: [HubCategory] { allCases.filter { $0 != .all } }
    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .productivity: "macwindow.on.rectangle"
        case .system: "wrench.and.screwdriver"
        case .applications: "app.dashed"
        case .files: "internaldrive"
        case .privacy: "lock.shield"
        case .online: "globe"
        }
    }
}

private enum HubAwakeDuration: String, CaseIterable, Identifiable {
    case quarter = "15 dakika", half = "30 dakika", hour = "1 saat", twoHours = "2 saat"
    case custom = "Özel süre", manual = "Ben durdurana kadar"
    var id: String { rawValue }
    var seconds: Double? {
        switch self {
        case .quarter: return 900
        case .half: return 1800
        case .hour: return 3600
        case .twoHours: return 7200
        case .custom, .manual: return nil
        }
    }
}

private struct HubTool: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let category: HubCategory
    var integration = false

    static let catalog: [HubTool] = [
        .init(id: "mac-utilities", title: "macOS Araçları", description: "Sistem raporları ve macOS ayarlarına hızlı erişim.", icon: "hammer", category: .system),
        .init(id: "launch-jobs", title: "Başlatma Görevleri", description: "Kullanıcı oturumunun launchd görevlerini incele.", icon: "list.bullet", category: .system),
        .init(id: "listening-ports", title: "Dinleyen Portlar", description: "Yerel sunucuları ve dinleyen ağ portlarını incele.", icon: "network", category: .system),
        .init(id: "disk-info", title: "Disk Bilgileri", description: "Dosya sistemi, disk özellikleri ve desteklenen sağlık verilerini oku.", icon: "internaldrive", category: .files),
        .init(id: "spotlight", title: "Spotlight Durumu", description: "Arama indekslemesinin sistemdeki durumunu incele.", icon: "magnifyingglass", category: .system),
        .init(id: "dns", title: "DNS Yapılandırması", description: "Sistemin etkin DNS çözümleyici yapılandırmasını incele.", icon: "globe", category: .system),
        .init(id: "routes", title: "Ağ Rotaları", description: "Etkin yönlendirme tablosunu incele.", icon: "arrow.triangle.branch", category: .system),
        .init(id: "os-updates", title: "macOS Güncellemeleri", description: "Yüklü sistem güncellemelerini incele ve sistem ayarlarına git.", icon: "arrow.down.circle", category: .system),
        .init(id: "security", title: "Sistem Güvenliği", description: "SIP ve Gatekeeper durumunu salt okunur olarak incele.", icon: "lock.shield", category: .privacy),
        .init(id: "task-manager", title: "Görev Yöneticisi", description: "Süreçleri ve kaynak kullanımını incele, seçtiğin uygulamayı sonlandır.", icon: "list.bullet.rectangle", category: .system),
        .init(id: "system-reports", title: "Sistem Raporları", description: "Bellek, ağ, açık dosyalar ve güç için salt okunur tanılar.", icon: "terminal", category: .system),
        .init(id: "keep-awake", title: "Mac'i Uyanık Tut", description: "Süreli veya sen durdurana kadar uyanık tut. Ekranı ayrıca açık tutabilirsin.", icon: "cup.and.saucer", category: .productivity),
        .init(id: "window-switcher", title: "Pencere Geçişi", description: "Açık pencereler arasında klavyeyle geçiş yap.", icon: "macwindow.on.rectangle", category: .productivity),
        .init(id: "app-leftovers", title: "Uygulama Kalıntıları", description: "Kaldırılan uygulamaların geride bıraktığı öğeleri bul.", icon: "square.dashed", category: .applications),
        .init(id: "app-updater", title: "Uygulama Güncelleme", description: "Kurulum kanalına göre uygulama güncellemelerini incele.", icon: "arrow.triangle.2.circlepath", category: .applications),
        .init(id: "permissions", title: "Uygulama İzinleri", description: "macOS Sistem Ayarlarını aç; Gizlilik ve Güvenlik bölümünden izinlerini yönet.", icon: "hand.raised", category: .privacy),
        .init(id: "background-items", title: "Arka Plan Öğeleri", description: "Arka planda çalışan görev ve yardımcıları yönet.", icon: "rectangle.stack", category: .applications),
        .init(id: "browser-care", title: "Tarayıcı Bakımı", description: "Tarayıcı sekmelerini kaynak kullanımlarıyla incele.", icon: "globe", category: .online, integration: true),
        .init(id: "downloads", title: "İndirilenler", description: "İndirilmiş dosyaları boyut ve tarihe göre ayıkla.", icon: "arrow.down.circle", category: .files),
        .init(id: "duplicates", title: "Yinelenen Dosyalar", description: "İçeriği aynı dosyaları karşılaştırarak alan kazan.", icon: "doc.on.doc", category: .files),
        .init(id: "email-cleanup", title: "E-posta Temizliği", description: "Bağlı e-posta hesabındaki gereksiz öğeleri düzenle.", icon: "envelope", category: .online, integration: true),
        .init(id: "large-old", title: "Büyük ve Eski Dosyalar", description: "Diskte yer kaplayan büyük ve eski dosyaları bul.", icon: "doc.badge.clock", category: .files),
        .init(id: "login-items", title: "Giriş Öğeleri", description: "Oturum açılışında başlayan uygulamaları incele.", icon: "power", category: .applications),
        .init(id: "mail-attachments", title: "Mail Ekleri", description: "Yerel e-posta eklerinin kapladığı alanı incele.", icon: "paperclip", category: .files),
        .init(id: "maintenance", title: "Bakım Görevleri", description: "Sistem raporlarını incele. Sistemi değiştiren bakım görevleri henüz hazır değil.", icon: "wrench.and.screwdriver", category: .system),
        .init(id: "malware", title: "Zararlı Yazılım Taraması", description: "Bir tespit motoruyla şüpheli dosya ve bulguları incele.", icon: "shield.lefthalf.filled", category: .privacy, integration: true),
        .init(id: "privacy", title: "Gizlilik İzleri", description: "Seçili etkinlik ve tarayıcı izlerini incele.", icon: "eye.slash", category: .privacy),
        .init(id: "screen-cleaning", title: "Ekran Temizleme Modu", description: "Ekranları kısa süre karart; MacPocket içindeki yanlış girişleri önle. Escape veya iki saniye basılı tutarak çık.", icon: "display", category: .productivity),
        .init(id: "similar-images", title: "Benzer Görseller", description: "Görsel benzerliği bulunan adayları yan yana karşılaştır.", icon: "photo.on.rectangle", category: .files),
        .init(id: "system-junk", title: "Sistem Gereksiz Dosyaları", description: "Önbellek ve log adaylarını kategorileriyle incele.", icon: "externaldrive.badge.minus", category: .system),
        .init(id: "time-machine", title: "Time Machine Anlık Görüntüleri", description: "Yerel snapshot listesini ve Time Machine durumunu incele.", icon: "clock.arrow.circlepath", category: .system),
        .init(id: "trash", title: "Çöp Kutuları", description: "Erişilebilen çöp konumlarını tek yerde incele.", icon: "trash", category: .files),
        .init(id: "uninstaller", title: "Tam Uygulama Kaldırma", description: "Uygulama ve ilişkili dosyalar için kaldırma planı oluştur.", icon: "app.badge", category: .applications),
    ]
}

private enum HubColors {
    static let background = PocketTheme.background
    static let group = PocketTheme.group
    static let surface = PocketTheme.panel
    static let border = PocketTheme.line
    static let text = Color.primary
    static let secondary = Color.secondary
    static let accent = PocketTheme.accent
}

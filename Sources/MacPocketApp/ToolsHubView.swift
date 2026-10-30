import MacPocketCore
import SwiftUI

@MainActor
struct ToolsHubView: View {
    @ObservedObject var model: PocketModel
    var openTool: (String) -> Void = { _ in }
    @AppStorage("MacPocket.tools.favorites") private var favorites = ""
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var category: HubCategory = .all
    @State private var favoritesOnly = false
    @State private var showAwake = false

    var body: some View {
        let tools = visibleTools
        let favoriteIDs = favoriteIDs
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.xl) {
                PocketPageHeading(title: "Araçlar",
                                  subtitle: "Kategorilerine göre araçlarını bul, favorilerine hızlıca ulaş.",
                                  icon: "square.grid.2x2") {
                    PocketStatusBadge(text: "\(HubTool.catalog.count) araç · \(HubCategory.groups.count) kategori" as LocalizedStringKey)
                }
                filters
                if let session = model.awakeSession, session.active {
                    activeAwakeBanner(session)
                }
                if let error = model.awakeError, !showAwake {
                    PocketMessage(error, error: true)
                }
                if tools.isEmpty {
                    emptyState(favoriteIDs: favoriteIDs)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: PocketSpacing.l, alignment: .top)],
                              alignment: .leading, spacing: PocketSpacing.l) {
                        ForEach(HubCategory.groups) { group in
                            let groupTools = tools.filter { $0.category == group }
                            if !groupTools.isEmpty {
                                categorySection(group, tools: groupTools, favoriteIDs: favoriteIDs)
                            }
                        }
                    }
                }
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .sheet(isPresented: $showAwake) { HubAwakeSheet(model: model) }
    }

    // MARK: - Sections

    private var filters: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Araç ara…", text: $search)
                    .frame(maxWidth: 320)
                    .focused($searchFocused)
                    .accessibilityLabel("Araç ara")
                Spacer(minLength: 0)
                Toggle(isOn: $favoritesOnly) {
                    Label("Favoriler", systemImage: favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .help("Yalnızca favori araçları göster")
            }
            GlassTabBar(tabs: HubCategory.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.icon, tint: $0.tint) },
                        selection: $category, tinted: false)
                .accessibilityLabel("Araç kategorisi")
        }
    }

    private func emptyState(favoriteIDs: Set<String>) -> some View {
        let noFavorites = favoritesOnly && favoriteIDs.isEmpty
        return ContentUnavailableView {
            Label(noFavorites ? "Henüz favori eklemedin" : "Araç bulunamadı",
                  systemImage: favoritesOnly ? "star" : "magnifyingglass")
        } description: {
            Text(noFavorites
                 ? "Araç kutularındaki yıldızlarla kendi kısayollarını oluştur."
                 : "Aramayı veya kategori seçimini değiştir.")
        } actions: {
            Button("Tüm Araçları Göster") {
                search = ""
                category = .all
                favoritesOnly = false
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PocketSpacing.xxl)
    }

    private func categorySection(_ group: HubCategory, tools: [HubTool], favoriteIDs: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader(group.title, icon: group.icon) {
                Text("\(tools.count)")
                    .monospacedDigit()
                    .accessibilityLabel("\(tools.count) araç")
            }
            .environment(\.pocketTint, group.tint)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: PocketSpacing.s)],
                      alignment: .leading, spacing: PocketSpacing.s) {
                ForEach(tools) { tool in
                    HubToolTile(tool: tool,
                                isFavorite: favoriteIDs.contains(tool.id),
                                status: status(for: tool),
                                highlighted: tool.id == "keep-awake" && model.awakeSession?.active == true,
                                open: { open(tool) },
                                toggleFavorite: { toggleFavorite(tool.id) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func activeAwakeBanner(_ session: AwakeSession) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.title2)
                .foregroundStyle(PocketTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text("Mac'in uyanık tutuluyor").font(.headline)
                HStack(spacing: PocketSpacing.xs) {
                    HubAwakeCountdown(session: session)
                    Text(session.keepDisplayAwake ? "· Ekran açık tutuluyor" : "· Ekran normal davranır")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: PocketSpacing.m)
            Button("Yönet") { showAwake = true }
            HubAwakeStopButton(model: model, title: "Durdur")
        }
        .padding(PocketSpacing.l)
        .background(PocketTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                .strokeBorder(PocketTheme.accent.opacity(0.3), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Data

    /// Stored favorites, minus tools that were removed from the catalog.
    private var favoriteIDs: Set<String> {
        Set(favorites.split(separator: ",").map(String.init)).intersection(HubTool.catalog.map(\.id))
    }

    private var visibleTools: [HubTool] {
        let favoriteIDs = favoriteIDs
        return HubTool.catalog.filter { tool in
            (category == .all || tool.category == category)
                && (!favoritesOnly || favoriteIDs.contains(tool.id))
                && (search.isEmpty || "\(tool.title) \(tool.description) \(tool.category.title)"
                    .localizedCaseInsensitiveContains(search))
        }
    }

    private func status(for tool: HubTool) -> HubToolTile.Status? {
        if tool.id == "keep-awake" {
            return model.awakeSession?.active == true
                ? .init(text: String(localized: "Etkin"), symbol: "circle.fill", tone: .accent)
                : nil
        }
        return nil
    }

    private func open(_ tool: HubTool) {
        if tool.id == "keep-awake" { showAwake = true } else { openTool(tool.id) }
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if !ids.insert(id).inserted { ids.remove(id) }
        favorites = ids.sorted().joined(separator: ",")
    }
}

// MARK: - Tile

/// A whole-card button with a secondary favorite control layered on top (never nested inside the button).
private struct HubToolTile: View {
    struct Status {
        let text: String
        let symbol: String
        let tone: PocketTone
    }

    let tool: HubTool
    let isFavorite: Bool
    let status: Status?
    let highlighted: Bool
    let open: () -> Void
    let toggleFavorite: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    PocketIconTile(symbol: tool.icon, tint: tool.category.tint, size: 34)
                    Text(tool.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(tool.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if let status {
                        PocketStatusBadge(text: status.text, systemImage: status.symbol, tone: status.tone)
                    }
                }
                .padding(PocketSpacing.m)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .contentShape(RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
            }
            .buttonStyle(HubTileButtonStyle(hovering: hovering, highlighted: highlighted))
            .accessibilityLabel(tool.title)
            .accessibilityHint(tool.description)
            .accessibilityValue(status?.text ?? "")

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.callout)
                    .foregroundStyle(isFavorite ? Color.yellow : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isFavorite || hovering ? 1 : 0.55)
            .padding(PocketSpacing.xs)
            .help(isFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
            .accessibilityLabel(isFavorite ? "\(tool.title): favorilerden çıkar" : "\(tool.title): favorilere ekle")
        }
        .onHover { hovering = $0 }
        .help(tool.description)
    }
}

private struct HubTileButtonStyle: ButtonStyle {
    let hovering: Bool
    let highlighted: Bool
    @PocketReduceMotion private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
        configuration.label
            .foregroundStyle(.primary)
            .background {
                shape.fill(hovering || configuration.isPressed
                           ? Color.primary.opacity(configuration.isPressed ? 0.1 : 0.05)
                           : Color.clear)
            }
            .background(PocketTheme.raised, in: shape)
            .overlay {
                shape.strokeBorder(highlighted ? PocketTheme.accent.opacity(0.7)
                                   : PocketTheme.line.opacity(hovering ? 1 : 0.6),
                                   lineWidth: highlighted ? 1 : 0.5)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Keep awake

/// Remaining time, re-rendered once per second without invalidating the whole page.
private struct HubAwakeCountdown: View {
    let session: AwakeSession

    var body: some View {
        if let end = session.endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.remaining(until: end, now: context.date)).monospacedDigit()
            }
        } else {
            Text("Sen durdurana kadar")
        }
    }

    static func remaining(until end: Date, now: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let time = String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        return String(localized: "\(time) kaldı")
    }
}

private struct HubAwakeStopButton: View {
    @ObservedObject var model: PocketModel
    let title: LocalizedStringKey
    var prominent = false
    @State private var stopping = false

    var body: some View {
        let button = Button(stopping ? "Durduruluyor…" : title) {
            guard !stopping else { return }
            stopping = true
            Task { @MainActor in
                await model.stopAwake()
                stopping = false
            }
        }
        .disabled(stopping)
        if prominent {
            button.buttonStyle(.pocketPrimary).keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}

private struct HubAwakeSheet: View {
    @ObservedObject var model: PocketModel
    @Environment(\.dismiss) private var dismiss
    @State private var duration: HubAwakeDuration = .hour
    @State private var customMinutes = "45"
    @State private var keepDisplayAwake = false
    @State private var starting = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Mac'i Uyanık Tut",
                              subtitle: "Mac'in otomatik uyumasını geçici olarak engelle.",
                              icon: "cup.and.saucer")
            Divider()
            if let session = model.awakeSession, session.active {
                activeSession(session)
            } else {
                options
            }
            if let error = model.awakeError {
                PocketMessage(error, error: true)
            }
            HStack {
                Spacer()
                if let session = model.awakeSession, session.active {
                    Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction)
                    HubAwakeStopButton(model: model, title: "Oturumu Durdur", prominent: true)
                } else {
                    Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(starting ? "Başlatılıyor…" : "Başlat", action: start)
                        .buttonStyle(.pocketPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(starting || !validDuration)
                }
            }
        }
        .padding(PocketSpacing.page)
        .frame(width: 480)
        .interactiveDismissDisabled(starting)
    }

    private func activeSession(_ session: AwakeSession) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketStatusBadge(text: "Etkin oturum" as LocalizedStringKey, systemImage: "circle.fill", tone: .accent)
            HubAwakeCountdown(session: session)
                .font(.system(.title2, design: .monospaced).weight(.medium))
            Text(session.keepDisplayAwake ? "Ekran da açık tutuluyor." : "Ekranın kapanması engellenmiyor.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Picker("Süre", selection: $duration) {
                ForEach(HubAwakeDuration.allCases) { Text($0.title).tag($0) }
            }
            if duration == .custom {
                HStack(spacing: PocketSpacing.s) {
                    TextField("Dakika", text: $customMinutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .accessibilityLabel("Özel süre, dakika")
                    Text("dakika · 1–1440")
                        .font(.callout)
                        .foregroundStyle(validDuration ? Color.secondary : Color.orange)
                }
            }
            Toggle("Ekranı da açık tut", isOn: $keepDisplayAwake)
                .toggleStyle(.checkbox)
            Text("Süre dolduğunda veya uygulama kapandığında uyanık tutma sona erer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(starting)
    }

    private var customSeconds: Double? {
        guard let minutes = Double(customMinutes.replacingOccurrences(of: ",", with: ".")),
              minutes.isFinite, (1...1440).contains(minutes) else { return nil }
        return minutes * 60
    }

    private var validDuration: Bool { duration != .custom || customSeconds != nil }

    private func start() {
        guard !starting, validDuration else { return }
        let seconds = duration == .custom ? customSeconds : duration.seconds
        let display = keepDisplayAwake
        starting = true
        Task { @MainActor in
            await model.startAwake(duration: seconds, display: display)
            starting = false
        }
    }
}

// MARK: - Catalog

private enum HubCategory: String, CaseIterable, Identifiable {
    case all = "Tümü", productivity = "Üretkenlik", system = "Sistem ve Bakım"
    case applications = "Uygulamalar", files = "Dosyalar ve Disk"
    case privacy = "Gizlilik ve Güvenlik"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: String(localized: "Tümü")
        case .productivity: String(localized: "Üretkenlik")
        case .system: String(localized: "Sistem ve Bakım")
        case .applications: String(localized: "Uygulamalar")
        case .files: String(localized: "Dosyalar ve Disk")
        case .privacy: String(localized: "Gizlilik ve Güvenlik")
        }
    }
    static var groups: [HubCategory] { allCases.filter { $0 != .all } }
    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .productivity: "macwindow.on.rectangle"
        case .system: "wrench.and.screwdriver"
        case .applications: "app.dashed"
        case .files: "internaldrive"
        case .privacy: "lock.shield"
        }
    }
    /// Category color shared by its section header and tool icons.
    var tint: Color {
        switch self {
        case .all: PocketTheme.brand
        case .productivity: PocketTheme.brand
        case .system: Color(hex: 0x00A6C8)
        case .applications: Color(hex: 0x7B5CFF)
        case .files: PocketTheme.disk
        case .privacy: Color(hex: 0xF0544F)
        }
    }
}

private enum HubAwakeDuration: String, CaseIterable, Identifiable {
    case quarter = "15 dakika", half = "30 dakika", hour = "1 saat", twoHours = "2 saat"
    case custom = "Özel süre", manual = "Ben durdurana kadar"
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .quarter: "15 dakika"
        case .half: "30 dakika"
        case .hour: "1 saat"
        case .twoHours: "2 saat"
        case .custom: "Özel süre"
        case .manual: "Ben durdurana kadar"
        }
    }
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

/// Every catalog entry opens a working tool; ids are routed by `PocketRootView.openCatalogTool`,
/// except "keep-awake", which this view presents itself.
private struct HubTool: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let category: HubCategory

    static let catalog: [HubTool] = [
        .init(id: "mac-utilities", title: String(localized: "macOS Araçları"), description: String(localized: "Sistem raporları ve macOS ayarlarına hızlı erişim."), icon: "hammer", category: .system),
        .init(id: "launch-jobs", title: String(localized: "Başlatma Görevleri"), description: String(localized: "Kullanıcı oturumunun launchd görevlerini incele."), icon: "list.bullet", category: .system),
        .init(id: "speed-test", title: String(localized: "Ağ Hız Testi"), description: String(localized: "İndirme, yükleme ve yanıt verme hızını macOS’un yerleşik aracıyla ölç; sonuçları karşılaştır."), icon: "speedometer", category: .system),
        .init(id: "listening-ports", title: String(localized: "Port Yöneticisi"), description: String(localized: "Hangi sürecin hangi portu dinlediğini ve ağa açık olup olmadığını gör; gerekirse durdur."), icon: "network", category: .system),
        .init(id: "disk-info", title: String(localized: "Disk Bilgileri"), description: String(localized: "Dosya sistemi, disk özellikleri ve desteklenen sağlık verilerini oku."), icon: "internaldrive", category: .files),
        .init(id: "spotlight", title: String(localized: "Spotlight Durumu"), description: String(localized: "Arama indekslemesinin sistemdeki durumunu incele."), icon: "magnifyingglass", category: .system),
        .init(id: "dns", title: String(localized: "DNS Yapılandırması"), description: String(localized: "Sistemin etkin DNS çözümleyici yapılandırmasını incele."), icon: "globe", category: .system),
        .init(id: "routes", title: String(localized: "Ağ Rotaları"), description: String(localized: "Etkin yönlendirme tablosunu incele."), icon: "arrow.triangle.branch", category: .system),
        .init(id: "os-updates", title: String(localized: "macOS Güncellemeleri"), description: String(localized: "Yüklü sistem güncellemelerini incele ve sistem ayarlarına git."), icon: "arrow.down.circle", category: .system),
        .init(id: "security", title: String(localized: "Sistem Güvenliği"), description: String(localized: "SIP ve Gatekeeper durumunu salt okunur olarak incele."), icon: "lock.shield", category: .privacy),
        .init(id: "task-manager", title: String(localized: "Görev Yöneticisi"), description: String(localized: "Süreçleri ve kaynak kullanımını incele, seçtiğin uygulamayı sonlandır."), icon: "list.bullet.rectangle", category: .system),
        .init(id: "hidden-settings", title: String(localized: "Gizli Ayarlar"), description: String(localized: "Sistem Ayarları’nda olmayan Dock, Finder, ekran görüntüsü ve klavye ayarlarını Terminal’e girmeden değiştir."), icon: "terminal", category: .system),
        .init(id: "system-reports", title: String(localized: "Sistem Raporları"), description: String(localized: "Bellek, ağ, açık dosyalar ve güç için salt okunur tanılar."), icon: "terminal", category: .system),
        .init(id: "keep-awake", title: String(localized: "Mac'i Uyanık Tut"), description: String(localized: "Süreli veya sen durdurana kadar uyanık tut. Ekranı ayrıca açık tutabilirsin."), icon: "cup.and.saucer", category: .productivity),
        .init(id: "quick-actions", title: String(localized: "Hızlı İşlemler"), description: String(localized: "Ekranı kilitle, Mac’i uyut, görünümü değiştir, diskleri çıkar, Çöp’ü boşalt: tek tıkla."), icon: "bolt.circle", category: .productivity),
        .init(id: "brightness", title: String(localized: "Ekran Parlaklığı"), description: String(localized: "Harici monitörleri klavyenin parlaklık tuşlarıyla ayarla: DDC ile gerçek arka ışık, desteklemeyen ekranlarda yazılımsal karartma."), icon: "sun.max.fill", category: .system),
        .init(id: "quit-guard", title: String(localized: "Kapatma Koruması"), description: String(localized: "⌘Q ve ⌘W yanlışlıkla basılınca uygulama kapanmasın: basılı tutma veya çift basış iste, uygulama bazında ayarla."), icon: "hand.raised.fill", category: .productivity),
        .init(id: "clipboard", title: String(localized: "Pano Geçmişi"), description: String(localized: "Kopyaladıklarını ara, sabitle, düz metin olarak yapıştır; bağlantılardaki izleme parametrelerini temizle."), icon: "doc.on.clipboard", category: .productivity),
        .init(id: "window-layout", title: String(localized: "Pencere Yerleşimi"), description: String(localized: "Pencereleri kısayollarla yarıya, çeyreğe, üçte bire veya başka ekrana yerleştir; aralığı ve kısayolları özelleştir."), icon: "rectangle.split.2x1", category: .productivity),
        .init(id: "window-switcher", title: String(localized: "Pencere Geçişi"), description: String(localized: "Açık pencereler arasında klavyeyle geçiş yap."), icon: "macwindow.on.rectangle", category: .productivity),
        .init(id: "app-leftovers", title: String(localized: "Uygulama Kalıntıları"), description: String(localized: "Kaldırılan uygulamaların geride bıraktığı öğeleri bul."), icon: "square.dashed", category: .applications),
        .init(id: "app-updater", title: String(localized: "Uygulama Güncelleme"), description: String(localized: "Kurulum kanalına göre uygulama güncellemelerini incele."), icon: "arrow.triangle.2.circlepath", category: .applications),
        .init(id: "downloads", title: String(localized: "İndirilenler"), description: String(localized: "İndirilmiş dosyaları boyut ve tarihe göre ayıkla."), icon: "arrow.down.circle", category: .files),
        .init(id: "duplicates", title: String(localized: "Yinelenen Dosyalar"), description: String(localized: "İçeriği aynı dosyaları karşılaştırarak alan kazan."), icon: "doc.on.doc", category: .files),
        .init(id: "large-old", title: String(localized: "Büyük ve Eski Dosyalar"), description: String(localized: "Diskte yer kaplayan büyük ve eski dosyaları bul."), icon: "doc.badge.clock", category: .files),
        .init(id: "screen-cleaning", title: String(localized: "Ekran Temizleme Modu"), description: String(localized: "Ekranları kısa süre karart; MacPocket içindeki yanlış girişleri önle. Escape veya iki saniye basılı tutarak çık."), icon: "display", category: .productivity),
        .init(id: "similar-images", title: String(localized: "Benzer Görseller"), description: String(localized: "Görsel benzerliği bulunan adayları yan yana karşılaştır."), icon: "photo.on.rectangle", category: .files),
        .init(id: "system-junk", title: String(localized: "Sistem Gereksiz Dosyaları"), description: String(localized: "Önbellek ve log adaylarını kategorileriyle incele."), icon: "externaldrive.badge.minus", category: .system),
        .init(id: "time-machine", title: String(localized: "Time Machine Anlık Görüntüleri"), description: String(localized: "Yerel snapshot listesini ve Time Machine durumunu incele."), icon: "clock.arrow.circlepath", category: .system),
        .init(id: "trash", title: String(localized: "Çöp Kutuları"), description: String(localized: "Erişilebilen çöp konumlarını tek yerde incele."), icon: "trash", category: .files),
        .init(id: "uninstaller", title: String(localized: "Tam Uygulama Kaldırma"), description: String(localized: "Uygulama ve ilişkili dosyalar için kaldırma planı oluştur."), icon: "app.badge", category: .applications),
    ]
}

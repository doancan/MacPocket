import MacPocketCore
import SwiftUI

@MainActor
struct ToolsHubView: View {
    var model: PocketModel
    var openTool: (String) -> Void = { _ in }
    @AppStorage("MacPocket.tools.favorites") private var favorites = ""
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var category: HubCategory = .all
    @State private var favoritesOnly = false

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
    }

    #if DEBUG
    static var diagnosticCatalogIDs: [String] { HubTool.catalog.map(\.id) }
    #endif

    // MARK: - Sections

    private var filters: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Araç ara…", text: $search, focus: $searchFocused)
                    .frame(maxWidth: 320)
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
                                open: { open(tool) },
                                toggleFavorite: { toggleFavorite(tool.id) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
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

    private func open(_ tool: HubTool) { openTool(tool.id) }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if !ids.insert(id).inserted { ids.remove(id) }
        favorites = ids.sorted().joined(separator: ",")
    }
}

// MARK: - Tile

/// A whole-card button with a secondary favorite control layered on top (never nested inside the button).
private struct HubToolTile: View {
    let tool: HubTool
    let isFavorite: Bool
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
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(tool.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(PocketSpacing.m)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .contentShape(RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
            }
            .buttonStyle(HubTileButtonStyle(hovering: hovering))
            .accessibilityLabel(tool.title)
            .accessibilityHint(tool.description)

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
                shape.strokeBorder(PocketTheme.line.opacity(hovering ? 1 : 0.6), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Catalog

enum HubCategory: String, CaseIterable, Identifiable {
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

/// Every catalog entry opens a working tool; ids are routed by `PocketModel.openCatalogTool`,

struct HubTool: Identifiable {
    let id: String
    private let titleResource: LocalizedStringResource
    private let descriptionResource: LocalizedStringResource
    var title: String { String(localized: titleResource) }
    var description: String { String(localized: descriptionResource) }
    var searchKeywords: String {
        var english = titleResource
        english.locale = Locale(identifier: "en")
        var turkish = titleResource
        turkish.locale = Locale(identifier: "tr")
        return String(localized: english) + " " + String(localized: turkish)
    }
    let icon: String
    let category: HubCategory

    init(id: String, title: LocalizedStringResource, description: LocalizedStringResource, icon: String, category: HubCategory) {
        self.id = id
        titleResource = title
        descriptionResource = description
        self.icon = icon
        self.category = category
    }

    static let catalog: [HubTool] = [
        .init(id: "cable-impact", title: "Kablo Etki Haritası", description: "Kabloyu çekmeden önce bağlı diskleri, ağ oturumlarını ve diğer kaynakları birlikte gör.", icon: "cable.connector", category: .system),
        .init(id: "menu-bar-organizer", title: "Menü Çubuğu Düzenleyici", description: "Diğer uygulamaların menü çubuğu simgelerini sırala, gizle ve yeniden aç.", icon: "menubar.rectangle", category: .productivity),
        .init(id: "update-center", title: "Güncelleme Merkezi", description: "Homebrew dışındaki uygulamaların güncellemelerini ve üretici kaynaklarını takip et.", icon: "arrow.triangle.2.circlepath", category: .system),
        .init(id: "internet-control", title: "İnternet Kontrolü", description: "Uygulamaların internet erişimi için izin ve engelleme kuralları oluştur.", icon: "network", category: .system),
        .init(id: "dock-preview", title: "Dock Önizlemeleri", description: "Dock simgesinde bekle; uygulamanın pencerelerini gör, seç ve yerleştir.", icon: "dock.rectangle", category: .productivity),
        .init(id: "shelf", title: "Dosya Rafı", description: "Dosya, metin ve bağlantıları topla; başka uygulamalara birlikte taşı.", icon: "tray.2", category: .productivity),
        .init(id: "command-bar", title: "Komut Çubuğu", description: "Araçlar, uygulamalar, pencereler, pano ve metin kısaltmaları tek aramada; kısayolla her yerden aç.", icon: "command", category: .productivity),
        .init(id: "mac-utilities", title: "macOS Araçları", description: "Time Machine, Spotlight, disk, DNS, ağ rotaları ve sistem güvenliği için salt okunur sistem sorguları.", icon: "hammer", category: .system),
        .init(id: "maintenance", title: "Bakım", description: "Önbellekleri sıfırla, başlangıç diskini doğrula, DNS’i temizle; yönetici gerektirenler tek parolayla çalışır.", icon: "wrench.and.screwdriver", category: .system),
        .init(id: "startup-items", title: "Başlangıç Öğeleri", description: "Oturum açılışında ve Mac başlarken kendiliğinden çalışan öğeleri, sahipleriyle ve durumlarıyla gör.", icon: "power", category: .system),
        .init(id: "speed-test", title: "Ağ Hız Testi", description: "İndirme, yükleme ve yanıt verme hızını macOS’un yerleşik aracıyla ölç; sonuçları karşılaştır.", icon: "speedometer", category: .system),
        .init(id: "network-traffic", title: "Ağ Trafiği", description: "Hangi uygulamanın şu an ne kadar indirip yüklediğini canlı gör; yardımcı süreçler uygulamada toplanır.", icon: "arrow.up.arrow.down.circle", category: .system),
        .init(id: "local-network", title: "Yerel Ağ", description: "Ağa bağlı cihazları adları, IP ve MAC adresleri ve türleriyle gör; yeni katılanları fark et.", icon: "network", category: .system),
        .init(id: "power-schedule", title: "Güç Zamanlaması", description: "Mac’in belirli saatlerde uyanmasını, açılmasını, uyumasını veya kapanmasını planla.", icon: "calendar.badge.clock", category: .system),
        .init(id: "wifi", title: "Wi-Fi Analizi", description: "Sinyal gücünü, paraziti ve çevredeki ağların kanal yoğunluğunu gör; modem için kanal önerisi al.", icon: "wifi", category: .system),
        .init(id: "screen-time", title: "Ekran Süresi", description: "Hangi uygulamada ne kadar zaman geçirdiğini gör; boşta ve kilitli süre sayılmaz, veriler bu Mac’te kalır.", icon: "hourglass", category: .productivity),
        .init(id: "hosts", title: "Hosts Dosyası", description: "Alan adlarını yönlendir veya engelle; satırları ve grupları tek tıkla aç/kapat.", icon: "list.bullet.rectangle.portrait", category: .system),
        .init(id: "peripherals", title: "USB ve Thunderbolt", description: "Takılı aygıtları, bağlantı hızlarını ve çektikleri gücü gör; yavaş kablo veya portu fark et.", icon: "cable.connector", category: .system),
        .init(id: "usb-eject", title: "USB Çıkarma Yöneticisi", description: "Harici diskleri güvenle çıkar; diski kullanan uygulamaları gör, seçili diskleri birlikte çıkar.", icon: "eject.circle", category: .files),
        .init(id: "listening-ports", title: "Port Yöneticisi", description: "Hangi sürecin hangi portu dinlediğini ve ağa açık olup olmadığını gör; gerekirse durdur.", icon: "network", category: .system),
        .init(id: "disk-health", title: "Disk Sağlığı", description: "SSD’nin yıpranmasını, yazılan veriyi, sıcaklığını ve hata sayaçlarını gör.", icon: "internaldrive.fill", category: .files),
        .init(id: "privacy-check", title: "Gizlilik Kontrolü", description: "Mikrofon ya da kamera kullanılmaya başladığında bildirim al; hangi uygulamanın dinlediğini gör.", icon: "eye.trianglebadge.exclamationmark", category: .privacy),
        .init(id: "task-manager", title: "Görev Yöneticisi", description: "Süreçleri ve kaynak kullanımını incele, seçtiğin uygulamayı sonlandır.", icon: "list.bullet.rectangle", category: .system),
        .init(id: "hidden-settings", title: "Gizli Ayarlar", description: "Sistem Ayarları’nda olmayan Dock, Finder, ekran görüntüsü ve klavye ayarlarını Terminal’e girmeden değiştir.", icon: "terminal", category: .system),
        .init(id: "support-report", title: "Destek Raporu", description: "Mac’in durumunu kişisel bilgileri gizleyerek tek tıkla paylaşılabilir bir rapora dök.", icon: "doc.text.below.ecg", category: .system),
        .init(id: "system-reports", title: "Sistem Raporları", description: "Bellek, ağ, açık dosyalar ve güç için salt okunur tanılar.", icon: "terminal", category: .system),
        .init(id: "freezer", title: "Uygulama Dondurucu", description: "Arka planda bekleyen uygulamaları dondurup işlemci ve pili koru; öne geldiklerinde anında çözülsünler.", icon: "snowflake", category: .system),
        .init(id: "displays", title: "Ekran Ayarları", description: "Çözünürlük, yenileme hızı, ana ekran ve yansıtma; gizli keskin HiDPI modları dahil, 15 sn onaylı.", icon: "display.2", category: .system),
        .init(id: "bluetooth-battery", title: "Bluetooth Pilleri", description: "Klavye, trackpad, fare (Logitech dahil) ve AirPods pillerini gör; azalınca bildirim al.", icon: "battery.75percent", category: .productivity),
        .init(id: "screenshot", title: "Ekran Görüntüsü", description: "Alan, pencere ya da tam ekran çek; önizlemeden kopyala, kaydet, sürükle; ok, vurgulayıcı, pikselleştirme ve metinle işaretle.", icon: "camera.viewfinder", category: .productivity),
        .init(id: "recorder", title: "Ekran Kaydı", description: "Ekranı sistem sesi ve mikrofonla birlikte kaydet; kısayolla başlat, glass göstergeyle durdur.", icon: "record.circle", category: .productivity),
        .init(id: "screen-grab", title: "Ekrandan Al", description: "Ekrandaki metni oku, QR kodunu çöz, rengi HEX/RGB/HSL/SwiftUI olarak al; hepsi bu Mac’te, kısayolla.", icon: "text.viewfinder", category: .productivity),
        .init(id: "mixer", title: "Ses Mikseri", description: "Her uygulamanın sesini ayrı ayarla, sustur ya da %150’ye kadar yükselt; sürücü gerekmez.", icon: "slider.vertical.3", category: .productivity),
        .init(id: "audio", title: "Ses Çıkışı", description: "Hoparlör, kulaklık ve monitör arasında kısayolla geç; kulaklık ayrılınca ses kendiliğinden kısılsın.", icon: "hifispeaker.2", category: .productivity),
        .init(id: "mouse-buttons", title: "Fare Tuşları", description: "Yan tuşlara ve yan tekere kısayol ata; uygulamaya özel profiller oluştur.", icon: "computermouse", category: .productivity),
        .init(id: "mouse-scroll", title: "Fare Kaydırma", description: "Fare tekerleğinin yönünü, hızını ve yumuşaklığını trackpad’den bağımsız ayarla.", icon: "computermouse", category: .productivity),
        .init(id: "snippets", title: "Metin Kısaltmaları", description: "Kısa bir kelime yaz, imzana, adresine ya da bugünün tarihine dönüşsün; her uygulamada.", icon: "text.badge.plus", category: .productivity),
        .init(id: "macros", title: "Makrolar", description: "Tekrarlanan işleri kaydet, düzenle ve kısayola bağla; uygulamaya özel tetikleyiciler, AppleScript, Kestirmeler ve komutlar.", icon: "wand.and.stars", category: .productivity),
        .init(id: "brightness", title: "Ekran Parlaklığı", description: "Harici monitörleri klavyenin parlaklık tuşlarıyla ayarla: DDC ile gerçek arka ışık, desteklemeyen ekranlarda yazılımsal karartma.", icon: "sun.max.fill", category: .system),
        .init(id: "focus", title: "Odak Oturumu", description: "Süre seç, odaklan: Mac uyanık kalır, masaüstü sadeleşir, diğer ekranlar kararır; bitince her şey geri döner.", icon: "scope", category: .productivity),
        .init(id: "quit-guard", title: "Kapatma Koruması", description: "⌘Q ve ⌘W yanlışlıkla basılınca uygulama kapanmasın: basılı tutma veya çift basış iste, uygulama bazında ayarla.", icon: "hand.raised.fill", category: .productivity),
        .init(id: "clipboard", title: "Pano Geçmişi", description: "Kopyaladıklarını ara, sabitle, düz metin olarak yapıştır; bağlantılardaki izleme parametrelerini temizle.", icon: "doc.on.clipboard", category: .productivity),
        .init(id: "workspaces", title: "Masa Düzenleri", description: "Açık pencerelerin yerleşimini adıyla kaydet, tek kısayolla geri getir; kapalı uygulamalar da açılsın.", icon: "rectangle.3.group", category: .productivity),
        .init(id: "window-layout", title: "Pencere Yerleşimi", description: "Pencereleri kısayollarla yarıya, çeyreğe, üçte bire veya başka ekrana yerleştir; aralığı ve kısayolları özelleştir.", icon: "rectangle.split.2x1", category: .productivity),
        .init(id: "window-switcher", title: "Pencere Geçişi", description: "Açık pencereler arasında klavyeyle geçiş yap.", icon: "macwindow.on.rectangle", category: .productivity),
        .init(id: "app-leftovers", title: "Uygulama Kalıntıları", description: "Kaldırılan uygulamaların geride bıraktığı öğeleri bul.", icon: "square.dashed", category: .applications),
        .init(id: "screen-cleaning", title: "Ekran Temizleme Modu", description: "Ekranları kısa süre karart; MacPocket içindeki yanlış girişleri önle. Escape veya iki saniye basılı tutarak çık.", icon: "display", category: .productivity),
        .init(id: "similar-images", title: "Benzer Görseller", description: "Görsel benzerliği bulunan adayları yan yana karşılaştır.", icon: "photo.on.rectangle", category: .files),
    ]
}

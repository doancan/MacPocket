import MacPocketCore
import AppKit
import SwiftUI

/// Raw values are stable identifiers (stored as the launch page); show `localizedTitle` instead.
enum PocketPage: String, CaseIterable, Identifiable, Hashable {
    case overview = "Genel Bakış", performance = "Sistem İzleme", power = "Güç Merkezi"
    case menuBar = "İstatistik Çubuğu"
    case cleanup = "Temizlik", storage = "Disk Analizi", applications = "Uygulamalar", tools = "Araçlar"
    case network = "Ağ Yönetimi"
    case ssh = "SSH Yöneticisi"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .performance: "waveform.path.ecg"
        case .power: "bolt.fill"
        case .cleanup: "sparkles"
        case .storage: "internaldrive.fill"
        case .applications: "app.badge.fill"
        case .tools: "wrench.and.screwdriver.fill"
        case .network: "network"
        case .ssh: "server.rack"
        case .menuBar: "menubar.rectangle"
        }
    }
}

/// Raw values are stable identifiers; show `localizedTitle` instead.
enum PocketTool: String, Identifiable {
    case similarImages = "Benzer Görseller", screenCleaning = "Ekran Temizleme"
    case practical = "Pratik Araçlar"
    case taskManager = "Görev Yöneticisi", diagnostics = "Sistem Raporları", windowSwitcher = "Pencere Geçişi"
    case hiddenSettings = "Gizli Ayarlar", clipboard = "Pano Geçmişi", windowLayout = "Pencere Yerleşimi"
    case quickActions = "Hızlı İşlemler"
    case quitGuard = "Kapatma Koruması", brightness = "Ekran Parlaklığı"
    case freezer = "Uygulama Dondurucu"
    case screenGrab = "Ekrandan Al"
    case mouseButtons = "Fare Tuşları"
    case mouseScroll = "Fare Kaydırma", audio = "Ses Çıkışı", mixer = "Ses Mikseri"
    case recorder = "Ekran Kaydı", screenshot = "Ekran Görüntüsü", bluetoothBattery = "Bluetooth Pilleri", displays = "Ekran Ayarları"
    case peripherals = "USB ve Thunderbolt", diskHealth = "Disk Sağlığı", systemData = "Disk Röntgeni"
    case powerSchedule = "Güç Zamanlaması"
    case startupItems = "Başlangıç Öğeleri", maintenance = "Bakım"
    case usbEject = "USB Çıkarma Yöneticisi"
    case commandBar = "Komut Çubuğu"
    case shelf = "Dosya Rafı"
    case menuBarOrganizer = "Menü Çubuğu Düzenleyici"
    case cableImpact = "Kablo Etki Haritası"
    case dockPreview = "Dock Önizlemeleri"
    var id: String { rawValue }
}

/// Navigation changes are independent of the live monitoring publisher.
@MainActor
final class PocketNavigation: ObservableObject {
    /// Starts on the page chosen in Settings → General, or where the person left off.
    @Published private(set) var page: PocketPage { didSet { rememberIfChanged(oldValue != page) } }
    @Published var tool: PocketTool? { didSet { rememberIfChanged(oldValue != tool) } }
    /// The module the Menü Çubuğu page selects when it next appears (e.g. from a tool page's "Menü Çubuğu
    /// Ayarları…").
    @Published var menuBarModule: MenuBarModule?
    /// The tab the Ağ Yönetimi page shows; kept while the person visits other pages.
    @Published var networkTab: NetworkTab { didSet { rememberIfChanged(oldValue != networkTab) } }

    init(launch: LaunchDestination = .atLaunch()) {
        page = launch.page
        tool = launch.tool
        networkTab = launch.networkTab ?? .diagnosis
    }

    private func rememberIfChanged(_ changed: Bool) {
        guard changed else { return }
        LaunchDestination(page: page, tool: tool, networkTab: networkTab).remember()
    }
    var title: String { page == .tools ? tool?.localizedTitle ?? page.localizedTitle : page.localizedTitle }
    func select(_ page: PocketPage) {
        guard self.page != page || tool != nil else { return }
        tool = nil
        self.page = page
    }
    func openMenuBar(module: MenuBarModule? = nil) {
        menuBarModule = module
        select(.menuBar)
    }
    func open(_ tab: NetworkTab) {
        networkTab = tab
        tool = nil
        page = .network
    }
    func open(_ tool: PocketTool) {
        page = .tools
        self.tool = tool
    }
}

@MainActor
final class PocketOperationState {
    static let shared = PocketOperationState()
    var preventTermination = false
}

/// Where the main window opens: a fixed page from Settings, or the page, tool and network tab last visited.
struct LaunchDestination: Equatable {
    var page: PocketPage
    var tool: PocketTool?
    var networkTab: NetworkTab?

    /// Stored in the launch page setting instead of a page name.
    static let lastVisitedSetting = "lastVisited"
    static let lastPageKey = "MacPocket.lastPage"
    static let lastToolKey = "MacPocket.lastTool"
    static let lastNetworkTabKey = "MacPocket.lastNetworkTab"

    static func atLaunch(from defaults: UserDefaults = .standard) -> LaunchDestination {
        let setting = defaults.string(forKey: PocketPreferenceKey.launchPage)
        guard setting == lastVisitedSetting else {
            return LaunchDestination(page: setting.flatMap(PocketPage.init(rawValue:)) ?? .overview)
        }
        // Pages and tools removed in later versions fall back to the overview.
        guard let page = defaults.string(forKey: lastPageKey).flatMap(PocketPage.init(rawValue:)) else {
            return LaunchDestination(page: .overview)
        }
        return LaunchDestination(page: page,
                                 tool: page == .tools ? defaults.string(forKey: lastToolKey).flatMap(PocketTool.init(rawValue:)) : nil,
                                 networkTab: defaults.string(forKey: lastNetworkTabKey).flatMap(NetworkTab.init(rawValue:)))
    }

    func remember(in defaults: UserDefaults = .standard) {
        defaults.set(page.rawValue, forKey: Self.lastPageKey)
        if let tool { defaults.set(tool.rawValue, forKey: Self.lastToolKey) } else { defaults.removeObject(forKey: Self.lastToolKey) }
        if let networkTab { defaults.set(networkTab.rawValue, forKey: Self.lastNetworkTabKey) }
    }
}

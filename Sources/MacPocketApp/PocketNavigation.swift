import AppKit
import SwiftUI

/// Raw values are stable identifiers (stored as the launch page); show `localizedTitle` instead.
enum PocketPage: String, CaseIterable, Identifiable, Hashable {
    case overview = "Genel Bakış", performance = "Sistem İzleme", power = "Güç Merkezi"
    case cleanup = "Temizlik", storage = "Disk Analizi", applications = "Uygulamalar", tools = "Araçlar"
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
        }
    }
}

/// Raw values are stable identifiers; show `localizedTitle` instead.
enum PocketTool: String, Identifiable {
    case similarImages = "Benzer Görseller", screenCleaning = "Ekran Temizleme"
    case utilities = "macOS Araçları", leftovers = "Uygulama Kalıntıları"
    case taskManager = "Görev Yöneticisi", diagnostics = "Sistem Raporları", windowSwitcher = "Pencere Geçişi"
    case hiddenSettings = "Gizli Ayarlar", clipboard = "Pano Geçmişi", windowLayout = "Pencere Yerleşimi"
    case speedTest = "Ağ Hız Testi", ports = "Port Yöneticisi", quickActions = "Hızlı İşlemler"
    case quitGuard = "Kapatma Koruması", brightness = "Ekran Parlaklığı", macros = "Makrolar"
    case freezer = "Uygulama Dondurucu", supportReport = "Destek Raporu", focus = "Odak Oturumu"
    case workspaces = "Masa Düzenleri", snippets = "Metin Kısaltmaları", screenGrab = "Ekrandan Al"
    case mouseScroll = "Fare Kaydırma", audio = "Ses Çıkışı", mixer = "Ses Mikseri"
    var id: String { rawValue }
}

/// Navigation changes are independent of the live monitoring publisher.
@MainActor
final class PocketNavigation: ObservableObject {
    /// Starts on the page chosen in Settings → General.
    @Published private(set) var page = PocketPage.launchPage
    @Published var tool: PocketTool?
    var title: String { page == .tools ? tool?.localizedTitle ?? page.localizedTitle : page.localizedTitle }
    func select(_ page: PocketPage) {
        guard self.page != page || tool != nil else { return }
        tool = nil
        self.page = page
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

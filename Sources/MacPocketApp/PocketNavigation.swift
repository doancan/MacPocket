import AppKit
import SwiftUI

enum PocketPage: String, CaseIterable, Identifiable, Hashable {
    case overview = "Genel Bakış", performance = "Sistem İzleme", power = "Güç Merkezi"
    case cleanup = "Temizlik", storage = "Disk Analizi", applications = "Uygulamalar", tools = "Tools"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .performance: "waveform.path.ecg"
        case .power: "battery.100percent.bolt"
        case .cleanup: "sparkles"
        case .storage: "internaldrive"
        case .applications: "app.badge"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

enum PocketTool: String, Identifiable {
    case similarImages = "Benzer Görseller", screenCleaning = "Ekran Temizleme"
    case utilities = "macOS Araçları", leftovers = "Uygulama Kalıntıları"
    case taskManager = "Görev Yöneticisi", diagnostics = "Sistem Raporları", windowSwitcher = "Pencere Geçişi"
    var id: String { rawValue }
}

/// Navigation changes are independent of the live monitoring publisher.
@MainActor
final class PocketNavigation: ObservableObject {
    @Published private(set) var page = PocketPage.overview
    @Published var tool: PocketTool?
    var title: String { page == .tools ? tool?.rawValue ?? page.rawValue : page.rawValue }
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

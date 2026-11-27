import AppIntents
import AppKit
import MacPocketCore

/// The pages Shortcuts, Spotlight and Siri can open. A separate enum (not `PocketPage`) so its identifiers
/// stay stable for saved shortcuts whatever the app renames.
enum PocketPageIntentValue: String, AppEnum {
    case overview, performance, power, menuBar, cleanup, storage, applications, tools, network, connectionDiagnosis, ssh

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "MacPocket Sayfası"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .overview: DisplayRepresentation(title: "Genel Bakış", image: .init(systemName: "square.grid.2x2.fill")),
        .performance: DisplayRepresentation(title: "Sistem İzleme", image: .init(systemName: "waveform.path.ecg")),
        .power: DisplayRepresentation(title: "Güç Merkezi", image: .init(systemName: "bolt.fill")),
        .menuBar: DisplayRepresentation(title: "İstatistik Çubuğu", image: .init(systemName: "menubar.rectangle")),
        .cleanup: DisplayRepresentation(title: "Temizlik", image: .init(systemName: "sparkles")),
        .storage: DisplayRepresentation(title: "Disk Analizi", image: .init(systemName: "internaldrive.fill")),
        .applications: DisplayRepresentation(title: "Uygulamalar", image: .init(systemName: "app.badge.fill")),
        .tools: DisplayRepresentation(title: "Araçlar", image: .init(systemName: "wrench.and.screwdriver.fill")),
        .network: DisplayRepresentation(title: "Ağ Yönetimi", image: .init(systemName: "network")),
        .connectionDiagnosis: DisplayRepresentation(title: "Bağlantı Tanılama", image: .init(systemName: "stethoscope")),
        .ssh: DisplayRepresentation(title: "SSH Yöneticisi", image: .init(systemName: "server.rack")),
    ]

    @MainActor func open(in navigation: PocketNavigation) {
        switch self {
        case .overview: navigation.select(.overview)
        case .performance: navigation.select(.performance)
        case .power: navigation.select(.power)
        case .menuBar: navigation.select(.menuBar)
        case .cleanup: navigation.select(.cleanup)
        case .storage: navigation.select(.storage)
        case .applications: navigation.select(.applications)
        case .tools: navigation.select(.tools)
        case .network: navigation.select(.network)
        case .connectionDiagnosis: navigation.open(NetworkTab.diagnosis)
        case .ssh: navigation.select(.ssh)
        }
    }
}

struct OpenPocketPageIntent: AppIntent {
    static let title: LocalizedStringResource = "MacPocket Sayfası Aç"
    static let description = IntentDescription("MacPocket’i seçilen sayfada açar.")
    static let openAppWhenRun = true

    @Parameter(title: "Sayfa", default: .overview)
    var page: PocketPageIntentValue

    static var parameterSummary: some ParameterSummary { Summary("\(\.$page) sayfasını aç") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = PocketApplicationState.shared.model
        page.open(in: model.navigation)
        model.openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
        return .result()
    }
}

/// Runs the same measurement as Ağ Yönetimi › Tanılama and answers in one sentence, without opening the app.
struct DiagnoseConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Bağlantıyı Tanıla"
    static let description = IntentDescription("Modemi, interneti ve DNS’i ölçer; sorunun nerede olduğunu söyler. Modeme ve 1.1.1.1’e üçer ping gönderir.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = ConnectionDiagnosisModel.shared
        await model.run()
        guard let measurement = model.measurement else {
            return .result(value: ConnectionVerdict.noLink.rawValue, dialog: "Bağlantı ölçülemedi.")
        }
        let verdict = ConnectionDiagnosis.verdict(measurement)
        let latency = measurement.internet.milliseconds.map { " · " + String(localized: "İnternet \(Int($0.rounded())) ms") } ?? ""
        return .result(value: verdict.rawValue, dialog: IntentDialog(stringLiteral: verdict.spokenSummary + latency))
    }
}

extension ConnectionVerdict {
    /// Plain-string form of `title` for dialogs and notifications.
    var spokenSummary: String {
        switch self {
        case .healthy: String(localized: "Bağlantı sağlıklı")
        case .noLink: String(localized: "Ağa bağlı değilsin")
        case .routerUnreachable: String(localized: "Modeme ulaşılamıyor")
        case .noInternet: String(localized: "Modem çalışıyor, internet yok")
        case .dnsFailing: String(localized: "İnternet var, alan adları çözülemiyor")
        case .weakWiFi: String(localized: "Wi-Fi sinyali zayıf")
        case .slow: String(localized: "Bağlantı yavaş")
        }
    }
}

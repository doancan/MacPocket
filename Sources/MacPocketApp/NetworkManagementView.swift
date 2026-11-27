import MacPocketCore
import SwiftUI

/// One tool of the Ağ Yönetimi page. Raw values are the catalog ids the Command Bar and deep links use.
enum NetworkTab: String, CaseIterable, Identifiable {
    case diagnosis = "connection-diagnosis"
    case traffic = "network-traffic"
    case wifi
    case localNetwork = "local-network"
    case speedTest = "speed-test"
    case ports = "listening-ports"
    case hosts
    case internetControl = "internet-control"

    var id: String { rawValue }

    /// Short label for the tab bar; the tool's own heading carries the full name.
    var tabTitle: String {
        switch self {
        case .diagnosis: String(localized: "Tanılama")
        case .traffic: String(localized: "Trafik")
        case .wifi: String(localized: "Wi-Fi")
        case .localNetwork: String(localized: "Yerel Ağ")
        case .speedTest: String(localized: "Hız Testi")
        case .ports: String(localized: "Portlar")
        case .hosts: String(localized: "Hosts")
        case .internetControl: String(localized: "Erişim")
        }
    }

    var title: String {
        switch self {
        case .diagnosis: String(localized: "Bağlantı Tanılama")
        case .traffic: String(localized: "Ağ Trafiği")
        case .wifi: String(localized: "Wi-Fi Analizi")
        case .localNetwork: String(localized: "Yerel Ağ")
        case .speedTest: String(localized: "Ağ Hız Testi")
        case .ports: String(localized: "Port Yöneticisi")
        case .hosts: String(localized: "Hosts Dosyası")
        case .internetControl: String(localized: "İnternet Kontrolü")
        }
    }

    var detail: String {
        switch self {
        case .diagnosis: String(localized: "Sorun Wi-Fi’de mi, modemde mi, internette mi, DNS’te mi? Tek tıkla öğren; kesintileri kaydet.")
        case .traffic: String(localized: "Hangi uygulamanın şu an ne kadar indirip yüklediğini canlı gör.")
        case .wifi: String(localized: "Sinyal, parazit ve çevredeki ağların kanal yoğunluğu; modem için kanal önerisi.")
        case .localNetwork: String(localized: "Ağa bağlı cihazları adları, IP ve MAC adresleriyle gör.")
        case .speedTest: String(localized: "İndirme, yükleme ve yanıt verme hızını ölç.")
        case .ports: String(localized: "Hangi sürecin hangi portu dinlediğini gör, gerekirse durdur.")
        case .hosts: String(localized: "Alan adlarını yönlendir veya engelle.")
        case .internetControl: String(localized: "Uygulamaların internet erişimi için izin ve engelleme kuralları.")
        }
    }

    var symbol: String {
        switch self {
        case .diagnosis: "stethoscope"
        case .traffic: "arrow.up.arrow.down"
        case .wifi: "wifi"
        case .localNetwork: "point.3.connected.trianglepath.dotted"
        case .speedTest: "speedometer"
        case .ports: "door.left.hand.open"
        case .hosts: "list.bullet.rectangle.portrait"
        case .internetControl: "hand.raised"
        }
    }
}

/// Ağ Yönetimi: every network and internet tool behind one tab bar. Only the selected tool's view exists, so
/// the others' scanners and timers stay idle.
struct NetworkManagementView: View {
    let model: PocketModel
    @ObservedObject private var navigation: PocketNavigation

    init(model: PocketModel) {
        self.model = model
        navigation = model.navigation
    }

    var body: some View {
        // Each tool draws its own heading (title, actions); the Ağ sections appear in the standard place
        // under it.
        tool
            .id(navigation.networkTab)
            .pocketPageSections(NetworkTab.allCases.map { GlassTab(id: $0, title: $0.tabTitle, symbol: $0.symbol) },
                                selection: $navigation.networkTab, label: "Ağ aracı")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var tool: some View {
        switch navigation.networkTab {
        case .diagnosis: ConnectionDiagnosisView()
        case .traffic: NetworkTrafficView()
        case .wifi: WiFiView()
        case .localNetwork: LANScannerView()
        case .speedTest: SpeedTestView()
        case .ports: PortManagerView(model: model)
        case .hosts: HostsView()
        case .internetControl: InternetControlView()
        }
    }
}

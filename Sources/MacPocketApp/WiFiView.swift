import Charts
import CoreLocation
import CoreWLAN
import MacPocketCore
import SwiftUI

/// The joined network as CoreWLAN reports it. Name and BSSID are nil without Location access.
struct WiFiLink: Equatable, Sendable {
    var interfaceName: String?
    var powerOn: Bool
    var ssid: String?
    var bssid: String?
    var rssi: Int
    var noise: Int
    var transmitRate: Double
    var channel: Int?
    var band: WiFiBand?
    var widthMHz: Int
    var standard: String?
    var security: String?
    var countryCode: String?
    var hardwareAddress: String?

    var isAssociated: Bool { powerOn && channel != nil && rssi != 0 }

    var observation: WiFiNetworkObservation? {
        guard let channel, let band else { return nil }
        return WiFiNetworkObservation(ssid: ssid, bssid: bssid, rssi: rssi, channel: channel, band: band, widthMHz: widthMHz)
    }
}

struct WiFiScannedNetwork: Identifiable, Equatable, Sendable {
    let id: String
    let observation: WiFiNetworkObservation
    let security: String?
    let standard: String?
}

enum WiFiReader {
    static func link() -> WiFiLink? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let channel = interface.wlanChannel()
        return WiFiLink(interfaceName: interface.interfaceName, powerOn: interface.powerOn(), ssid: interface.ssid(),
                        bssid: interface.bssid(), rssi: interface.rssiValue(), noise: interface.noiseMeasurement(),
                        transmitRate: interface.transmitRate(), channel: channel?.channelNumber,
                        band: channel.flatMap { band($0.channelBand) }, widthMHz: channel.map { width($0.channelWidth) } ?? 20,
                        standard: standard(interface.activePHYMode()), security: security(interface.security()),
                        countryCode: interface.countryCode(), hardwareAddress: interface.hardwareAddress())
    }

    /// Blocks for a few seconds while the radio listens on every channel.
    static func scan() throws -> [WiFiScannedNetwork] {
        guard let interface = CWWiFiClient.shared().interface() else { return [] }
        return try interface.scanForNetworks(withSSID: nil).enumerated().compactMap { index, network in
            guard let channel = network.wlanChannel, let band = band(channel.channelBand) else { return nil }
            return WiFiScannedNetwork(id: network.bssid ?? "\(index)", observation: WiFiNetworkObservation(
                ssid: network.ssid, bssid: network.bssid, rssi: network.rssiValue, channel: channel.channelNumber,
                band: band, widthMHz: width(channel.channelWidth)),
                security: strongestSecurity(network), standard: newestStandard(network))
        }
    }

    /// A network advertises every mode it accepts; show the best one.
    static func strongestSecurity(_ network: CWNetwork) -> String? {
        let order: [CWSecurity] = [.wpa3Enterprise, .wpa3Personal, .wpa3Transition, .wpa2Enterprise, .enterprise,
                                   .wpa2Personal, .personal, .wpaEnterprise, .wpaEnterpriseMixed, .wpaPersonal,
                                   .wpaPersonalMixed, .OWE, .oweTransition, .dynamicWEP, .WEP, .none]
        return order.first(where: network.supportsSecurity).flatMap(security)
    }

    static func newestStandard(_ network: CWNetwork) -> String? {
        let order: [CWPHYMode] = [.mode11be, .mode11ax, .mode11ac, .mode11n, .mode11g, .mode11a, .mode11b]
        return order.first(where: network.supportsPHYMode).flatMap(standard)
    }

    static func band(_ band: CWChannelBand) -> WiFiBand? {
        switch band {
        case .band2GHz: .ghz2_4
        case .band5GHz: .ghz5
        case .band6GHz: .ghz6
        default: nil
        }
    }

    static func width(_ width: CWChannelWidth) -> Int {
        switch width {
        case .width40MHz: 40
        case .width80MHz: 80
        case .width160MHz: 160
        default: 20
        }
    }

    static func standard(_ mode: CWPHYMode) -> String? {
        switch mode {
        case .mode11a: "802.11a"
        case .mode11b: "802.11b"
        case .mode11g: "802.11g"
        case .mode11n: String(localized: "Wi-Fi 4 (802.11n)")
        case .mode11ac: String(localized: "Wi-Fi 5 (802.11ac)")
        case .mode11ax: String(localized: "Wi-Fi 6 (802.11ax)")
        case .mode11be: String(localized: "Wi-Fi 7 (802.11be)")
        default: nil
        }
    }

    static func security(_ security: CWSecurity) -> String? {
        switch security {
        case .none: String(localized: "Açık (şifresiz)")
        case .WEP, .dynamicWEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA"
        case .wpa2Personal, .personal: "WPA2"
        case .wpa3Personal: "WPA3"
        case .wpa3Transition: "WPA2/WPA3"
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise: String(localized: "WPA2 Kurumsal")
        case .wpa3Enterprise: String(localized: "WPA3 Kurumsal")
        case .OWE, .oweTransition: "OWE"
        default: nil
        }
    }
}

@MainActor
final class WiFiModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var link: WiFiLink?
    @Published private(set) var history: [Double] = []
    @Published private(set) var networks: [WiFiScannedNetwork] = []
    @Published private(set) var scanning = false
    @Published private(set) var scannedAt: Date?
    @Published private(set) var scanError: String?
    @Published private(set) var loaded = false
    @Published private(set) var authorization: CLAuthorizationStatus

    static let interval = Duration.seconds(2)
    static let historyLength = 90
    static let autoScanInterval: TimeInterval = 30
    @Published var autoScan = false {
        didSet { UserDefaults.standard.set(autoScan, forKey: "MacPocket.wifi.autoScan") }
    }
    private let location = CLLocationManager()

    override init() {
        authorization = location.authorizationStatus
        super.init()
        location.delegate = self
        autoScan = UserDefaults.standard.bool(forKey: "MacPocket.wifi.autoScan")
    }

    var canShowNames: Bool { authorization == .authorizedAlways }

    func run() async {
        Task { await scan() }
        while !Task.isCancelled {
            let link = await Task.detached(priority: .utility) { WiFiReader.link() }.value
            self.link = link
            if let link, link.isAssociated {
                history.append(Double(link.rssi))
                if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
            }
            loaded = true
            if autoScan, !scanning, Date().timeIntervalSince(scannedAt ?? .distantPast) >= Self.autoScanInterval {
                Task { await scan() }
            }
            try? await Task.sleep(for: Self.interval)
        }
    }

    /// Relation of a scanned network to the joined one.
    func relation(_ network: WiFiNetworkObservation) -> WiFiRelation? {
        guard let own = link?.bssid, let bssid = network.bssid else { return nil }
        if bssid == own { return .connected }
        return WiFiAnalysis.sameRadio(bssid, own) ? .sameRouter : nil
    }

    func scan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        do {
            networks = try await Task.detached(priority: .userInitiated) { try WiFiReader.scan() }.value
                .sorted { $0.observation.rssi > $1.observation.rssi }
            scannedAt = Date()
            scanError = nil
        } catch {
            scanError = error.localizedDescription
        }
    }

    func requestNames() {
        if authorization == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    var advice: WiFiChannelAdvice? {
        guard let current = link?.observation, !networks.isEmpty else { return nil }
        return WiFiAnalysis.advice(networks: networks.map(\.observation), current: current)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let gained = status == .authorizedAlways && self.authorization != .authorizedAlways
            self.authorization = status
            if gained { await self.scan() }
        }
    }
}

enum WiFiRelation { case connected, sameRouter }

enum WiFiSort: String, CaseIterable, Identifiable {
    case signal, name, channel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .signal: String(localized: "Sinyal")
        case .name: String(localized: "Ad")
        case .channel: String(localized: "Kanal")
        }
    }
}

struct WiFiView: View {
    @StateObject private var model = WiFiModel()
    @State private var band: WiFiBand?

    @State private var listBand: WiFiBand?
    @State private var sort = WiFiSort.signal
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Wi-Fi Analizi",
                              subtitle: "Sinyal gücü, parazit ve çevredeki ağların kanal yoğunluğu; modem için kanal önerisi.",
                              icon: "wifi") {
                Button { Task { await model.scan() } } label: {
                    Label(model.scanning ? "Taranıyor…" : "Yeniden tara", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(model.scanning)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if !model.canShowNames {
                        HStack(spacing: PocketSpacing.m) {
                            PocketMessage("macOS, ağ adlarını ve BSSID’leri yalnız konum izni olan uygulamalara gösterir. İzin vermeden de sinyal ve kanal analizi çalışır.",
                                          tone: .neutral)
                            Button(model.authorization == .notDetermined ? "Ağ adlarını göster" : "Konum ayarlarını aç") { model.requestNames() }
                        }
                    }
                    if let error = model.scanError { PocketMessage(error, tone: .warning) }
                    if let link = model.link, link.isAssociated {
                        connection(link)
                        adviceCard
                    } else {
                        ContentUnavailableView(model.loaded ? (model.link?.powerOn == false ? "Wi-Fi kapalı" : "Bir Wi-Fi ağına bağlı değil")
                                                            : "Okunuyor…",
                                               systemImage: "wifi.slash",
                                               description: Text(model.loaded ? "Analiz için bir Wi-Fi ağına bağlan." : ""))
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .pocketCard()
                    }
                    if !model.networks.isEmpty || model.link?.isAssociated == true {
                        channels
                        nearby
                    }
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .task { await model.run() }
    }

    private func connection(_ link: WiFiLink) -> some View {
        let quality = WiFiSignalQuality(rssi: link.rssi)
        return VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(alignment: .center, spacing: PocketSpacing.m) {
                Image(systemName: "wifi").font(.title2).foregroundStyle(color(quality))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: link.ssid ?? String(localized: "Bağlı ağ")).font(.headline)
                    Text(verbatim: [link.interfaceName, link.standard, link.security].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PocketStatusBadge(text: quality.title, systemImage: "cellularbars", tone: tone(quality))
            }
            HStack(alignment: .center, spacing: PocketSpacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sinyal").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(link.rssi) dBm").font(.largeTitle.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    if let stats = historyStats {
                        Text(String(localized: "Son \(stats.minutes) dk · en düşük \(stats.min) · ort. \(stats.average) · en yüksek \(stats.max) dBm"))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .fixedSize()
                PocketSparkline(values: model.history, color: color(quality), ceiling: -20, floor: -100)
                    .frame(height: 70)
            }
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: PocketSpacing.m)], alignment: .leading,
                      spacing: PocketSpacing.m) {
                metric("Gürültü", "\(link.noise) dBm", symbol: "waveform")
                metric("Sinyal/gürültü (SNR)", "\(link.rssi - link.noise) dB", symbol: "chart.line.uptrend.xyaxis",
                       tint: link.rssi - link.noise < 25 ? .orange : .secondary)
                metric("Bağlantı hızı", "\(Int(link.transmitRate)) Mb/s", symbol: "speedometer")
                metric("Kanal", channelText(link), symbol: "dot.radiowaves.left.and.right")
                metric("BSSID (modem)", link.bssid ?? "—", symbol: "antenna.radiowaves.left.and.right")
                metric("Bu Mac’in adresi", link.hardwareAddress ?? "—", symbol: "desktopcomputer")
                if let country = link.countryCode { metric("Ülke kodu", country, symbol: "globe") }
            }
            Text("−55 dBm ve üstü mükemmel, −65’e kadar iyi, −75’e kadar orta sayılır. SNR 25 dB’nin altına düşerse bağlantı kararsızlaşabilir.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .pocketCard()
    }

    private var historyStats: (minutes: Int, min: Int, average: Int, max: Int)? {
        let values = model.history
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return nil }
        let seconds = Double(values.count) * Double(WiFiModel.interval.components.seconds)
        return (max(1, Int((seconds / 60).rounded())), Int(low), Int((values.reduce(0, +) / Double(values.count)).rounded()), Int(high))
    }

    @ViewBuilder private var adviceCard: some View {
        if let advice = model.advice {
            if advice.shouldSwitch {
                PocketMessage(String(localized: "\(advice.band.title) bandında kanal \(advice.current) kalabalık. Modem/router ayarlarından kanal \(advice.recommended) seçmek paraziti azaltabilir."),
                              tone: .warning)
            } else {
                PocketMessage(String(localized: "Kanal \(advice.current), \(advice.band.title) bandındaki en sakin kanallardan biri; değiştirmen gerekmiyor."),
                              tone: .success)
            }
        }
    }

    private var bands: [WiFiBand] {
        Array(Set(model.networks.map(\.observation.band)).union(model.link?.band.map { [$0] } ?? [])).sorted()
    }

    private var selectedBand: WiFiBand? { band ?? model.link?.band ?? bands.first }

    @ViewBuilder private var channels: some View {
        if let selected = selectedBand {
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Kanal yoğunluğu", icon: "chart.bar") {
                    if bands.count > 1 {
                        Picker("Bant", selection: Binding(get: { selected }, set: { band = $0 })) {
                            ForEach(bands, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    }
                }
                let loads = WiFiAnalysis.channelLoads(model.networks.map(\.observation), band: selected)
                Chart(loads) { load in
                    BarMark(x: .value(Text("Kanal"), String(load.channel)), y: .value(Text("Yoğunluk"), load.load))
                        .foregroundStyle(load.channel == model.link?.channel && selected == model.link?.band
                                         ? Color.accentColor : Color.secondary.opacity(0.5))
                        .annotation(position: .top) {
                            if load.networks > 0 { Text(verbatim: "\(load.networks)").font(.caption2).foregroundStyle(.secondary) }
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 140)
                Text("Çubuk, o kanalı kullanan ya da ona taşan ağların ne kadar güçlü duyulduğunu gösterir; üstteki sayı yayın yapan cihaz sayısıdır (bir cihazın birden çok ağı bir kez sayılır). Vurgulu çubuk senin kanalın; aynı modemin yayınladığı ek ağlar (misafir ağı gibi) hesaba katılmaz, ayrı cihazlar katılır. Yalnız çakışmayan ve radar beklemesi (DFS) olmayan kanallar gösterilir.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .pocketCard()
        }
    }

    private var listedNetworks: [WiFiScannedNetwork] {
        model.networks
            .filter { listBand == nil || $0.observation.band == listBand }
            .filter { network in
                search.isEmpty || (network.observation.ssid?.localizedCaseInsensitiveContains(search) ?? false)
                    || (network.observation.bssid?.localizedCaseInsensitiveContains(search) ?? false)
                    || String(network.observation.channel) == search
            }
            .sorted { lhs, rhs in
                let a = lhs.observation, b = rhs.observation
                switch sort {
                case .signal: return a.rssi > b.rssi
                case .name: return (a.ssid ?? "\u{10FFFF}").localizedStandardCompare(b.ssid ?? "\u{10FFFF}") == .orderedAscending
                case .channel: return a.band != b.band ? a.band < b.band : a.channel != b.channel ? a.channel < b.channel : a.rssi > b.rssi
                }
            }
    }

    private var nearby: some View {
        let visible = listedNetworks
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Çevredeki ağlar", icon: "antenna.radiowaves.left.and.right") {
                if let at = model.scannedAt {
                    Text("\(model.networks.count) ağ · \(at.formatted(date: .omitted, time: .shortened))")
                }
            }
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Ad, BSSID veya kanal ara…", text: $search, focus: $searchFocused).frame(maxWidth: 260)
                Picker("Bant", selection: $listBand) {
                    Text("Tümü").tag(WiFiBand?.none)
                    ForEach(bands, id: \.self) { Text(verbatim: $0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("Sırala", selection: $sort) {
                    ForEach(WiFiSort.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .fixedSize()
                Spacer(minLength: 0)
                Toggle(String(localized: "\(Int(WiFiModel.autoScanInterval)) sn’de bir tara"), isOn: $model.autoScan)
                    .toggleStyle(.checkbox)
            }
            if visible.isEmpty {
                Text(model.scanning ? "Taranıyor…" : "Ağ bulunamadı.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    WiFiNetworkHeader()
                    Divider()
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, network in
                        if index > 0 { Divider() }
                        WiFiNetworkRow(network: network, relation: model.relation(network.observation))
                    }
                }
            }
            Text("Aynı modem: BSSID’si bağlı olduğun modemle aynı radyodan geldiğini gösteren ek ağlar (misafir ağı gibi). Tarama sırasında bağlantı bir an yavaşlayabilir.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .pocketCard()
    }

    private func channelText(_ link: WiFiLink) -> String {
        guard let channel = link.channel else { return "—" }
        return String(localized: "\(channel) · \(link.band?.title ?? "") · \(link.widthMHz) MHz")
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: value).font(.callout.weight(.semibold)).monospacedDigit().textSelection(.enabled).lineLimit(1)
            }
        }
    }

    private func tone(_ quality: WiFiSignalQuality) -> PocketTone { quality.tone }

    private func color(_ quality: WiFiSignalQuality) -> Color { quality.tone.color }
}

extension WiFiSignalQuality {
    var tone: PocketTone {
        switch self {
        case .excellent, .good: .success
        case .fair: .warning
        case .weak: .critical
        }
    }
}

private enum WiFiColumns {
    static let bssid: CGFloat = 150
    static let channel: CGFloat = 56
    static let width: CGFloat = 64
    static let security: CGFloat = 96
    static let signal: CGFloat = 150
}

private struct WiFiNetworkHeader: View {
    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Text("Ağ").frame(maxWidth: .infinity, alignment: .leading)
            Text("BSSID").frame(width: WiFiColumns.bssid, alignment: .leading)
            Text("Kanal").frame(width: WiFiColumns.channel, alignment: .trailing)
            Text("Genişlik").frame(width: WiFiColumns.width, alignment: .trailing)
            Text("Güvenlik").frame(width: WiFiColumns.security, alignment: .leading)
            Text("Sinyal").frame(width: WiFiColumns.signal, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, PocketSpacing.s)
    }
}

private struct WiFiNetworkRow: View {
    let network: WiFiScannedNetwork
    let relation: WiFiRelation?
    private var observation: WiFiNetworkObservation { network.observation }

    var body: some View {
        let quality = WiFiSignalQuality(rssi: observation.rssi)
        HStack(spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: relation == .connected ? "checkmark.circle.fill" : "wifi")
                    .foregroundStyle(relation == .connected ? Color.accentColor : quality.tone.color).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: PocketSpacing.xs) {
                        Text(verbatim: observation.ssid ?? String(localized: "Adı gizli"))
                            .foregroundStyle(observation.ssid == nil ? .secondary : .primary)
                            .fontWeight(relation == .connected ? .semibold : .regular)
                            .lineLimit(1)
                        if relation == .connected { PocketStatusBadge(text: "Bağlı", tone: .accent) }
                        if relation == .sameRouter { PocketStatusBadge(text: "Aynı modem", tone: .neutral) }
                    }
                    Text(verbatim: [observation.band.title, network.standard].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: observation.bssid ?? "—").font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(width: WiFiColumns.bssid, alignment: .leading)
            Text(verbatim: "\(observation.channel)").frame(width: WiFiColumns.channel, alignment: .trailing)
            Text(verbatim: "\(observation.widthMHz) MHz").foregroundStyle(.secondary).frame(width: WiFiColumns.width, alignment: .trailing)
            Text(verbatim: network.security ?? "—").foregroundStyle(network.security == nil ? .tertiary : .secondary)
                .lineLimit(1).frame(width: WiFiColumns.security, alignment: .leading)
            HStack(spacing: PocketSpacing.s) {
                SignalBar(rssi: observation.rssi, color: quality.tone.color)
                Text(verbatim: "\(observation.rssi) dBm").frame(width: 62, alignment: .trailing)
            }
            .frame(width: WiFiColumns.signal, alignment: .trailing)
        }
        .monospacedDigit()
        .font(.callout)
        .padding(.vertical, PocketSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// −100 dBm empty, −30 dBm full.
private struct SignalBar: View {
    let rssi: Int
    let color: Color

    var body: some View {
        let fraction = min(1, max(0.04, Double(rssi + 100) / 70))
        Capsule().fill(Color.secondary.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in Capsule().fill(color).frame(width: proxy.size.width * fraction) }
            }
            .frame(width: 70, height: 6)
            .accessibilityHidden(true)
    }
}

import AppKit
import MacPocketCore
import Network
import Observation
import SwiftUI
import UserNotifications

// MARK: - Outage watch

/// Records internet outages from `NWPathMonitor` for the whole app session and, when the user asks for it,
/// posts a notification as the connection drops and when it comes back. The monitor is a kernel callback, not
/// a poll, so watching costs nothing while the path is stable.
@MainActor
@Observable
final class ConnectionWatchService {
    static let shared = ConnectionWatchService()
    static let alertsKey = "MacPocket.network.outageAlerts"
    static let logKey = "MacPocket.network.outageLog"
    /// A drop must last this long before it is announced, so Wi-Fi roaming never raises a notification.
    static let defaultAnnounceDelay: Duration = .seconds(5)
    typealias Poster = @MainActor (_ title: String, _ body: String, _ id: String) async -> Void

    private(set) var log: ConnectionOutageLog
    private(set) var online: Bool?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var announceTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let announceDelay: Duration
    @ObservationIgnored private let post: Poster

    init(defaults: UserDefaults = .standard, announceDelay: Duration = defaultAnnounceDelay,
         post: @escaping Poster = { title, body, id in await ConnectionWatchService.postNotification(title: title, body: body, id: id) }) {
        self.defaults = defaults
        self.announceDelay = announceDelay
        self.post = post
        log = defaults.data(forKey: Self.logKey).flatMap { try? JSONDecoder().decode(ConnectionOutageLog.self, from: $0) }
            ?? ConnectionOutageLog()
    }

    var alertsEnabled: Bool { defaults.bool(forKey: Self.alertsKey) }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.record(online: satisfied, at: Date()) }
        }
        monitor.start(queue: DispatchQueue(label: "MacPocket.outageWatch", qos: .utility))
    }

    func clearHistory() {
        log.clear()
        save()
    }

    /// One path reading; `NWPathMonitor` calls it, tests feed it directly.
    func record(online isOnline: Bool, at date: Date) {
        // The first reading after launch is the baseline: a Mac that starts without a network is not news.
        let isFirstReading = online == nil
        online = isOnline
        guard let change = log.update(online: isOnline, at: date) else { return }
        save()
        guard !isFirstReading, alertsEnabled else { return }
        switch change {
        case .wentOffline:
            announceTask?.cancel()
            let delay = announceDelay
            announceTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.online == false else { return }
                await self.post(String(localized: "İnternet bağlantısı koptu"),
                                String(localized: "MacPocket bağlantı geri geldiğinde haber verecek."), "down")
            }
        case .cameBack(let duration):
            announceTask?.cancel()
            // Only outages that were announced get a "back" notification.
            guard duration >= announceDelay.timeInterval else { return }
            let text = Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
            Task { await post(String(localized: "İnternet bağlantısı geri geldi"),
                              String(localized: "Kesinti \(text) sürdü."), "up") }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: Self.logKey) }
    }

    static func postNotification(title: String, body: String, id: String) async {
        guard PocketAlertNotifier.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "MacPocket.connection." + id, content: content, trigger: nil))
    }
}

private extension Duration {
    var timeInterval: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

// MARK: - Diagnosis

@MainActor
@Observable
final class ConnectionDiagnosisModel {
    static let shared = ConnectionDiagnosisModel()

    private(set) var measurement: ConnectionMeasurement?
    private(set) var measuredAt: Date?
    private(set) var running = false

    var verdict: ConnectionVerdict? { measurement.map(ConnectionDiagnosis.verdict) }

    func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        let online = ConnectionWatchService.shared.online
        let rssi = await Task.detached(priority: .utility) { WiFiReader.link()?.rssi }.value
        measurement = await ConnectionDiagnostics.measure(hasLink: online != false, wifiRSSI: rssi)
        measuredAt = Date()
    }
}

extension ConnectionVerdict {
    var title: LocalizedStringKey {
        switch self {
        case .healthy: "Bağlantı sağlıklı"
        case .noLink: "Ağa bağlı değilsin"
        case .routerUnreachable: "Modeme ulaşılamıyor"
        case .noInternet: "Modem çalışıyor, internet yok"
        case .dnsFailing: "İnternet var, alan adları çözülemiyor"
        case .weakWiFi: "Wi-Fi sinyali zayıf"
        case .slow: "Bağlantı yavaş"
        }
    }

    var advice: LocalizedStringKey {
        switch self {
        case .healthy: "Modem, internet ve DNS normal yanıt veriyor."
        case .noLink: "Wi-Fi’yi aç veya bir ağa katıl; kablolu bağlantıda kabloyu kontrol et."
        case .routerUnreachable: "Modemi kapatıp 30 saniye sonra aç. Wi-Fi’deysen ağdan çıkıp yeniden katıl."
        case .noInternet: "Sorun büyük olasılıkla servis sağlayıcıda. Modemin internet ışığını kontrol et veya sağlayıcını ara."
        case .dnsFailing: "DNS sunucusu yanıt vermiyor. Sistem Ayarları › Ağ › Ayrıntılar › DNS’e 1.1.1.1 ekleyebilirsin."
        case .weakWiFi: "Modeme yaklaş, aradaki engelleri azalt veya Wi-Fi Analizi’nden daha boş bir kanal seç."
        case .slow: "Gecikme veya paket kaybı yüksek. Ağı yoğun kullanan uygulamaları Trafik sekmesinden kontrol et."
        }
    }

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .noLink: "wifi.slash"
        case .routerUnreachable: "wifi.router"
        case .noInternet: "globe.badge.chevron.backward"
        case .dnsFailing: "character.magnify"
        case .weakWiFi: "wifi.exclamationmark"
        case .slow: "tortoise.fill"
        }
    }

    var tone: PocketTone {
        switch self {
        case .healthy: .success
        case .weakWiFi, .slow: .warning
        case .noLink, .routerUnreachable, .noInternet, .dnsFailing: .critical
        }
    }

    /// The hop the verdict points at, highlighted in the path diagram.
    var failingHop: ConnectionHop? {
        switch self {
        case .noLink: .mac
        case .routerUnreachable, .weakWiFi: .router
        case .noInternet, .slow: .internet
        case .dnsFailing: .dns
        case .healthy: nil
        }
    }
}

enum ConnectionHop: CaseIterable, Identifiable {
    case mac, router, internet, dns
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .mac: "Bu Mac"
        case .router: "Modem"
        case .internet: "İnternet"
        case .dns: "DNS"
        }
    }

    var symbol: String {
        switch self {
        case .mac: "desktopcomputer"
        case .router: "wifi.router"
        case .internet: "globe"
        case .dns: "character.book.closed"
        }
    }
}

/// Ağ Yönetimi › Tanılama: "is it my Wi-Fi, my router, my provider or DNS?" in one click, plus the outage
/// history.
struct ConnectionDiagnosisView: View {
    @State private var model = ConnectionDiagnosisModel.shared
    @State private var watch = ConnectionWatchService.shared
    @AppStorage(ConnectionWatchService.alertsKey) private var alertsEnabled = false
    @State private var notificationsDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Bağlantı Tanılama",
                                  subtitle: "Modemi, interneti ve DNS’i ayrı ayrı ölçer; sorunun nerede olduğunu söyler.",
                                  icon: "stethoscope") {
                    Button { Task { await model.run() } } label: {
                        Label(model.measurement == nil ? "Bağlantıyı Tanıla" : "Yeniden Tanıla", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.pocketPrimary)
                    .disabled(model.running)
                    .keyboardShortcut("r", modifiers: .command)
                }
                verdictCard
                pathCard
                outageCard
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Verdict

    @ViewBuilder private var verdictCard: some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            if model.running {
                ProgressView().controlSize(.large).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Ölçülüyor…").font(.title3.weight(.semibold))
                    Text("Modem ve 1.1.1.1 üçer kez yoklanıyor, bir DNS sorgusu zamanlanıyor. Yaklaşık 3 saniye sürer.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if let verdict = model.verdict {
                Image(systemName: verdict.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(verdict.tone.color)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(verdict.title).font(.title3.weight(.semibold))
                    Text(verdict.advice).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let date = model.measuredAt {
                        Text("Ölçüm \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Image(systemName: "stethoscope").font(.system(size: 28)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Henüz ölçülmedi").font(.title3.weight(.semibold))
                    Text("Tanıla’ya bastığında modeme ve Cloudflare’in 1.1.1.1 adresine üçer ping gönderilir ve bir DNS sorgusu zamanlanır. Başka veri gönderilmez.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Path

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Bağlantı yolu", icon: "point.topleft.down.to.point.bottomright.curvepath")
            HStack(spacing: 0) {
                ForEach(Array(ConnectionHop.allCases.enumerated()), id: \.element) { index, hop in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            .frame(maxWidth: 40).accessibilityHidden(true)
                    }
                    HopTile(hop: hop, detail: detail(for: hop), state: state(for: hop))
                }
            }
        }
        .pocketCard()
    }

    private func detail(for hop: ConnectionHop) -> String {
        guard let measurement = model.measurement else { return "—" }
        func text(_ probe: ConnectionProbe?) -> String {
            guard let probe else { return String(localized: "Ağ geçidi yok") }
            guard let milliseconds = probe.milliseconds else { return String(localized: "Yanıt yok") }
            let time = milliseconds.formatted(.number.precision(.fractionLength(0))) + " ms"
            return probe.loss > 0 ? time + " · " + String(localized: "%\(Int((probe.loss * 100).rounded())) kayıp") : time
        }
        switch hop {
        case .mac:
            guard measurement.hasLink else { return String(localized: "Ağ yok") }
            return measurement.wifiRSSI.map { "Wi-Fi \($0) dBm" } ?? String(localized: "Bağlı")
        case .router: return text(measurement.router)
        case .internet: return text(measurement.internet)
        case .dns: return text(measurement.dns)
        }
    }

    private func state(for hop: ConnectionHop) -> HopTile.State {
        guard !model.running, let verdict = model.verdict else { return .unknown }
        if verdict.failingHop == hop { return verdict.tone == .warning ? .warning : .failed }
        let order = ConnectionHop.allCases
        if let failing = verdict.failingHop, let failingIndex = order.firstIndex(of: failing),
           let index = order.firstIndex(of: hop), index > failingIndex, verdict.tone == .critical {
            return .unknown
        }
        return .ok
    }

    // MARK: Outages

    private var outageCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("İnternet kesintileri", icon: "bolt.horizontal.circle") {
                if !watch.log.outages.isEmpty {
                    Button("Geçmişi Temizle") { watch.clearHistory() }.buttonStyle(.link)
                }
            }
            Toggle("Bağlantı koptuğunda ve geri geldiğinde bildirim gönder", isOn: $alertsEnabled)
                .onChange(of: alertsEnabled) { _, enabled in
                    guard enabled else { return }
                    Task {
                        let granted = await PocketAlertNotifier.requestAuthorization()
                        notificationsDenied = !granted
                    }
                }
            if notificationsDenied {
                PocketMessage("Bildirim izni yok. Sistem Ayarları › Bildirimler’den MacPocket’e izin ver.", tone: .warning)
            }
            if let since = watch.log.ongoingSince {
                Label("Şu an çevrimdışı · \(since.formatted(date: .omitted, time: .shortened)) itibarıyla", systemImage: "wifi.slash")
                    .foregroundStyle(.red)
            }
            if watch.log.outages.isEmpty {
                Text("MacPocket açıkken kesinti kaydedilmedi. 5 saniyeden kısa kopmalar (ör. erişim noktası değişimi) sayılmaz.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(watch.log.outages) { outage in
                        OutageRow(outage: outage)
                        if outage.id != watch.log.outages.last?.id { Divider() }
                    }
                }
            }
        }
        .pocketCard()
    }
}

private struct HopTile: View {
    enum State { case unknown, ok, warning, failed }
    let hop: ConnectionHop
    let detail: String
    let state: State

    private var color: Color {
        switch state {
        case .unknown: .secondary
        case .ok: PocketTone.success.color
        case .warning: PocketTone.warning.color
        case .failed: PocketTone.critical.color
        }
    }

    private var badge: String? {
        switch state {
        case .unknown: nil
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: PocketSpacing.s) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: hop.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(state == .unknown ? Color.secondary : Color.primary)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(state == .unknown ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let badge {
                    // The symbol shape, not only its color, tells the states apart.
                    Image(systemName: badge).font(.callout).foregroundStyle(color).background { Circle().fill(.background) }
                        .offset(x: 6, y: 6)
                }
            }
            Text(hop.title).font(.callout.weight(.semibold))
            Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct OutageRow: View {
    let outage: ConnectionOutage

    var body: some View {
        HStack {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange).accessibilityHidden(true)
            Text(outage.start.formatted(date: .abbreviated, time: .shortened))
            Spacer()
            Text(Duration.seconds(outage.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.vertical, PocketSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

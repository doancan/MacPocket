import AppKit
import Charts
import MacPocketCore
import SwiftUI
import UserNotifications

// MARK: - Model

/// Scans the local network on demand, remembers devices by MAC address, and (opt-in) rescans every 15 minutes
/// to notify about devices that join for the first time.
@MainActor
@Observable
final class LANScannerModel {
    static let shared = LANScannerModel()
    private static let knownKey = "MacPocket.lan.known"
    private static let watchKey = "MacPocket.lan.watch"
    private static let selectedKey = "MacPocket.lan.selectedNetworks"
    private static let customKey = "MacPocket.lan.customRanges"

    struct CustomRange: Codable, Equatable, Hashable {
        var cidr: String
        var name: String
    }

    private(set) var results: [LANScanResult] = []
    /// Attached networks found on this Mac, plus the ranges the user added.
    private(set) var networks: [LANNetworkInfo] = []
    private(set) var custom: [CustomRange] = []
    /// Network ids chosen for scanning; empty means "the primary network".
    private(set) var selected: Set<String> = []
    private(set) var scanning = false
    private(set) var progress = 0.0
    private(set) var error: String?
    private(set) var known: LANKnownDevices
    /// MAC addresses that appeared for the first time in the latest scan.
    private(set) var fresh: Set<String> = []
    private(set) var oui: OUIDatabase?
    var watch: Bool {
        didSet {
            UserDefaults.standard.set(watch, forKey: Self.watchKey)
            scheduleWatch()
            if watch { Task { _ = await PocketAlertNotifier.requestAuthorization() } }
        }
    }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var retried = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.knownKey),
           let stored = try? JSONDecoder().decode(LANKnownDevices.self, from: data) {
            known = stored
        } else {
            known = LANKnownDevices()
        }
        watch = UserDefaults.standard.bool(forKey: Self.watchKey)
        selected = Set(UserDefaults.standard.stringArray(forKey: Self.selectedKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let stored = try? JSONDecoder().decode([CustomRange].self, from: data) { custom = stored }
        scheduleWatch()
        Task.detached(priority: .utility) {
            let database = OUIDatabase.bundled()
            await MainActor.run { LANScannerModel.shared.oui = database }
        }
    }

    /// All devices of the last scan, network by network.
    var devices: [LANDevice] { results.flatMap(\.devices) }

    func network(of device: LANDevice) -> LANNetworkInfo? { results.first { $0.devices.contains { $0.id == device.id } }?.network }

    func isSelected(_ network: LANNetworkInfo) -> Bool {
        selected.isEmpty ? network.isPrimary : selected.contains(network.id)
    }

    var chosenNetworks: [LANNetworkInfo] {
        let chosen = networks.filter(isSelected)
        return chosen.isEmpty ? Array(networks.prefix(1)) : chosen
    }

    func toggle(_ network: LANNetworkInfo) {
        var set = selected.isEmpty ? Set(networks.filter(\.isPrimary).map(\.id)) : selected
        if set.contains(network.id) { set.remove(network.id) } else { set.insert(network.id) }
        if set.isEmpty { return }  // Always scan at least one network.
        selected = set
        UserDefaults.standard.set(Array(set), forKey: Self.selectedKey)
    }

    func addRange(_ cidr: String, name: String) -> String? {
        guard let subnet = LANSubnet.parse(cidr: cidr) else {
            return String(localized: "Geçerli bir aralık gir, örneğin 10.0.20.0/24 (en geniş /22).")
        }
        let range = CustomRange(cidr: subnet.description, name: name.trimmingCharacters(in: .whitespaces))
        guard !custom.contains(where: { $0.cidr == range.cidr }) else { return String(localized: "Bu aralık zaten listede.") }
        custom.append(range)
        saveCustom()
        Task {
            await refreshNetworks()
            if let added = networks.first(where: { $0.subnet.description == range.cidr }), !isSelected(added) { toggle(added) }
        }
        return nil
    }

    func removeRange(_ network: LANNetworkInfo) {
        custom.removeAll { $0.cidr == network.subnet.description }
        saveCustom()
        selected.remove(network.id)
        UserDefaults.standard.set(Array(selected), forKey: Self.selectedKey)
        networks.removeAll { $0.id == network.id }
        results.removeAll { $0.network.id == network.id }
    }

    func refreshNetworks() async {
        let attached = await LANScanner.availableNetworks()
        let routed = custom.compactMap { range -> LANNetworkInfo? in
            guard let subnet = LANSubnet.parse(cidr: range.cidr) else { return nil }
            let network = LANScanner.customNetwork(subnet, name: range.name, attached: attached)
            return network.isLocal ? nil : network
        }
        networks = attached + routed
    }

    private func saveCustom() {
        if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: Self.customKey) }
    }

    func scan(notify: Bool = false) async {
        guard !scanning else { return }
        scanning = true
        progress = 0
        error = nil
        defer { scanning = false }
        do {
            await refreshNetworks()
            let targets = chosenNetworks
            let report: @Sendable (Double) async -> Void = { value in await MainActor.run { LANScannerModel.shared.progress = value } }
            var scanned = try await LANScanner.scan(networks: targets, progress: report)
            // Right after launch macOS can still be applying Local Network access: pings and Bonjour come
            // back empty while the router answers. One quiet retry gives a complete picture instead of a
            // misleading one.
            let all = scanned.flatMap(\.devices)
            if !retried, all.filter({ $0.responded && !$0.isGateway && !$0.isSelf }).isEmpty, all.count > 2 {
                retried = true
                try? await Task.sleep(for: .seconds(1.5))
                scanned = try await LANScanner.scan(networks: targets, progress: report)
            }
            // Complete every normal scan through the installed helper; no separate button or password prompt.
            results = scanned
            do {
                scanned = try await LANHelperDiscovery.complete(scanned) { network in
                    try await LANHelperClient.shared.discover(network)
                }
            } catch {
                self.error = error.localizedDescription
            }
            results = scanned
            let found = scanned.flatMap(\.devices)
            var store = known
            let added = store.update(with: found)
            known = store
            save()
            if !notify { fresh = added } else { fresh.formUnion(added) }
            if notify && !added.isEmpty { announce(found.filter { $0.mac.map(added.contains) ?? false }) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func vendor(for device: LANDevice) -> String? { oui?.vendor(for: device.mac) }

    /// Bonjour first; the manufacturer fills in when Bonjour says nothing.
    func kind(for device: LANDevice) -> LANDeviceKind {
        let kind = device.kind
        guard kind == .unknown, let hint = LANDeviceKind.infer(vendor: vendor(for: device)) else { return kind }
        return hint
    }

    func name(for device: LANDevice) -> String {
        if let custom = known.name(for: device.mac) { return custom }
        if let name = device.displayName { return name }
        if device.isGateway { return String(localized: "Yönlendirici") }
        if let vendor = vendor(for: device) { return String(localized: "\(vendor) cihazı") }
        return String(localized: "Bilinmeyen cihaz")
    }

    func record(for device: LANDevice) -> LANKnownDevices.Record? { device.mac.flatMap { known.records[$0] } }

    func rename(_ device: LANDevice, to name: String) {
        guard let mac = device.mac else { return }
        known.rename(mac, to: name)
        save()
    }

    func forget(_ device: LANDevice) {
        guard let mac = device.mac else { return }
        known.forget(mac)
        fresh.remove(mac)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(known) { UserDefaults.standard.set(data, forKey: Self.knownKey) }
    }

    private func scheduleWatch() {
        timer?.invalidate()
        timer = nil
        guard watch else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in await LANScannerModel.shared.scan(notify: true) }
        }
        timer?.tolerance = 60
    }

    private func announce(_ devices: [LANDevice]) {
        guard PocketAlertNotifier.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ağa yeni cihaz katıldı")
        content.body = devices.map { [name(for: $0), $0.ip].joined(separator: " · ") }.joined(separator: "\n")
        let request = UNNotificationRequest(identifier: "lan-\(UUID().uuidString)", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}

extension LANDeviceKind {
    var tint: Color {
        switch self {
        case .router: PocketTheme.disk
        case .thisMac, .computer: PocketTheme.brand
        case .appleDevice: Color(hex: 0x8E8E93)
        case .printer: Color(hex: 0x5E5CE6)
        case .tv: Color(hex: 0xFF375F)
        case .speaker: Color(hex: 0xFF9F0A)
        case .smartHome: Color(hex: 0xFF9500)
        case .unknown: Color(hex: 0x98989D)
        }
    }
}

func lanLatencyText(_ seconds: TimeInterval) -> String {
    seconds < 0.001 ? "< 1 ms" : String(format: "%.0f ms", seconds * 1000)
}

func lanCopy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func lanServiceTitle(_ type: String) -> String? {
    switch type {
    case "_airplay._tcp": "AirPlay"
    case "_raop._tcp": String(localized: "AirPlay ses")
    case "_googlecast._tcp": "Google Cast"
    case "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp": String(localized: "Yazdırma")
    case "_hap._tcp": "HomeKit"
    case "_matter._tcp": "Matter"
    case "_smb._tcp": String(localized: "Dosya paylaşımı")
    case "_afpovertcp._tcp": "AFP"
    case "_ssh._tcp", "_sftp-ssh._tcp": "SSH"
    case "_rfb._tcp": String(localized: "Ekran paylaşımı")
    case "_spotify-connect._tcp": "Spotify Connect"
    case "_sonos._tcp": "Sonos"
    case "_companion-link._tcp": String(localized: "Apple Süreklilik")
    case "_http._tcp": String(localized: "Web arayüzü")
    default: nil
    }
}

// MARK: - Page

private enum LANFilter: String, CaseIterable, Identifiable {
    case all, responding, fresh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: String(localized: "Tümü")
        case .responding: String(localized: "Yanıt verenler")
        case .fresh: String(localized: "Yeni")
        }
    }
}

private enum LANLayout: String, CaseIterable, Identifiable {
    case list, map
    var id: String { rawValue }
    var title: String { self == .list ? String(localized: "Liste") : String(localized: "Harita") }
    var symbol: String { self == .list ? "list.bullet" : "point.3.filled.connected.trianglepath.dotted" }
}

/// Tools → Yerel Ağ.
struct LANScannerView: View {
    @Bindable private var model = LANScannerModel.shared
    @State private var filter = LANFilter.all
    @State private var layout = LANLayout.list
    @State private var search = ""
    @State private var selection: LANDevice.ID?
    @State private var renaming: LANDevice?
    @State private var newName = ""
    @State private var addingRange = false
    @State private var rangeText = ""
    @State private var rangeName = ""
    @State private var rangeError: String?
    @State private var mapNetwork: String?

    private var selected: LANDevice? { model.devices.first { $0.id == selection } }

    var body: some View {
        // The details panel sits beside the page instead of using `.inspector`: the inspector rebuilds the
        // window's customizable toolbar during layout, which AppKit rejects with an exception.
        HStack(spacing: 0) {
            page
            if let device = selected, let network = model.network(of: device) {
                Divider()
                LANDeviceInspector(device: device, network: network, model: model,
                                   rename: { newName = model.known.name(for: device.mac) ?? device.displayName ?? ""; renaming = device },
                                   close: { selection = nil })
                    .id(device.id)
                    .frame(width: 370)
                    .background { PocketTheme.panel.opacity(0.6) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: selection)
        .task {
            await model.refreshNetworks()
            if model.results.isEmpty { await model.scan() }
        }
        .sheet(item: $renaming) { device in renameSheet(device) }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Yerel Ağ",
                              subtitle: "Ağdaki cihazları üretici, tür, adres ve gecikmeleriyle gör; portlarını incele, uzaktan uyandır, yeni katılanları fark et.",
                              icon: "network") {
                Button { Task { await model.scan() } } label: {
                    Label(model.results.isEmpty ? "Ağı Tara" : "Yeniden Tara", systemImage: "dot.radiowaves.left.and.right")
                        .padding(.horizontal, PocketSpacing.xs)
                }
                .buttonStyle(.pocketPrimary).controlSize(.large)
                .disabled(model.scanning)
            }
            if model.scanning {
                HStack(spacing: PocketSpacing.m) {
                    ProgressView(value: model.progress).frame(maxWidth: 260)
                    Text("Ağ taranıyor; cihazların yanıtı ve adları bekleniyor…").font(.callout).foregroundStyle(.secondary)
                }
            }
            networkBar
            if let error = model.error { PocketMessage(error, tone: .warning) }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if !model.results.isEmpty {
                        summary(model.results)
                        controls
                        switch layout {
                        case .list:
                            ForEach(model.results) { result in list(result) }
                        case .map:
                            if let result = model.results.first(where: { $0.network.id == mapNetwork }) ?? model.results.first {
                                LANMapView(result: result, model: model, selection: $selection).pocketCard(padding: PocketSpacing.m)
                            }
                        }
                    } else if !model.scanning {
                        intro
                    }
                    footer
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
    }

    /// The networks to scan: attached ones found on this Mac and ranges added by hand.
    private var networkBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: PocketSpacing.s) {
                Text("Ağlar").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(model.networks) { network in
                    let on = model.isSelected(network)
                    HStack(spacing: 6) {
                        Button { model.toggle(network) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                                Image(systemName: network.symbol)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(networkTitle(network)).font(.callout.weight(.medium))
                                    Text(verbatim: network.subnet.description + (network.interface.isEmpty ? "" : " · \(network.interface)"))
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(on ? Text("Seçili") : Text("Seçili değil"))
                        if network.kind == .custom {
                            Button { model.removeRange(network) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("Aralığı kaldır").accessibilityLabel("Aralığı kaldır")
                        }
                    }
                    .padding(.horizontal, PocketSpacing.s).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(on ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                            .strokeBorder(on ? Color.accentColor.opacity(0.5) : PocketTheme.line)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        if network.kind == .custom {
                            Button("Aralığı Kaldır", role: .destructive) { model.removeRange(network) }
                        }
                    }
                    .disabled(model.scanning)
                    .help(network.isLocal ? String(localized: "Doğrudan bağlı ağ: MAC, Bonjour ve ping") : String(localized: "Yönlendirici üzerinden: ping, ters DNS, destekleyen cihazlarda NetBIOS ve SNMP"))
                }
                Button { rangeText = ""; rangeName = ""; rangeError = nil; addingRange = true } label: {
                    Label("Aralık ekle", systemImage: "plus")
                }
                .popover(isPresented: $addingRange, arrowEdge: .bottom) { rangePopover }
            }
            .padding(.vertical, 2)
        }.scrollIndicators(.hidden)
    }

    private var rangePopover: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text("Ağ aralığı ekle").font(.headline)
            Text("Yönlendirici üzerinden ulaşılan başka bir alt ağ veya VLAN. Ping ve ters DNS kullanılır; destekleyen cihazlar MAC bilgisini NetBIOS veya SNMP ile bildirebilir. Bonjour doğrudan bağlı ağlarla sınırlıdır.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(width: 320, alignment: .leading)
            TextField("10.0.20.0/24", text: $rangeText).textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle).monospaced()
            TextField("Ad (isteğe bağlı), örneğin Misafir ağı", text: $rangeName).textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle)
            if let rangeError { Text(rangeError).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Vazgeç") { addingRange = false }.keyboardShortcut(.cancelAction)
                Button("Ekle") {
                    if let problem = model.addRange(rangeText, name: rangeName) { rangeError = problem } else { addingRange = false }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.pocketPrimary)
            }
        }
        .padding(PocketSpacing.l)
    }

    private func networkTitle(_ network: LANNetworkInfo) -> String {
        if network.kind == .custom { return network.name }
        if network.subnet.network >> 16 == 0xA9FE { return String(localized: "Doğrudan bağlantı") }  // 169.254.x.x
        return network.name == network.interface ? String(localized: "Ağ arayüzü") : network.name
    }

    private var intro: some View {
        VStack(spacing: PocketSpacing.m) {
            Image(systemName: "network").font(.system(size: 52)).foregroundStyle(PocketTheme.brandGradient)
            Text("Ağındaki cihazları keşfet").font(.title3.weight(.semibold))
            Text("Tarama yalnız bu yerel ağa kısa paketler gönderir. macOS ilk taramada Yerel Ağ izni ister.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).pocketCard(padding: PocketSpacing.xl)
    }

    private func summary(_ results: [LANScanResult]) -> some View {
        let all = results.flatMap(\.devices)
        let primary = results.first(where: { $0.network.isPrimary }) ?? results[0]
        let responding = all.filter { $0.responded || $0.isSelf }.count
        let vendors = Set(all.compactMap(model.vendor(for:))).count
        let kinds = Dictionary(grouping: all, by: model.kind(for:)).mapValues(\.count)
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketMetricTile(title: "Cihaz", value: "\(all.count)",
                                 detail: "\(String(localized: "\(responding) tanesi yanıt verdi"))", icon: "dot.radiowaves.left.and.right",
                                 color: PocketTheme.brand)
                PocketMetricTile(title: "Ağ", value: results.count == 1 ? "\(primary.network.subnet.description)" : "\(String(localized: "\(results.count) ağ"))",
                                 detail: "\(results.map { networkTitle($0.network) }.joined(separator: ", "))", icon: "point.3.connected.trianglepath.dotted",
                                 color: PocketTheme.brandSecondary)
                PocketMetricTile(title: "Yönlendirici", value: "\(primary.network.gateway ?? "—")",
                                 detail: "\(primary.devices.first(where: \.isGateway)?.latency.map(lanLatencyText) ?? String(localized: "Yanıt yok"))",
                                 icon: "wifi.router", color: PocketTheme.disk)
                PocketMetricTile(title: "Yeni", value: "\(model.fresh.count)",
                                 detail: "\(String(localized: "\(vendors) farklı üretici"))", icon: "sparkles", color: PocketTheme.power)
            }
            // Composition of the network by device type.
            HStack(spacing: PocketSpacing.s) {
                ScrollView(.horizontal) {
                    HStack(spacing: PocketSpacing.s) {
                        ForEach(LANDeviceKind.allCases.filter { kinds[$0] != nil }, id: \.self) { kind in
                            Label("\(kind.title) \(kinds[kind] ?? 0)", systemImage: kind.symbol)
                                .font(.caption.weight(.medium)).foregroundStyle(kind.tint)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, PocketSpacing.s).padding(.vertical, 4)
                                .background(kind.tint.opacity(0.12), in: Capsule())
                        }
                    }
                }.scrollIndicators(.hidden)
                Spacer(minLength: 0)
                Text(String(localized: "Son tarama: \(primary.date.formatted(date: .omitted, time: .shortened))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: PocketSpacing.m) {
            GlassTabBar(tabs: LANLayout.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol) }, selection: $layout)
                .frame(maxWidth: 220)
            if layout == .list {
                GlassTabBar(tabs: LANFilter.allCases.map { GlassTab(id: $0, title: $0.title) }, selection: $filter).frame(maxWidth: 330)
                PocketSearchField("Ad, üretici, IP veya MAC ara", text: $search)
            } else {
                if model.results.count > 1 {
                    Picker("Ağ", selection: Binding(get: { mapNetwork ?? model.results.first?.network.id }, set: { mapNetwork = $0 })) {
                        ForEach(model.results) { result in
                            Text(verbatim: "\(networkTitle(result.network)) · \(result.network.subnet.description)").tag(Optional(result.network.id))
                        }
                    }
                    .fixedSize()
                        .pocketMenuPicker()
                }
                Spacer()
                Text("Bir cihaza tıklayarak ayrıntılarını aç.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func list(_ result: LANScanResult) -> some View {
        let devices = result.devices.filter { device in
            switch filter {
            case .all: true
            case .responding: device.responded || device.isSelf
            case .fresh: device.mac.map(model.fresh.contains) ?? false
            }
        }.filter { device in
            search.isEmpty || [model.name(for: device), device.ip, device.mac ?? "", model.kind(for: device).title, device.model ?? "",
                               model.vendor(for: device) ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
        }
        return VStack(alignment: .leading, spacing: PocketSpacing.s) {
            if model.results.count > 1 || !result.network.isLocal {
                HStack(spacing: PocketSpacing.s) {
                    Image(systemName: result.network.symbol).foregroundStyle(PocketTheme.brand)
                    Text(networkTitle(result.network)).font(.headline)
                    Text(verbatim: result.network.subnet.description + (result.network.interface.isEmpty ? "" : " · \(result.network.interface)"))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    if !result.network.isLocal {
                        PocketStatusBadge(text: "Yönlendirici üzerinden", systemImage: "arrow.triangle.branch", tone: .neutral)
                            .help("Yardımcı servis MAC taramasını otomatik tamamlar. Doğrudan ARP aynı fiziksel ağda çalışır; diğer cihazlar NetBIOS veya SNMP ile MAC bildirebilir.")

                    }
                    Spacer()
                    Text(String(localized: "\(result.devices.count) cihaz")).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, PocketSpacing.xs)
            }
            if devices.isEmpty {
                Text("Bu filtreyle eşleşen cihaz yok.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(devices) { device in
                        // A native button: click, keyboard focus with Space/Return and VoiceOver all toggle
                        // the details.
                        Button { selection = selection == device.id ? nil : device.id } label: {
                            LANDeviceRow(device: device, name: model.name(for: device), kind: model.kind(for: device),
                                         vendor: model.vendor(for: device), isNew: device.mac.map(model.fresh.contains) ?? false,
                                         selected: selection == device.id)
                        }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Ayrıntılar") { selection = device.id }
                                Button("Yeniden Adlandır…") { newName = model.known.name(for: device.mac) ?? device.displayName ?? ""; renaming = device }
                                    .disabled(device.mac == nil)
                                Button("IP Adresini Kopyala") { lanCopy(device.ip) }
                                if let mac = device.mac { Button("MAC Adresini Kopyala") { lanCopy(mac) } }
                                if device.mac != nil, !device.isSelf {
                                    Divider()
                                    Button("Bu Cihazı Unut", role: .destructive) { model.forget(device) }
                                }
                            }
                        if device.id != devices.last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .pocketCard(padding: PocketSpacing.m)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Toggle("Yeni cihaz katılınca bildir (15 dakikada bir tarar)", isOn: $model.watch)
            Text("Tarama yalnız seçili ağlardaki adreslere ping, Bonjour, NetBIOS, SNMP ve (ayrıntı panelinde) port sorgusu gönderir; internete bir şey gitmez. MAC adresi aynı ağda ARP’den, yönlendirici arkasında yalnız NetBIOS veya SNMP yanıtlayan cihazlardan (Windows, NAS, switch, yazıcı) gelir. Üretici bilgisi uygulamanın içindeki MACLookup ve IEEE kayıtlarından okunur.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PocketSpacing.xs)
    }

    private func renameSheet(_ device: LANDevice) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text("Cihazı adlandır").font(.headline)
            Text(verbatim: [device.ip, device.mac].compactMap { $0 }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
            TextField("Örneğin Salon TV", text: $newName).textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle).frame(width: 320)
            HStack {
                Spacer()
                Button("Vazgeç") { renaming = nil }.keyboardShortcut(.cancelAction)
                Button("Kaydet") { model.rename(device, to: newName); renaming = nil }.keyboardShortcut(.defaultAction).buttonStyle(.pocketPrimary)
            }
        }
        .padding(PocketSpacing.xl)
    }
}

// MARK: - Row

private struct LANDeviceRow: View {
    let device: LANDevice
    let name: String
    let kind: LANDeviceKind
    let vendor: String?
    let isNew: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketIconTile(symbol: kind.symbol, tint: kind.tint, size: PocketIconSize.item)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(name).font(.headline).lineLimit(1)
                    if device.isSelf { PocketStatusBadge(text: "Bu Mac", tone: .accent) }
                    if device.isGateway { PocketStatusBadge(text: "Yönlendirici", tone: .accent) }
                    if isNew { PocketStatusBadge(text: "Yeni", systemImage: "sparkles", tone: .warning) }
                }
                HStack(spacing: PocketSpacing.s) {
                    Text(verbatim: device.ip).monospacedDigit()
                    if let mac = device.mac {
                        Text(verbatim: mac).monospaced()
                        if MACAddress.isPrivate(mac) {
                            Label("Özel adres", systemImage: "eye.slash").help("Cihaz bu ağ için rastgele bir donanım adresi kullanıyor.")
                        }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
            }
            Spacer(minLength: PocketSpacing.m)
            VStack(alignment: .trailing, spacing: 2) {
                Text(kind.title).font(.callout.weight(.medium))
                if device.isSelf {
                    Text("Bu cihaz").font(.caption).foregroundStyle(.secondary)
                } else if let latency = device.latency {
                    HStack(spacing: 4) {
                        Circle().fill(latency < 0.05 ? PocketTheme.disk : .orange).frame(width: 6, height: 6)
                        Text(lanLatencyText(latency)).monospacedDigit()
                    }
                    .font(.caption)
                } else {
                    Text("Uykuda olabilir").font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, PocketSpacing.s).padding(.horizontal, PocketSpacing.xs)
        .background { RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous).fill(Color.accentColor.opacity(selected ? 0.10 : 0)) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var detail: String? {
        let parts = [vendor, device.model ?? device.snmpDescription.map { String($0.prefix(60)) }].compactMap { $0 }
            + [device.services.compactMap(lanServiceTitle).sorted().joined(separator: ", ")].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Map

/// The router in the middle, devices that answered on the inner ring, quiet ones on the outer ring.
private struct LANMapView: View {
    @PocketReduceMotion private var reduceMotion
    let result: LANScanResult
    var model: LANScannerModel
    @Binding var selection: LANDevice.ID?
    @State private var hovered: LANDevice.ID?

    var body: some View {
        let router = result.devices.first(where: \.isGateway)
        let others = result.devices.filter { !$0.isGateway }
        let inner = others.filter { $0.responded || $0.isSelf }, outer = others.filter { !$0.responded && !$0.isSelf }
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let innerRadius = min(proxy.size.width, proxy.size.height) * 0.27
            let outerRadius = min(proxy.size.width * 0.46, proxy.size.height * 0.44)
            let positions = place(inner, radius: innerRadius, center: center, offset: -.pi / 2)
                .merging(place(outer, radius: outerRadius, center: center, offset: -.pi / 2 + 0.3)) { $1 }
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1).frame(width: innerRadius * 2, height: innerRadius * 2).position(center)
                Circle().stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    .frame(width: outerRadius * 2, height: outerRadius * 2).position(center)
                Canvas { context, _ in
                    for device in others {
                        guard let point = positions[device.id] else { continue }
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point)
                        let active = selection == device.id || hovered == device.id
                        context.stroke(path, with: .color(model.kind(for: device).tint.opacity(active ? 0.8 : device.responded ? 0.35 : 0.15)),
                                       style: StrokeStyle(lineWidth: active ? 2 : 1, dash: device.responded || device.isSelf ? [] : [3, 4]))
                    }
                }
                if let router { node(router, size: 58).position(center) }
                ForEach(others) { device in
                    if let point = positions[device.id] { node(device, size: 40).position(point) }
                }
            }
        }
        .frame(height: 520)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: PocketSpacing.m) {
                Label("Yanıt veriyor", systemImage: "circle").foregroundStyle(.secondary)
                Label("Uykuda olabilir", systemImage: "circle.dashed").foregroundStyle(.secondary)
            }
            .font(.caption).padding(PocketSpacing.s)
        }
    }

    private func place(_ devices: [LANDevice], radius: CGFloat, center: CGPoint, offset: Double) -> [LANDevice.ID: CGPoint] {
        var result: [LANDevice.ID: CGPoint] = [:]
        for (index, device) in devices.enumerated() {
            let angle = offset + Double(index) / Double(max(1, devices.count)) * 2 * .pi
            result[device.id] = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return result
    }

    private func node(_ device: LANDevice, size: CGFloat) -> some View {
        let kind = model.kind(for: device)
        let active = selection == device.id
        return Button { selection = device.id } label: {
            VStack(spacing: 4) {
                PocketIconTile(symbol: kind.symbol, tint: kind.tint, size: size)
                    .opacity(device.responded || device.isSelf || device.isGateway ? 1 : 0.55)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: active ? 3 : 0).padding(-3)
                    }
                    .overlay(alignment: .topTrailing) {
                        if device.mac.map(model.fresh.contains) ?? false {
                            Circle().fill(.orange).frame(width: 10, height: 10).offset(x: 3, y: -3)
                        }
                    }
                Text(model.name(for: device)).font(.caption2.weight(.medium)).lineLimit(1).frame(maxWidth: 110)
                Text(verbatim: device.latency.map(lanLatencyText) ?? device.ip).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(!reduceMotion && hovered == device.id ? 1.08 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 ? device.id : (hovered == device.id ? nil : hovered) }
        .help([model.name(for: device), device.ip, model.vendor(for: device)].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityValue(active ? Text("Seçili") : Text("Seçili değil"))
    }
}

// MARK: - Inspector

@MainActor
private final class LANDeviceProbe: ObservableObject {
    @Published private(set) var samples: [(date: Date, latency: TimeInterval?)] = []
    @Published private(set) var ports: [LANPort]?
    @Published private(set) var titles: [UInt16: String] = [:]
    @Published private(set) var scanningPorts = false
    private var pinging: Task<Void, Never>?

    func start(_ ip: String, isSelf: Bool) {
        guard pinging == nil, !isSelf else { return }
        pinging = Task { [weak self] in
            while !Task.isCancelled {
                let latency = await LANScanner.ping(ip, timeout: 1)
                guard let self else { return }
                self.samples.append((Date(), latency))
                if self.samples.count > 60 { self.samples.removeFirst(self.samples.count - 60) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { pinging?.cancel(); pinging = nil }

    func scanPorts(_ ip: String) async {
        guard !scanningPorts else { return }
        scanningPorts = true
        let open = await LANPortScanner.scan(ip)
        ports = open
        scanningPorts = false
        for port in open where port.isWeb {
            if let title = await LANPortScanner.webTitle(ip, port: port) { titles[port.number] = title }
        }
    }

    var statistics: PingStatistics { PingStatistics(samples: samples.map(\.latency)) }
}

private struct LANDeviceInspector: View {
    let device: LANDevice
    let network: LANNetworkInfo
    var model: LANScannerModel
    let rename: () -> Void
    let close: () -> Void
    @StateObject private var probe = LANDeviceProbe()
    @State private var wakeSent: Bool?

    var body: some View {
        let kind = model.kind(for: device)
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                HStack(alignment: .top, spacing: PocketSpacing.m) {
                    PocketIconTile(symbol: kind.symbol, tint: kind.tint, size: PocketIconSize.feature)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name(for: device)).font(.title3.weight(.semibold)).lineLimit(2)
                        Text([kind.title, model.vendor(for: device)].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Kapat").accessibilityLabel("Kapat")
                }
                actions
                if let wakeSent {
                    Text(wakeSent ? "Uyandırma paketi gönderildi." : "Paket gönderilemedi.").font(.caption)
                        .foregroundStyle(wakeSent ? PocketTheme.disk : .orange)
                }
                pingCard
                portsCard
                infoCard
            }
            .padding(PocketSpacing.l)
        }
        .onAppear { probe.start(device.ip, isSelf: device.isSelf) }
        .onDisappear { probe.stop() }
        .task { await probe.scanPorts(device.isSelf ? "127.0.0.1" : device.ip) }
    }

    private var actions: some View {
        HStack(spacing: PocketSpacing.s) {
            Button { rename() } label: { Label("Adlandır", systemImage: "pencil") }.disabled(device.mac == nil)
            Button { lanCopy(device.ip) } label: { Label("IP", systemImage: "doc.on.doc") }
            if let mac = device.mac, !device.isSelf {
                Button {
                    wakeSent = WakeOnLAN.wake(mac: mac, broadcast: IPv4.text(network.subnet.broadcast))
                } label: { Label("Uyandır", systemImage: "power") }
                    .help("Wake-on-LAN sihirli paketi gönderir; yalnız bu özelliği açık cihazlarda çalışır.")
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private var pingCard: some View {
        if !device.isSelf {
            let stats = probe.statistics
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                PocketSectionHeader("Canlı gecikme", icon: "waveform.path.ecg") {
                    Text(String(localized: "\(stats.sent) ping"))
                }
                Chart {
                    ForEach(Array(probe.samples.enumerated()), id: \.offset) { _, sample in
                        if let latency = sample.latency {
                            LineMark(x: .value("Zaman", sample.date), y: .value("ms", latency * 1000))
                                .interpolationMethod(.monotone).foregroundStyle(PocketTheme.brand)
                            AreaMark(x: .value("Zaman", sample.date), y: .value("ms", latency * 1000))
                                .interpolationMethod(.monotone).foregroundStyle(PocketTheme.brand.opacity(0.12))
                        } else {
                            RuleMark(x: .value("Zaman", sample.date)).foregroundStyle(.red.opacity(0.5))
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let ms = value.as(Double.self) { Text(String(format: "%.0f", ms)) } }
                } }
                .frame(height: 110)
                .overlay { if probe.samples.isEmpty { Text("Ölçülüyor…").font(.caption).foregroundStyle(.secondary) } }
                Grid(alignment: .leading, horizontalSpacing: PocketSpacing.l, verticalSpacing: 4) {
                    GridRow {
                        stat("Ortalama", stats.average.map(lanLatencyText))
                        stat("Oynaklık", stats.jitter.map(lanLatencyText))
                    }
                    GridRow {
                        stat("En düşük / yüksek", stats.minimum.flatMap { min in stats.maximum.map { "\(lanLatencyText(min)) / \(lanLatencyText($0))" } })
                        stat("Kayıp", stats.sent > 0 ? MenuBarFormatter.percent(stats.lossPercent, decimals: false) : nil,
                             warn: stats.lossPercent > 5)
                    }
                }
                .font(.callout)
            }
            .pocketCard(padding: PocketSpacing.m)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String?, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value ?? "—").monospacedDigit().foregroundStyle(warn ? .orange : .primary)
        }
    }

    private var portsCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Açık portlar", icon: "door.left.hand.open") {
                if probe.scanningPorts { ProgressView().controlSize(.small) } else if let ports = probe.ports { Text(String(localized: "\(ports.count) açık")) }
            }
            if let ports = probe.ports {
                if ports.isEmpty {
                    Text("Yaygın portların hiçbiri açık değil; cihaz bağlantıları reddediyor ya da yanıt vermiyor.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(ports) { port in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: PocketSpacing.s) {
                            Text(verbatim: "\(port.number)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 52, alignment: .leading)
                            Text(port.name).font(.callout)
                            Spacer(minLength: 0)
                            if port.isWeb, let url = URL(string: "\(port.scheme)://\(device.ip):\(port.number)/") {
                                Button("Aç") { NSWorkspace.shared.open(url) }.controlSize(.small)
                            }
                        }
                        if let title = probe.titles[port.number] {
                            Text(verbatim: "“\(title)”").font(.caption).foregroundStyle(.secondary).padding(.leading, 60).lineLimit(1)
                        }
                        if let risk = port.risk {
                            Label(risk, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                                .padding(.leading, 60).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text(String(localized: "Yaygın \(LANPort.common.count) port deneniyor…")).font(.callout).foregroundStyle(.secondary)
            }
            Button { Task { await probe.scanPorts(device.isSelf ? "127.0.0.1" : device.ip) } } label: {
                Label("Yeniden Tara", systemImage: "arrow.clockwise")
            }
            .controlSize(.small).disabled(probe.scanningPorts)
        }
        .pocketCard(padding: PocketSpacing.m)
    }

    private var infoCard: some View {
        let record = model.record(for: device)
        return VStack(alignment: .leading, spacing: 6) {
            PocketSectionHeader("Bilgiler", icon: "info.circle")
            info("IP adresi", device.ip)
            info("MAC adresi", device.mac.map { MACAddress.isPrivate($0) ? $0 + String(localized: " (özel)") : $0 })
            info("Üretici", model.vendor(for: device))
            info("Bonjour adı", device.bonjourName)
            info("NetBIOS adı", device.netbiosName)
            info("Çalışma grubu", device.workgroup)
            info("SNMP adı", device.snmpName)
            info("Sistem açıklaması", device.snmpDescription)
            switch device.macSource {
            case .netbios:
                Label("MAC adresi NetBIOS yanıtından alındı.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            case .snmp:
                Label("MAC adresi SNMP yanıtından alındı.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            case .snmpInterface:
                Label("SNMP arayüz MAC adresi; hedef IP ile eşleşmesi doğrulanamadı.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            case .arp:
                EmptyView()
            }
            info("Ana makine adı", device.hostName)
            info("Model", device.model)
            info("Hizmetler", device.services.isEmpty ? nil : device.services.compactMap(lanServiceTitle).sorted().joined(separator: ", "))
            info("İlk görülme", record?.firstSeen.formatted(date: .abbreviated, time: .shortened))
            info("Son görülme", record?.lastSeen.formatted(.relative(presentation: .named)))
        }
        .pocketCard(padding: PocketSpacing.m)
    }

    @ViewBuilder private func info(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                Text(verbatim: value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
        }
    }
}

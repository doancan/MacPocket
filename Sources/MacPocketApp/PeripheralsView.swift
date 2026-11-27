import MacPocketCore
import SwiftUI

@MainActor
final class PeripheralsModel: ObservableObject {
    @Published private(set) var devices: [USBDevice] = []
    @Published private(set) var ports: [ThunderboltPort] = []
    @Published private(set) var loaded = false
    @Published private(set) var refreshing = false
    @Published private(set) var thunderboltLoaded = false
    @Published private(set) var error: String?
    @Published var showHubs = false {
        didSet { UserDefaults.standard.set(showHubs, forKey: Self.showHubsKey) }
    }

    private static let showHubsKey = "MacPocket.peripherals.showHubs"
    /// Plugging something in shows up within this interval while the page is open.
    static let interval = Duration.seconds(2)

    init() { showHubs = UserDefaults.standard.bool(forKey: Self.showHubsKey) }

    func run() async {
        var lastIDs: Set<UInt64>?
        while !Task.isCancelled {
            let devices = await Task.detached(priority: .utility) { USBDeviceReader.read() }.value
            let ids = Set(devices.map(\.id))
            guard !Task.isCancelled else { return }
            self.devices = devices
            loaded = true
            // System Information is slow; ask it again only when the USB tree changed (a dock brings both).
            if ids != lastIDs {
                lastIDs = ids
                await refreshThunderbolt()
            }
            loaded = true
            do { try await Task.sleep(for: Self.interval) } catch { return }
        }
    }

    func refreshThunderbolt() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false; thunderboltLoaded = true }
        do {
            let result = try await BoundedProcess.run(ThunderboltReport.executable, ThunderboltReport.arguments, timeout: 20)
            try Task.checkCancellation()
            guard result.status == 0 else {
                throw NSError(domain: "MacPocket.Thunderbolt", code: Int(result.status),
                              userInfo: [NSLocalizedDescriptionKey: String(localized: "Thunderbolt bilgileri okunamadı. Yeniden dene.")])
            }
            ports = ThunderboltReport.parse(Data(result.output.utf8))
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// Hubs are plumbing; hidden by default, their children move up to the hub's level.
    var visibleRows: [USBTreeRow] { USBTree.rows(devices, includeHubs: showHubs) }

    var hubCount: Int { devices.filter(\.isHub).count }
}

struct PeripheralsView: View {
    @StateObject private var model = PeripheralsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "USB ve Thunderbolt",
                              subtitle: "Takılı aygıtları, bağlantı hızlarını ve çektikleri gücü gör; yavaş kablo veya portu fark et.",
                              icon: "cable.connector") {
                Button { Task { await model.refreshThunderbolt() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if let error = model.error { PocketMessage(error, tone: .warning) }
                    ForEach(model.visibleRows.filter(\.device.isSlowStorage)) { row in
                        PocketMessage(String(localized: "\(row.device.name) USB 2 hızında bağlı (en fazla ~40 MB/s). USB 3 destekliyorsa kabloyu veya portu değiştirmek hızlandırabilir."),
                                      tone: .warning)
                    }
                    thunderbolt
                    usb
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .task { await model.run() }
    }

    private var thunderbolt: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Thunderbolt / USB4 portları", icon: "bolt.horizontal")
            if model.refreshing {
                PocketProgressRow(message: "Thunderbolt portları okunuyor…")
            }
            if model.ports.isEmpty, model.thunderboltLoaded, !model.refreshing {
                Text(model.error == nil ? "Bu Mac Thunderbolt portu bildirmedi." : "Port bilgisi alınamadı; Yenile ile tekrar dene.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: PocketSpacing.m)], spacing: PocketSpacing.m) {
                    ForEach(model.ports) { port in ThunderboltPortCard(port: port) }
                }
            }
        }
    }

    private var usb: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("USB aygıtları", icon: "cable.connector.horizontal") {
                if model.hubCount > 0 {
                    Toggle(String(localized: "Hub’ları göster (\(model.hubCount))"), isOn: $model.showHubs).toggleStyle(.checkbox)
                }
            }
            let rows = model.visibleRows
            if !model.loaded {
                PocketProgressRow(message: "USB aygıtları okunuyor…")
            } else if rows.isEmpty {
                ContentUnavailableView("USB aygıtı yok", systemImage: "cable.connector.slash")
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .pocketCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        USBDeviceRow(row: row)
                    }
                }
                .padding(.horizontal, PocketSpacing.l)
                .padding(.vertical, PocketSpacing.s)
                .pocketCard(padding: 0)
            }
            Text("Liste \(Int(PeripheralsModel.interval.components.seconds)) saniyede bir yenilenir. Güç, macOS’un aygıta ayırdığı akımdır; anlık tüketim değildir.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct ThunderboltPortCard: View {
    let port: ThunderboltPort

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack {
                Image(systemName: port.isConnected ? "bolt.horizontal.fill" : "bolt.horizontal")
                    .foregroundStyle(port.isConnected ? Color.accentColor : .secondary)
                Text(port.receptacle.map { String(localized: "Port \($0)") } ?? String(localized: "Port"))
                    .font(.headline)
                Spacer()
                if let speed = port.speedGbps {
                    Text(String(localized: "en fazla \(speed.formatted(.number.precision(.fractionLength(0...1)))) Gb/s"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if port.devices.isEmpty {
                Text("Boş").foregroundStyle(.secondary)
            } else {
                ForEach(port.devices) { device in
                    HStack(spacing: PocketSpacing.xs) {
                        Text(verbatim: device.name).lineLimit(1)
                        if let vendor = device.vendor { Text(verbatim: vendor).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(minLength: 0)
                        if let speed = device.speedGbps {
                            Text(verbatim: "\(speed.formatted(.number.precision(.fractionLength(0...1)))) Gb/s")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .padding(.leading, CGFloat(device.depth) * 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard(padding: PocketSpacing.m)
    }
}

private struct USBDeviceRow: View {
    let row: USBTreeRow
    private var device: USBDevice { row.device }

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: symbol).foregroundStyle(device.isSlowStorage ? .orange : .secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: device.name).lineLimit(1)
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: device.speedTitle ?? "—")
                .frame(width: 130, alignment: .trailing)
                .foregroundStyle(device.isSlowStorage ? .orange : .primary)
            Text(verbatim: device.powerMilliamps.map { String(localized: "\($0) mA") } ?? "—")
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(.vertical, PocketSpacing.s)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let ids = String(format: "%04X:%04X", device.vendorID, device.productID)
        return [device.vendor, kind, ids].compactMap { $0 }.joined(separator: " · ")
    }

    private var kind: String? {
        if device.isHub { return String(localized: "Hub") }
        if device.isStorage { return String(localized: "Depolama") }
        if device.interfaceClasses.contains(3) { return String(localized: "Giriş aygıtı") }
        if device.interfaceClasses.contains(1) { return String(localized: "Ses") }
        if device.interfaceClasses.contains(14) { return String(localized: "Kamera") }
        if device.deviceClass == 17 { return String(localized: "Billboard (USB-C mod bilgisi)") }
        return nil
    }

    private var symbol: String {
        if device.isHub { return "point.3.connected.trianglepath.dotted" }
        if device.isStorage { return "externaldrive" }
        if device.interfaceClasses.contains(3) { return "keyboard" }
        if device.interfaceClasses.contains(1) { return "speaker.wave.2" }
        if device.interfaceClasses.contains(14) { return "web.camera" }
        return "cable.connector"
    }
}

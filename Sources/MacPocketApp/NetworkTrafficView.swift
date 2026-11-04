import AppKit
import Darwin
import MacPocketCore
import SwiftUI

/// Samples `nettop` every two seconds while the page is open; nothing runs in the background.
@MainActor
final class NetworkTrafficModel: ObservableObject {
    @Published private(set) var groups: [NetworkTrafficGroup] = []
    @Published private(set) var error: String?
    @Published private(set) var startedAt = Date()
    @Published var groupByApp = UserDefaults.standard.object(forKey: "MacPocket.traffic.groupByApp") as? Bool ?? true {
        didSet { UserDefaults.standard.set(groupByApp, forKey: "MacPocket.traffic.groupByApp"); regroup() }
    }

    static let interval: Duration = .seconds(2)
    private var sampling = false
    private var generation = UUID()
    private var tracker = NetworkTrafficTracker()
    private var rows: [NetworkTrafficRow] = []
    private var identities: [Int32: ProcessIdentity] = [:]

    struct ProcessIdentity {
        let name: String
        /// The outermost `.app` the executable lives in, if any.
        let appPath: String?
        let appName: String?
    }

    var downloadRate: Double { groups.reduce(0) { $0 + $1.downloadRate } }
    var uploadRate: Double { groups.reduce(0) { $0 + $1.uploadRate } }
    var sessionTotal: UInt64 { groups.reduce(0) { $0 &+ $1.sessionTotal } }

    func run() async {
        while !Task.isCancelled {
            await sample()
            do { try await Task.sleep(for: Self.interval) } catch { return }
        }
    }

    func resetSession() {
        generation = UUID()
        tracker.reset()
        rows = []
        groups = []
        startedAt = Date()
    }

    private func sample() async {
        guard !sampling, !Task.isCancelled else { return }
        sampling = true
        let token = generation
        defer { sampling = false }
        do {
            let result = try await BoundedProcess.run(NetworkTraffic.nettopPath, NetworkTraffic.nettopArguments, timeout: 10)
            guard !Task.isCancelled, token == generation else { return }
            guard result.status == 0 else {
                error = String(localized: "nettop başarısız oldu (\(result.status)).")
                return
            }
            let samples = NetworkTraffic.parse(result.output)
            let live = Set(samples.map(\.pid))
            identities = identities.filter { live.contains($0.key) }
            for sample in samples where identities[sample.pid] == nil { identities[sample.pid] = Self.identity(of: sample) }
            let named = samples.map { NetworkTrafficSample(pid: $0.pid, name: identities[$0.pid]?.name ?? $0.name,
                                                           bytesIn: $0.bytesIn, bytesOut: $0.bytesOut) }
            rows = tracker.update(named, at: Date())
            error = nil
            regroup()
        } catch is CancellationError {
        } catch BoundedProcess.Failure.cancelled {
        } catch {
            if !Task.isCancelled, token == generation { self.error = error.localizedDescription }
        }
    }

    private func regroup() {
        let latest = NetworkTraffic.group(rows) { [identities, groupByApp] row in
            guard groupByApp, let identity = identities[row.pid], let path = identity.appPath else { return nil }
            return (path, identity.appName ?? row.name)
        }
        if latest != groups { groups = latest }
    }

    func appPath(of group: NetworkTrafficGroup) -> String? {
        group.id.hasPrefix("pid:") ? identities[group.rows[0].pid]?.appPath : group.id
    }

    /// The running app a group can be quit through: a regular app whose bundle owns the group.
    func runningApp(for group: NetworkTrafficGroup) -> NSRunningApplication? {
        guard let path = appPath(of: group) else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.bundleURL?.path == path && $0.processIdentifier != getpid()
        }
    }

    private static func identity(of sample: NetworkTrafficSample) -> ProcessIdentity {
        let running = NSRunningApplication(processIdentifier: sample.pid)
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(sample.pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        let appPath = path.flatMap(outermostApp)
        let appName = appPath.map { FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "") }
        let name = running?.localizedName ?? path.map { ($0 as NSString).lastPathComponent } ?? sample.name
        return ProcessIdentity(name: name, appPath: appPath, appName: appName)
    }

    private static func outermostApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        let candidate = String(path[..<range.lowerBound]) + ".app"
        return candidate.hasPrefix("/System/Library/") || candidate.hasPrefix("/usr/") ? nil : candidate
    }
}

/// Tools → Ağ Trafiği: which apps are using the network right now and how much they moved since the page opened.
struct NetworkTrafficView: View {
    @StateObject private var traffic = NetworkTrafficModel()
    @State private var search = ""
    @State private var activeOnly = false
    @State private var pendingQuit: NetworkTrafficGroup?
    @State private var expanded: Set<String> = []
    @FocusState private var searchFocused: Bool

    private var visible: [NetworkTrafficGroup] {
        traffic.groups.filter { group in
            (!activeOnly || group.isActive)
                && (search.isEmpty || group.name.localizedCaseInsensitiveContains(search)
                    || group.rows.contains { $0.name.localizedCaseInsensitiveContains(search) || String($0.pid) == search })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ağ Trafiği",
                              subtitle: "Hangi uygulamanın şu an ne kadar indirip yüklediğini ve bu sayfa açıldığından beri toplam trafiğini gör.",
                              icon: "arrow.up.arrow.down.circle") {
                Button { traffic.resetSession() } label: { Label("Sıfırla", systemImage: "arrow.counterclockwise") }
                    .help("Toplamları sıfırla")
            }
            if let error = traffic.error { PocketMessage(error, tone: .warning) }
            summary
            controls
            list
        }
        .pocketPage()
        .task { await traffic.run() }
        .confirmationDialog(pendingQuit.map { String(localized: "\($0.name) kapatılsın mı?") } ?? "", isPresented: Binding(
            get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })) {
            if let group = pendingQuit {
                Button("Kapat") { quit(group, force: false) }
                Button("Zorla kapat", role: .destructive) { quit(group, force: true) }
            }
        } message: {
            Text("Kaydedilmemiş değişiklikler kaybolabilir.")
        }
    }

    private var summary: some View {
        HStack(spacing: PocketSpacing.m) {
            TrafficStat(title: "İndirme", value: MenuBarFormatter.rate(traffic.downloadRate, binary: false),
                        symbol: "arrow.down", tint: .blue)
            TrafficStat(title: "Yükleme", value: MenuBarFormatter.rate(traffic.uploadRate, binary: false),
                        symbol: "arrow.up", tint: .orange)
            TrafficStat(title: "Toplam", value: MenuBarFormatter.bytes(Double(traffic.sessionTotal), binary: false),
                        symbol: "sum", tint: .secondary,
                        footnote: String(localized: "\(traffic.startedAt.formatted(date: .omitted, time: .shortened)) itibarıyla"))
        }
    }

    private var controls: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketSearchField("Uygulama, süreç veya PID ara…", text: $search, focus: $searchFocused).frame(maxWidth: 280)
            Toggle("Yalnız şu an trafiği olanlar", isOn: $activeOnly).toggleStyle(.checkbox)
            Toggle("Yardımcı süreçleri uygulamada topla", isOn: $traffic.groupByApp).toggleStyle(.checkbox)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var list: some View {
        if visible.isEmpty {
            ContentUnavailableView(traffic.groups.isEmpty ? "Ölçülüyor…" : "Eşleşen süreç yok", systemImage: "network",
                                   description: Text(traffic.groups.isEmpty ? "İlk ölçüm birkaç saniye sürer." : "Aramayı veya filtreyi değiştir."))
                .frame(maxWidth: .infinity, minHeight: 240)
                .pocketCard()
        } else {
            VStack(spacing: 0) {
                TrafficHeaderRow()
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, group in
                            if index > 0 { Divider() }
                            TrafficGroupRow(group: group, icon: icon(for: group), canQuit: traffic.runningApp(for: group) != nil,
                                            isExpanded: expanded.contains(group.id),
                                            toggle: { toggle(group.id) }, quit: { pendingQuit = group })
                        }
                    }
                }
            }
            .padding(.horizontal, PocketSpacing.l)
            .padding(.vertical, PocketSpacing.s)
            .pocketCard(padding: 0)
            Text("Hızlar \(Int(NetworkTrafficModel.interval.components.seconds)) saniyede bir ölçülür ve yalnız bu sayfa açıkken izlenir; yerel ağ trafiği de dahildir.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func icon(for group: NetworkTrafficGroup) -> NSImage? {
        traffic.appPath(of: group).map { NSWorkspace.shared.icon(forFile: $0) }
    }

    private func quit(_ group: NetworkTrafficGroup, force: Bool) {
        pendingQuit = nil
        guard let app = traffic.runningApp(for: group) else { return }
        _ = force ? app.forceTerminate() : app.terminate()
    }
}

private struct TrafficStat: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let tint: Color
    var footnote: String?

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                if let footnote { Text(verbatim: footnote).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .pocketCard(padding: PocketSpacing.m)
    }
}

private enum TrafficColumns {
    static let rate: CGFloat = 96
    static let total: CGFloat = 96
    static let action: CGFloat = 28
}

private struct TrafficHeaderRow: View {
    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Text("Uygulama").frame(maxWidth: .infinity, alignment: .leading)
            Text("İndirme").frame(width: TrafficColumns.rate, alignment: .trailing)
            Text("Yükleme").frame(width: TrafficColumns.rate, alignment: .trailing)
            Text("Toplam").frame(width: TrafficColumns.total, alignment: .trailing)
            Color.clear.frame(width: TrafficColumns.action, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, PocketSpacing.s)
    }
}

private struct TrafficGroupRow: View {
    let group: NetworkTrafficGroup
    let icon: NSImage?
    let canQuit: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PocketSpacing.m) {
                HStack(spacing: PocketSpacing.s) {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() } else { Image(systemName: "gearshape.2").foregroundStyle(.secondary) }
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: group.name).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if group.rows.count > 1 {
                        Button(action: toggle) {
                            Image(systemName: "chevron.right").rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(isExpanded ? "Süreçleri gizle" : "Süreçleri göster")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rate(group.downloadRate)
                rate(group.uploadRate)
                Text(verbatim: MenuBarFormatter.bytes(Double(group.sessionTotal), binary: false))
                    .frame(width: TrafficColumns.total, alignment: .trailing).foregroundStyle(.secondary)
                Group {
                    if canQuit {
                        Button(action: quit) { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless)
                            .help("Uygulamayı kapat")
                            .accessibilityLabel("Uygulamayı kapat")
                    } else { Color.clear.frame(height: 1) }
                }
                .frame(width: TrafficColumns.action)
            }
            .monospacedDigit()
            .padding(.vertical, PocketSpacing.s)
            if isExpanded, group.rows.count > 1 {
                ForEach(group.rows) { row in
                    HStack(spacing: PocketSpacing.m) {
                        Text(verbatim: "\(row.name) · \(row.pid)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            .padding(.leading, 30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rate(row.downloadRate).font(.callout)
                        rate(row.uploadRate).font(.callout)
                        Text(verbatim: MenuBarFormatter.bytes(Double(row.sessionTotal), binary: false)).font(.callout)
                            .frame(width: TrafficColumns.total, alignment: .trailing).foregroundStyle(.secondary)
                        Color.clear.frame(width: TrafficColumns.action, height: 1)
                    }
                    .monospacedDigit()
                    .padding(.bottom, PocketSpacing.xs)
                }
            }
        }
        .opacity(group.isActive ? 1 : 0.6)
    }

    private var subtitle: String {
        group.rows.count == 1 ? String(localized: "PID \(group.rows[0].pid)") : String(localized: "\(group.rows.count) süreç")
    }

    private func rate(_ value: Double) -> some View {
        Text(verbatim: value <= 0 ? "—" : value < 500 ? "< 1 KB/s" : MenuBarFormatter.rate(value, binary: false))
            .frame(width: TrafficColumns.rate, alignment: .trailing)
            .foregroundStyle(value > 0 ? .primary : .tertiary)
    }
}

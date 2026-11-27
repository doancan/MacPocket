import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class PortManagerModel: ObservableObject {
    @Published private(set) var owners: [PortOwner] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published var includeUDP = UserDefaults.standard.bool(forKey: "MacPocket.ports.includeUDP") {
        didSet {
            UserDefaults.standard.set(includeUDP, forKey: "MacPocket.ports.includeUDP")
            Task { await load() }
        }
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let arguments = ListeningPorts.arguments(includeUDP: includeUDP)
        do {
            // lsof can block for a long time on a stale network mount, so it runs bounded.
            let result = try await BoundedProcess.run("/usr/sbin/lsof", arguments, timeout: 15)
            // lsof exits 1 when nothing matches; that is an empty list, not a failure.
            guard result.status == 0 || result.status == 1 else {
                throw NSError(domain: "MacPocket.lsof", code: Int(result.status),
                              userInfo: [NSLocalizedDescriptionKey: String(localized: "lsof başarısız oldu (\(result.status)).")])
            }
            owners = ListeningPorts.parse(result.output)
            error = nil
            updatedAt = Date()
        } catch BoundedProcess.Failure.timedOut {
            self.error = String(localized: "lsof zaman aşımına uğradı.")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Tools → Port Yöneticisi: who listens on which port, whether it is reachable from the network, and stop it.
struct PortManagerView: View {
    var model: PocketModel
    @StateObject private var ports = PortManagerModel()
    @State private var search = ""
    @State private var exposedOnly = false
    @State private var autoRefresh = true
    @State private var pending: PortOwner?
    @FocusState private var searchFocused: Bool

    private var visible: [PortOwner] {
        ports.owners.filter { owner in
            (!exposedOnly || owner.isExposed)
                && (search.isEmpty || "\(owner.command) \(owner.pid) \(owner.ports.map(String.init).joined(separator: " ")) \(owner.sockets.compactMap(\.serviceName).joined(separator: " "))"
                    .localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Port Yöneticisi",
                              subtitle: "Bu Mac’te bağlantı bekleyen süreçleri, dinledikleri portları ve ağa açık olup olmadıklarını gör; gerekirse durdur.",
                              icon: "network") {
                Button { Task { await ports.load() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(ports.loading)
            }
            if let error = ports.error { PocketMessage(error, tone: .warning) }
            if let status = model.signalStatus { PocketMessage(status, tone: .neutral) }
            controls
            list
        }
        .pocketPage()
        .task { await ports.load() }
        .task(id: autoRefresh) {
            while autoRefresh, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard autoRefresh, !Task.isCancelled else { break }
                await ports.load()
            }
        }
        .confirmationDialog(pending.map { String(localized: "\($0.command) durdurulsun mu?") } ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let owner = pending {
                Button("Sonlandır") { stop(owner, force: false) }
                Button("Zorla sonlandır", role: .destructive) { stop(owner, force: true) }
            }
        } message: {
            if let owner = pending {
                Text("PID \(owner.pid) · port \(owner.ports.map(String.init).joined(separator: ", ")). Kaydedilmemiş veriler kaybolabilir; sistem için kritik süreçler sonlandırılmaz.")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketSearchField("Süreç, port veya servis ara…", text: $search, focus: $searchFocused).frame(maxWidth: 280)
            Toggle("Yalnız ağa açık olanlar", isOn: $exposedOnly).toggleStyle(.checkbox)
            Toggle("UDP’yi de göster", isOn: $ports.includeUDP).toggleStyle(.checkbox)
            Toggle("Otomatik yenile", isOn: $autoRefresh).toggleStyle(.checkbox)
            Spacer(minLength: PocketSpacing.s)
            if let updatedAt = ports.updatedAt {
                Text(updatedAt.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    @ViewBuilder private var list: some View {
        if ports.owners.isEmpty && !ports.loading {
            ContentUnavailableView("Dinleyen port yok", systemImage: "network.slash",
                                   description: Text("Kendi kullanıcının süreçlerinden hiçbiri bağlantı beklemiyor."))
                .frame(maxWidth: .infinity, minHeight: 240)
                .pocketCard()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, owner in
                        if index > 0 { Divider() }
                        PortOwnerRow(owner: owner, stop: { pending = owner })
                    }
                }
                .padding(.horizontal, PocketSpacing.l)
                .padding(.vertical, PocketSpacing.s)
            }
            .pocketCard(padding: 0)
            Text("\(visible.filter(\.isExposed).count) süreç ağdan gelen bağlantılara açık; diğerleri yalnız bu Mac’ten erişilebilir.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func stop(_ owner: PortOwner, force: Bool) {
        pending = nil
        Task {
            await model.refresh(includeProcesses: true)
            guard let entry = model.processes.first(where: { $0.pid == owner.pid }) else {
                model.signalStatus = String(localized: "PID \(owner.pid) artık çalışmıyor veya başka bir kullanıcıya ait.")
                await ports.load()
                return
            }
            await model.terminate(entry, force: force)
            try? await Task.sleep(for: .milliseconds(800))
            await ports.load()
        }
    }
}

private struct PortOwnerRow: View {
    let owner: PortOwner
    let stop: () -> Void
    @State private var hovering = false

    var body: some View {
        let application = NSRunningApplication(processIdentifier: owner.pid)
        HStack(alignment: .center, spacing: PocketSpacing.m) {
            Group {
                if let icon = application?.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "terminal").font(.system(size: 16)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PocketSpacing.s) {
                    Text(application?.localizedName ?? owner.command).font(.body.weight(.medium))
                    Text("PID \(owner.pid)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                PocketFlowLayout {
                    ForEach(owner.sockets, id: \.self) { socket in PortChip(socket: socket) }
                }
            }
            Spacer(minLength: PocketSpacing.m)
            if owner.isExposed {
                PocketStatusBadge(text: "Ağa açık", systemImage: "globe", tone: .warning)
                    .help("Diğer cihazlar bu portlara bağlanabilir (güvenlik duvarı izin veriyorsa).")
            } else {
                PocketStatusBadge(text: "Yalnız bu Mac", systemImage: "lock", tone: .success)
            }
            Button(action: stop) { Label("Durdur", systemImage: "stop.circle") }
                .controlSize(.small)
                .opacity(hovering ? 1 : 0.6)
        }
        .padding(.vertical, PocketSpacing.s)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Portu kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(owner.ports.map(String.init).joined(separator: ", "), forType: .string)
            }
            if let url = application?.bundleURL {
                Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("Durdur…", role: .destructive, action: stop)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PortChip: View {
    let socket: ListeningSocket

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: "\(socket.port)").monospacedDigit().fontWeight(.semibold)
            if let name = socket.serviceName { Text(verbatim: name).foregroundStyle(.secondary) }
            if socket.transport == .udp { Text(verbatim: "UDP").foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .help(Text(verbatim: "\(socket.transport.rawValue) \(socket.address):\(socket.port)"))
    }
}

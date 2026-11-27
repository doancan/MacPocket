import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class USBEjectModel: ObservableObject {
    @Published private(set) var drives: [EjectDrive] = []
    @Published private(set) var loaded = false
    @Published private(set) var refreshing = false
    @Published private(set) var ejecting = false
    @Published private(set) var checking: Set<String> = []
    @Published private(set) var usage: [String: DiskUsageReport] = [:]
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var error: String?
    @Published private(set) var success: String?
    @Published var selection: Set<String> = []
    @Published var expanded: Set<String> = []

    typealias ObserveChanges = @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void)?
    private let loadDrives: @Sendable () async throws -> [EjectDrive]
    private let observeChanges: ObserveChanges
    private var refreshAgain = false
    private var changes: AsyncStream<Void>.Continuation?
    private var runGeneration = UUID()

    init(loadDrives: @escaping @Sendable () async throws -> [EjectDrive] = { try await USBEject.load() },
         observeChanges: @escaping ObserveChanges = DiskChangeObservation.observe) {
        self.loadDrives = loadDrives
        self.observeChanges = observeChanges
    }

    func run() async {
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let generation = UUID()
        runGeneration = generation
        changes = continuation
        defer { if runGeneration == generation { changes = nil } }
        if let stop = observeChanges({ continuation.yield(()) }) {
            defer { stop(); continuation.finish() }
            for await _ in events {
                guard !Task.isCancelled else { return }
                await refresh()
            }
            return
        }
        continuation.finish()
        // Keep discovery working if Disk Arbitration cannot create a session.
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }

    func refresh(force: Bool = false) async {
        if refreshing { refreshAgain = true; return }
        guard !ejecting || force else { return }
        refreshing = true
        defer {
            refreshing = false
            loaded = true
            if refreshAgain { changes?.yield(()) }
        }
        repeat {
            refreshAgain = false
            do {
                let latest = try await loadDrives()
                guard !Task.isCancelled else { return }
                let previous = Set(drives.map(\.identity))
                let unchanged = Set(latest.filter { previous.contains($0.identity) }.map(\.id))
                usage = usage.filter { unchanged.contains($0.key) }
                failures = failures.filter { unchanged.contains($0.key) }
                if drives != latest { drives = latest }
                // A replugged drive can reuse the same BSD id; it must not inherit the user's previous
                // selection.
                selection.formIntersection(unchanged)
                expanded.formIntersection(unchanged)
                error = nil
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        } while refreshAgain && !Task.isCancelled
    }

    func inspect(_ drive: EjectDrive) async {
        guard !checking.contains(drive.id) else { return }
        checking.insert(drive.id)
        expanded.insert(drive.id)
        defer { checking.remove(drive.id) }
        do {
            let report = try await USBEject.usage(of: drive)
            guard drives.contains(where: { $0.identity == drive.identity }) else { return }
            usage[drive.id] = report
        } catch {
            if failures[drive.id] == nil { failures[drive.id] = error.localizedDescription }
        }
    }

    func eject(_ ids: Set<String>) async {
        guard !ejecting, !ids.isEmpty else { return }
        let targets = drives.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        ejecting = true
        success = nil
        defer { ejecting = false }
        var removed: [String] = []
        for drive in targets {
            failures[drive.id] = nil
            do {
                try await USBEject.eject(drive)
                removed.append(drive.name)
                selection.remove(drive.id)
                usage[drive.id] = nil
            } catch {
                failures[drive.id] = error.localizedDescription
                await inspect(drive)
            }
        }
        if !removed.isEmpty { success = String(localized: "\(removed.joined(separator: ", ")) güvenle çıkarıldı.") }
        await refresh(force: true)
    }
}

struct USBEjectView: View {
    @StateObject private var model = USBEjectModel()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "USB Çıkarma Yöneticisi",
                              subtitle: "Harici disklerini güvenle çıkar; diski kullanan uygulamaları ve açık dosyaları gör.",
                              icon: "eject.circle") {
                Button { Task { await model.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing || model.ejecting)
                Button { Task { await model.eject(model.selection) } } label: {
                    Label("Seçilenleri Çıkar (\(model.selection.count))", systemImage: "eject.fill")
                }
                .buttonStyle(.pocketPrimary)
                .disabled(model.selection.isEmpty || model.ejecting)
                .help("Çıkarmak istediğin diskleri listeden seç.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.m) {
                    if let error = model.error { PocketMessage(error, tone: .warning) }
                    if let success = model.success { PocketMessage(success, tone: .success) }
                    if model.ejecting { ProgressView("Diskler çıkarılıyor…").controlSize(.small) }
                    if !model.loaded {
                        ProgressView("Harici diskler okunuyor…").frame(maxWidth: .infinity, minHeight: 180)
                    } else if model.drives.isEmpty, model.error != nil {
                        ContentUnavailableView {
                            Label("Disk listesi alınamadı", systemImage: "externaldrive.badge.exclamationmark")
                        } description: {
                            Text("Bağlantıyı kontrol edip disk listesini yeniden yükle.")
                        } actions: {
                            Button("Yeniden Dene") { Task { await model.refresh() } }.disabled(model.refreshing)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220).pocketCard()
                    } else if model.drives.isEmpty {
                        ContentUnavailableView("Harici disk bağlı değil", systemImage: "externaldrive",
                                               description: Text("USB bellek veya harici SSD bağladığında burada görünür."))
                            .frame(maxWidth: .infinity, minHeight: 220).pocketCard()
                    } else {
                        Toggle("Tümünü Seç", isOn: Binding(get: {
                            !model.drives.isEmpty && model.selection.count == model.drives.count
                        }, set: { model.selection = $0 ? Set(model.drives.map(\.id)) : [] }))
                        .toggleStyle(.checkbox).disabled(model.ejecting)
                        ForEach(model.drives) { drive in driveRow(drive) }
                    }
                    Text("Diskin tüm bölümleri birlikte çıkarılır. İşlem tamamlandığında bağlantıyı kesebilirsin.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .task { await model.run() }
    }

    private func driveRow(_ drive: EjectDrive) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                Toggle(isOn: Binding(get: { model.selection.contains(drive.id) }, set: {
                    if $0 { model.selection.insert(drive.id) } else { model.selection.remove(drive.id) }
                })) { Text(verbatim: drive.name).font(.headline).lineLimit(2) }
                .toggleStyle(.checkbox).disabled(model.ejecting)
                Spacer(minLength: PocketSpacing.s)
                Text(verbatim: [drive.connection, pocketDiskBytes(drive.capacity), drive.id].joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button { Task { await model.eject([drive.id]) } } label: { Label("Çıkar", systemImage: "eject") }
                    .disabled(model.ejecting)
            }
            if drive.volumes.isEmpty {
                Label("Bağlı bölüm yok", systemImage: "externaldrive").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(drive.volumes) { volume in
                HStack {
                    Label { Text(verbatim: volume.name) } icon: { Image(systemName: "externaldrive") }
                    if let path = volume.mountPath {
                        Text(verbatim: path).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("Finder’da Göster") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                            .controlSize(.small).disabled(model.ejecting)
                    } else { Text("Bağlı değil").foregroundStyle(.secondary) }
                }.font(.callout)
            }
            if let failure = model.failures[drive.id] { PocketMessage(failure, tone: .warning) }
            DisclosureGroup(isExpanded: Binding(get: { model.expanded.contains(drive.id) }, set: {
                if $0 {
                    model.expanded.insert(drive.id)
                    if model.usage[drive.id] == nil { Task { await model.inspect(drive) } }
                } else { model.expanded.remove(drive.id) }
            })) {
                usage(drive).padding(.top, PocketSpacing.s)
            } label: { Text("Diski kullanan uygulamalar") }
            .disabled(model.ejecting)
        }
        .pocketCard()
    }

    @ViewBuilder private func usage(_ drive: EjectDrive) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            if model.checking.contains(drive.id) { ProgressView("Kullanım denetleniyor…").controlSize(.small) }
            if let report = model.usage[drive.id] {
                if report.users.isEmpty {
                    Text("Bu oturumda açık dosya bildirilmedi. macOS çıkarma sırasında yeniden denetler.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(report.users) { user in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let app = NSRunningApplication(processIdentifier: user.pid)
                            Text(verbatim: app?.localizedName ?? user.command).fontWeight(.medium)
                            Text(verbatim: "PID \(user.pid)").foregroundStyle(.secondary)
                            Spacer()
                            if let url = app?.bundleURL {
                                Button("Uygulamaya Git") { NSWorkspace.shared.open(url) }.controlSize(.small)
                            }
                        }
                        Text(String(localized: "\(user.files.count) açık dosya")).font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(user.files.prefix(5)), id: \.self) { path in
                            Text(verbatim: path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(.callout).padding(.vertical, 4)
                }
                if report.limited { PocketMessage(String(localized: "Bazı kullanım bilgileri okunamadı."), tone: .warning) }
            }
            Text("Yalnız bu oturumda erişilebilen süreçler gösterilir. Açık dosyaları kaydedip ilgili uygulamayı kapatarak yeniden deneyebilirsin.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Kullanımı Yenile") { Task { await model.inspect(drive) } }
                .controlSize(.small).disabled(model.checking.contains(drive.id))
        }
    }
}

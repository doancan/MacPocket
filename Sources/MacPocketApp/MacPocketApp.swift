import AppKit
import Combine
import SwiftUI
import MacPocketCore

@main
@MainActor
struct MacPocketApplication: App {
    @NSApplicationDelegateAdaptor(PocketAppDelegate.self) var delegate
    @StateObject private var state = PocketApplicationState()
    @AppStorage("MacPocket.appearance") private var appearance = PocketAppearance.dark

    var body: some Scene {
        Window("MacPocket", id: "main") {
            PocketRootView(model: state.model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(PocketTheme.accent)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands { PocketCommands(model: state.model) }

        Settings {
            PocketSettingsView(model: state.model, loginItem: state.loginItem)
                .preferredColorScheme(appearance.colorScheme)
        }

    }
}

@MainActor
final class PocketAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if PocketOperationState.shared.preventTermination {
            let alert = NSAlert()
            alert.messageText = "Uygulama işlemi sürüyor"
            alert.informativeText = "Homebrew işleminin tamamlanmasını beklemelisin. Sonucu Uygulamalar bölümünde görebilirsin."
            alert.addButton(withTitle: "Bekle")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
final class PocketModel: ObservableObject {
    @Published var system: SystemSnapshot?
    @Published var processes: [ProcessEntry] = []
    @Published var appPIDs: Set<Int32> = []
    @Published var paused = false
    @Published var refreshSeconds = 2.0 {
        didSet {
            if refreshSeconds != oldValue { UserDefaults.standard.set(refreshSeconds, forKey: "MacPocket.refreshSeconds") }
        }
    }
    let navigation = PocketNavigation()
    let storage = FileWorkspaceModel()
    let cleanup = FileWorkspaceModel(cleanup: true)
    let applications = ApplicationWorkspaceModel()
    @Published var error: String?
    @Published var lastUpdate: Date?
    @Published var unreadableCount = 0
    @Published var cpuHistory: [Double] = []
    @Published var signalStatus: String?
    @Published var terminatingPID: Int32?
    @Published var awakeSession: AwakeSession?
    @Published var awakeError: String?
    @Published var powerHistory: [PowerHistoryEntry] = []
    @Published var powerHistoryError: String?
    var mainWindowVisible = false
    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    let processMonitor = ProcessMonitor()
    let systemMonitor = SystemMonitor()
    let sleepController = SleepController()
    private let historyStore = PowerHistoryStore()
    private var historyLoaded = false
    private var subscriptions = Set<AnyCancellable>()
    private var refreshing = false
    private var pollingTask: Task<Void, Never>?

    init() {
        let interval = UserDefaults.standard.double(forKey: "MacPocket.refreshSeconds")
        if [1.0, 2.0, 5.0, 10.0].contains(interval) { refreshSeconds = interval }
        for (notification, event) in [(NSWorkspace.willSleepNotification, "Uyku"), (NSWorkspace.didWakeNotification, "Uyanma")] {
            NSWorkspace.shared.notificationCenter.publisher(for: notification).sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.recordPowerEvent(event) }
            }.store(in: &subscriptions)
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let seconds = await self?.monitoringTick() else { return }
                do { try await Task.sleep(for: .seconds(seconds)) }
                catch { return }
            }
        }
    }

    deinit { pollingTask?.cancel() }

    var cpuLabel: String {
        guard let user = system?.cpuUserPercent, let kernel = system?.cpuSystemPercent else { return "—" }
        return String(format: "%.0f%%", user + kernel)
    }

    private func monitoringTick() async -> Double {
        if !historyLoaded {
            do { powerHistory = try await historyStore.entries(); historyLoaded = true }
            catch { powerHistoryError = error.localizedDescription; historyLoaded = true }
        }
        awakeSession = await sleepController.status()
        if !paused { await refresh(includeProcesses: mainWindowVisible && navigation.tool == .taskManager) }
        return refreshSeconds
    }

    func refresh(includeProcesses: Bool = true) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let system = try await systemMonitor.snapshot()
            self.system = system
            if includeProcesses {
                let snapshot = try await processMonitor.snapshot()
                processes = snapshot.processes
                unreadableCount = snapshot.unreadableProcessCount
                appPIDs = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
            }
            lastUpdate = system.capturedAt
            do {
                if let entries = try await historyStore.record(system) { powerHistory = entries }
                powerHistoryError = nil
            } catch { powerHistoryError = error.localizedDescription }
            if let user = system.cpuUserPercent, let kernel = system.cpuSystemPercent {
                cpuHistory.append(user + kernel)
                if cpuHistory.count > 90 { cpuHistory.removeFirst(cpuHistory.count - 90) }
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func recordPowerEvent(_ event: String) async {
        do {
            let snapshot = try await systemMonitor.snapshot()
            if let entries = try await historyStore.record(snapshot, event: event) { powerHistory = entries }
        } catch { powerHistoryError = error.localizedDescription }
    }

    func startAwake(duration: Double = 1800, display: Bool = false) async {
        do {
            awakeSession = try await sleepController.start(durationSeconds: duration, keepDisplayAwake: display)
            awakeError = nil
        } catch { awakeError = error.localizedDescription }
    }

    func stopAwake() async {
        do {
            try await sleepController.stop()
            awakeSession = await sleepController.status()
            awakeError = nil
        } catch { awakeError = error.localizedDescription }
    }

    func terminate(_ entry: ProcessEntry, force: Bool) async {
        guard terminatingPID == nil else { return }
        terminatingPID = entry.pid
        defer { terminatingPID = nil }
        do {
            try await processMonitor.terminate(entry: entry, force: force)
            signalStatus = "PID \(entry.pid): istek gönderildi; çıkış bekleniyor."
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(250))
                await refresh()
                if !processes.contains(where: { $0.identity == entry.identity }) {
                    signalStatus = "\(entry.name) · PID \(entry.pid) sonlandı."
                    return
                }
            }
            signalStatus = "PID \(entry.pid) hâlâ çalışıyor. Listeyi yeniden kontrol et."
        } catch { signalStatus = error.localizedDescription }
    }
}

func pocketBytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
}

struct ResourceStrip: View {
    @ObservedObject var model: PocketModel
    var body: some View {
        HStack(spacing: 10) {
            ResourceTile(title: "CPU", value: model.system?.cpuUserPercent.map { String(format: "%.1f%%", $0 + (model.system?.cpuSystemPercent ?? 0)) } ?? "—",
                         detail: "\(model.system?.logicalCPUCount ?? 0) mantıksal çekirdek", color: PocketTheme.accent, history: model.cpuHistory)
            ResourceTile(title: "Fiziksel RAM", value: model.system.map { pocketBytes($0.physicalMemoryBytes) } ?? "—",
                         detail: model.system.map { "Wired \(pocketBytes($0.wiredMemoryBytes)) · Sıkıştırılmış \(pocketBytes($0.compressedMemoryBytes))" } ?? "Örnek bekleniyor", color: PocketTheme.memory)
            ResourceTile(title: "Disk · Boş alan", value: model.system?.volumes.first.map { pocketBytes(UInt64(max(0, $0.availableBytes))) } ?? "—",
                         detail: model.system?.volumes.first.map { "\($0.name) · \(pocketBytes(UInt64(max(0, $0.totalBytes))))" } ?? "—", color: PocketTheme.disk)
            ResourceTile(title: "Termal durum", value: model.system?.thermalState == "nominal" ? "Normal" : (model.system?.thermalState ?? "—"),
                         detail: model.system?.power.source ?? "Güç kaynağı bekleniyor", color: .orange)
        }
    }
}

struct ResourceTile: View {
    let title: String
    let value: String
    let detail: String
    let color: Color
    var history: [Double] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold)).foregroundStyle(color).monospacedDigit()
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            if !history.isEmpty { PocketGraph(values: history, color: color).frame(height: 18) }
        }.padding(12).frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading)
            .background(PocketTheme.panel).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(PocketTheme.line) }
    }
}

struct PocketGraph: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: geo.size.width * Double(index) / Double(max(1, values.count - 1)),
                                        y: geo.size.height * (1 - min(100, max(0, value)) / 100))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(color, lineWidth: 1.5)
        }
    }
}

struct PerformanceView: View {
    @ObservedObject var model: PocketModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Performans").font(.system(size: 23, weight: .semibold))
            ResourceStrip(model: model)
            Text("CPU · Toplam kullanım").font(.headline)
            PocketGraph(values: model.cpuHistory, color: PocketTheme.accent)
                .frame(height: 230).padding(16).background(PocketTheme.panel)
            if let s = model.system {
                Grid(alignment: .leading, horizontalSpacing: 35, verticalSpacing: 12) {
                    GridRow { Text("Kullanıcı / Sistem"); Text(String(format: "%.1f%% / %.1f%%", s.cpuUserPercent ?? 0, s.cpuSystemPercent ?? 0)) }
                    GridRow { Text("Ham boş RAM"); Text(pocketBytes(s.freeMemoryBytes)) }
                    GridRow { Text("Wired RAM"); Text(pocketBytes(s.wiredMemoryBytes)) }
                    GridRow { Text("Sıkıştırıcı fiziksel alanı"); Text(pocketBytes(s.compressedMemoryBytes)) }
                    GridRow { Text("Çalışma süresi"); Text(String(format: "%.1f gün", s.uptimeSeconds / 86400)) }
                }.font(.system(size: 12)).monospacedDigit()
            }
            Text("Ham boş RAM, Activity Monitor’daki kullanılabilir bellek değildir. Grafik yalnız bu oturumda toplanan örnekleri gösterir.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(22)
    }
}

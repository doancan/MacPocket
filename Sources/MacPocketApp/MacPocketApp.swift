import AppKit
import Combine
import SwiftUI
import MacPocketCore

@main
@MainActor
struct MacPocketApplication: App {
    @NSApplicationDelegateAdaptor(PocketAppDelegate.self) var delegate
    @StateObject private var state = PocketApplicationState.shared

    init() {
        // Must run before any localized string is resolved.
        PocketDefaults.applyLanguageDefault()
    }

    var body: some Scene {
        Window("MacPocket", id: "main") {
            PocketRootView(model: state.model)
                .pocketAppearanceRoot()
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands { PocketCommands(model: state.model) }

        Window("MacPocket’a Hoş Geldin", id: "onboarding") {
            OnboardingView(loginItem: state.loginItem)
                .pocketAppearanceRoot(rebuildsOnTokenChange: false)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        Settings {
            PocketSettingsView(model: state.model, loginItem: state.loginItem)
                .pocketAppearanceRoot(rebuildsOnTokenChange: false)
        }

    }
}

@MainActor
final class PocketAppDelegate: NSObject, NSApplicationDelegate {
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = PocketRelaunch.languageAtLaunch
        PocketDock.apply()
        // The Dock icon must come back if the menu bar item is hidden from anywhere (Settings, menu, import).
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { _ in
            MainActor.assumeIsolated { PocketDock.apply() }
        }
        if PocketLaunch.showsWindow { NSApp.activate(ignoringOtherApps: true) }
        #if DEBUG
        // Exercise the ordinary scan from the signed app, whose identifier the root helper requires.
        let arguments = CommandLine.arguments
        if arguments.contains("--open-practical") { PocketApplicationState.shared.model.navigation.select(.practical) }
        if arguments.contains("--open-case-converter") {
            PracticalWorkspace.shared.selected = .caseConverter
            PocketApplicationState.shared.model.navigation.select(.practical)
        }
        if let index = arguments.firstIndex(of: "--audit-practical"), arguments.indices.contains(index + 1) {
            let destination = URL(fileURLWithPath: arguments[index + 1])
            Task { @MainActor in await ToolUIAudit.runPractical(destination: destination) }
        }
        if let index = arguments.firstIndex(of: "--audit-tools"), arguments.indices.contains(index + 1) {
            let destination = URL(fileURLWithPath: arguments[index + 1])
            Task { @MainActor in await ToolUIAudit.run(destination: destination) }
        }
        if arguments.contains("--open-usb-eject") {
            PocketApplicationState.shared.model.navigation.open(.usbEject)
        }
        if let index = arguments.firstIndex(of: "--snapshot-main-window"), arguments.indices.contains(index + 1) {
            let destination = URL(fileURLWithPath: arguments[index + 1])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                // Render only our own view hierarchy; this does not capture the screen or other applications.
                guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }), let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: destination, options: .atomic)
            }
        }
        if let index = arguments.firstIndex(of: "--diagnose-weather"), arguments.indices.contains(index + 2) {
            let query = arguments[index + 1]
            let destination = URL(fileURLWithPath: arguments[index + 2])
            Task { @MainActor in
                var report: [String: Any] = [:]
                do {
                    let places = try await WeatherLocationSearch.find(query)
                    report["places"] = places.map { ["name": $0.name, "latitude": $0.latitude,
                                                    "longitude": $0.longitude, "timeZone": $0.timeZone] as [String: Any] }
                    if let place = places.first {
                        let result = try await WeatherClient.fetch(location: place, language: "tr")
                        report["temperature"] = result.current.temperature
                        report["hourlyCount"] = result.hourly.count
                        report["forecastCount"] = result.forecast.count
                        report["symbol"] = result.symbol
                        report["timeZone"] = result.timeZone.identifier
                        let settings = MenuBarModuleSettings.defaults(for: .weather)
                        report["menuBarText"] = MenuBarFormatter.reading(.weather, settings: settings, snapshot: nil, weather: result).lines
                    }
                } catch { report["error"] = error.localizedDescription }
                report["ui"] = PocketApplicationState.shared.statusItem.showWeatherForDiagnostics()
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: destination, options: .atomic)
                }
            }
        }
        if let index = arguments.firstIndex(of: "--diagnose-lan"), arguments.indices.contains(index + 1) {
            let destination = URL(fileURLWithPath: arguments[index + 1])
            Task { @MainActor in
                if arguments.contains("--restore-wizard-helper") {
                    try? await FanControlService.shared.restoreWizardRegistration()
                }
                PocketApplicationState.shared.model.navigation.open(.localNetwork)
                let model = LANScannerModel.shared
                await model.scan()
                while model.scanning { try? await Task.sleep(for: .milliseconds(100)) }
                let report: [String: Any] = [
                    "error": model.error ?? "",
                    "helper": String(describing: FanControlService.shared.availability),
                    "networks": model.results.map { result in [
                        "cidr": result.network.subnet.description,
                        "devices": result.devices.map { ["ip": $0.ip, "mac": $0.mac ?? "", "source": $0.macSource.rawValue] }
                    ] as [String: Any] },
                ]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: destination, options: .atomic)
                }
            }
        }
        #endif
    }

    /// Dock icon click with no window open (for example after "show window at launch" was turned off).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let open = PocketApplicationState.shared.model.openMainWindow else { return true }
        open()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if PocketOperationState.shared.preventTermination {
            let alert = NSAlert()
            alert.messageText = String(localized: "Uygulama işlemi sürüyor")
            alert.informativeText = String(localized: "Homebrew işleminin tamamlanmasını beklemelisin. Sonucu Uygulamalar bölümünde görebilirsin.")
            alert.addButton(withTitle: String(localized: "Bekle"))
            alert.runModal()
            return .terminateCancel
        }
        let defaults = UserDefaults.standard
        if PocketApplicationState.shared.model.awakeSession?.active == true,
           defaults.object(forKey: PocketPreferenceKey.confirmQuitWhileAwake) as? Bool ?? true {
            let alert = NSAlert()
            alert.messageText = String(localized: "Mac’i uyanık tutma etkin")
            alert.informativeText = String(localized: "MacPocket’tan çıkarsan uyanık tutma sona erer ve Mac yeniden normal şekilde uyuyabilir.")
            alert.addButton(withTitle: String(localized: "Çık"))
            alert.addButton(withTitle: String(localized: "Vazgeç"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = String(localized: "Bir daha sorma")
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if alert.suppressionButton?.state == .on { defaults.set(false, forKey: PocketPreferenceKey.confirmQuitWhileAwake) }
            if response != .alertFirstButtonReturn { return .terminateCancel }
        }
        PocketLaunch.terminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardService.shared.flushSave()
        ScreenTimeService.shared.flush()
        NightModeService.shared.prepareForQuit()
        DisplayBrightnessService.shared.restoreSoftwareDimming()
        AppFreezerService.shared.thawAll()
        FocusSessionService.shared.undoForQuit()
        VolumeMixerService.shared.stopAll()
        PocketRelaunch.spawnIfPending()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension PocketApplicationState {
    /// One per process; the app delegate reaches the model through it.
    static let shared = PocketApplicationState()
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
    @Published private(set) var samples: [PocketSample] = []
    @Published var signalStatus: String?
    @Published var terminatingPID: Int32?
    @Published var awakeSession: AwakeSession?
    @Published var awakeError: String?
    @Published var powerHistory: [PowerHistoryEntry] = []
    @Published var powerHistoryError: String?
    var mainWindowVisible = false
    /// Set by the menu bar while a popover showing top processes is open; process sampling is
    /// otherwise limited to the visible Task Manager.
    var menuBarProcessesWanted = false
    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    let processMonitor = ProcessMonitor()
    let systemMonitor = SystemMonitor()
    let sleepController = SleepController()
    private var historyDays = PowerHistoryRetention.days(from: .standard)
    private lazy var historyStore = PowerHistoryStore(maximumEntries: PowerHistoryRetention.maximumEntries(days: historyDays))
    private var historyLoaded = false
    private let alerts = PocketAlertNotifier()
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

    static let sampleCapacity = 150

    var cpuLabel: String { system?.cpuTotalPercent.map { pocketPercent($0) } ?? "—" }

    private func monitoringTick() async -> Double {
        let days = PowerHistoryRetention.days(from: .standard)
        if days != historyDays {
            // History length changed in Settings: reopen the log with the new bound.
            historyDays = days
            historyStore = PowerHistoryStore(maximumEntries: PowerHistoryRetention.maximumEntries(days: days))
            historyLoaded = false
        }
        if !historyLoaded {
            do { powerHistory = try await historyStore.entries(); historyLoaded = true }
            catch { powerHistoryError = error.localizedDescription; historyLoaded = true }
        }
        // Every @Published write notifies all observers, even with an equal value; publish only changes.
        let session = await sleepController.status()
        if session != awakeSession { awakeSession = session }
        if !paused {
            await refresh(includeProcesses: (mainWindowVisible && navigation.tool == .taskManager) || menuBarProcessesWanted)
        }
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
                if unreadableCount != snapshot.unreadableProcessCount { unreadableCount = snapshot.unreadableProcessCount }
                let pids = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
                if pids != appPIDs { appPIDs = pids }
            }
            lastUpdate = system.capturedAt
            alerts.evaluate(system)
            do {
                if let entries = try await historyStore.record(system) { powerHistory = entries }
                if powerHistoryError != nil { powerHistoryError = nil }
            } catch { powerHistoryError = error.localizedDescription }
            if let user = system.cpuUserPercent, let kernel = system.cpuSystemPercent {
                let memory = system.usedMemoryBytes.map { Double($0) / Double(max(1, system.physicalMemoryBytes)) }
                samples.append(PocketSample(date: system.capturedAt, cpuUser: user, cpuSystem: kernel, memoryUsedFraction: memory))
                if samples.count > Self.sampleCapacity { samples.removeFirst(samples.count - Self.sampleCapacity) }
            }
            if error != nil { error = nil }
        } catch { self.error = error.localizedDescription }
    }

    /// Deletes the stored power history (Settings → Advanced).
    func clearPowerHistory() async {
        do {
            try await historyStore.clear()
            powerHistory = []
            powerHistoryError = nil
        } catch { powerHistoryError = error.localizedDescription }
    }

    /// `event` is stored as-is ("Uyku"/"Uyanma" are persisted identifiers, localized when shown).
    private func recordPowerEvent(_ event: String) async {
        do {
            let snapshot = try await systemMonitor.snapshot()
            if let entries = try await historyStore.record(snapshot, event: event) { powerHistory = entries }
        } catch { powerHistoryError = error.localizedDescription }
    }

    static let awakeDisplayKey = "MacPocket.power.awakeDisplay"
    /// Users expect "keep awake" to keep the screen on, so the display is held unless they opt out.
    static let awakeDisplayDefault = true

    /// `duration` nil keeps the Mac awake until stopped; `display` nil follows the saved preference.
    func startAwake(duration: Double? = 1800, display: Bool? = nil) async {
        let keepDisplayAwake = display
            ?? (UserDefaults.standard.object(forKey: Self.awakeDisplayKey) as? Bool ?? Self.awakeDisplayDefault)
        do {
            awakeSession = try await sleepController.start(durationSeconds: duration, keepDisplayAwake: keepDisplayAwake)
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
            signalStatus = String(localized: "PID \(entry.pid): istek gönderildi; çıkış bekleniyor.")
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(250))
                await refresh()
                if !processes.contains(where: { $0.identity == entry.identity }) {
                    signalStatus = String(localized: "\(entry.name) · PID \(entry.pid) sonlandı.")
                    return
                }
            }
            signalStatus = String(localized: "PID \(entry.pid) hâlâ çalışıyor. Listeyi yeniden kontrol et.")
        } catch { signalStatus = error.localizedDescription }
    }
}

/// Chart-only ring buffer: ResourceStrip and the menu bar read the same live samples as the main window.
struct PocketSample: Identifiable, Sendable {
    let date: Date
    let cpuUser: Double
    let cpuSystem: Double
    let memoryUsedFraction: Double?
    var id: Date { date }
    var cpuTotal: Double { min(100, cpuUser + cpuSystem) }
}

struct ResourceStrip: View {
    @ObservedObject var model: PocketModel
    var body: some View {
        let system = model.system
        let volume = system?.volumes.first
        let usedMemory = system?.usedMemoryBytes
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PocketSpacing.m) { tiles(system, volume, usedMemory) }
            Grid(horizontalSpacing: PocketSpacing.m, verticalSpacing: PocketSpacing.m) {
                let views = Array(0..<4)
                GridRow { tile(views[0], system, volume, usedMemory); tile(views[1], system, volume, usedMemory) }
                GridRow { tile(views[2], system, volume, usedMemory); tile(views[3], system, volume, usedMemory) }
            }
        }
    }

    @ViewBuilder private func tiles(_ system: SystemSnapshot?, _ volume: VolumeSnapshot?, _ usedMemory: UInt64?) -> some View {
        ForEach(0..<4, id: \.self) { tile($0, system, volume, usedMemory) }
    }

    @ViewBuilder private func tile(_ index: Int, _ system: SystemSnapshot?, _ volume: VolumeSnapshot?, _ usedMemory: UInt64?) -> some View {
        switch index {
        case 0:
            PocketMetricTile(title: "CPU", value: "\(system?.cpuTotalPercent.map { pocketPercent($0, decimals: true) } ?? "—")",
                             detail: system.map { "\($0.logicalCPUCount) mantıksal çekirdek" } ?? "Örnek bekleniyor",
                             icon: "cpu", color: PocketTheme.accent, history: model.samples.map(\.cpuTotal))
        case 1:
            PocketMetricTile(title: "Bellek", value: "\(usedMemory.map(pocketBytes) ?? "—")",
                             detail: system.map { "\(pocketBytes($0.physicalMemoryBytes)) fiziksel · Sıkıştırılmış \(pocketBytes($0.compressedMemoryBytes))" } ?? "Örnek bekleniyor",
                             icon: "memorychip", color: PocketTheme.memory,
                             history: model.samples.compactMap(\.memoryUsedFraction).map { $0 * 100 })
        case 2:
            PocketMetricTile(title: "Disk · Boş", value: "\(volume.map { pocketDiskBytes($0.availableBytes) } ?? "—")",
                             detail: volume.map { "\($0.name) · \(pocketDiskBytes($0.totalBytes)) toplam" } ?? "—",
                             icon: "internaldrive", color: PocketTheme.disk)
        default:
            PocketMetricTile(title: "Termal durum", value: "\(pocketThermalTitle(system?.thermalState))",
                             detail: "Güç: \(pocketPowerSourceTitle(system?.power.source))",
                             icon: "thermometer.medium", color: pocketThermalTone(system?.thermalState).color)
        }
    }
}

import AppKit
import Foundation
import MacPocketCore

enum PowerTab: String, CaseIterable, Identifiable {
    case overview = "Genel Bakış"
    case battery = "Pil"
    case blockers = "Uyku Engelleyiciler"
    case energy = "Enerji Kullanımı"
    case settings = "Ayarlar"
    case history = "Geçmiş"
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .overview: String(localized: "Genel Bakış")
        case .battery: String(localized: "Pil")
        case .blockers: String(localized: "Uyku Engelleyiciler")
        case .energy: String(localized: "Enerji Kullanımı")
        case .settings: String(localized: "Ayarlar")
        case .history: String(localized: "Geçmiş")
        }
    }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .battery: "battery.75percent"
        case .blockers: "moon.zzz"
        case .energy: "bolt.horizontal"
        case .settings: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// A requested pmset change waiting for explicit confirmation.
struct PowerSettingChange: Identifiable, Equatable {
    let id = UUID()
    let profile: PMPowerProfile
    let key: PMSettingKey
    let currentValue: Int?
    var newValue: Int
}

struct PowerWattSample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let watts: Double
}

/// Page-scoped state of the Güç Merkezi. Created by the view; all polling stops when `run()` is cancelled.
@MainActor
final class PowerCenterModel: ObservableObject {
    @Published var tab: PowerTab = .overview
    @Published private(set) var overview: PowerOverview?
    @Published private(set) var wattHistory: [PowerWattSample] = []

    @Published private(set) var assertions: PMAssertionReport?
    @Published private(set) var assertionsError: String?
    @Published private(set) var thermal: PMThermalReport?

    @Published private(set) var profiles: [PMSettingsProfile] = []
    @Published private(set) var live: PMLiveSettings?
    @Published private(set) var settingsError: String?
    @Published private(set) var settingsLoading = false

    @Published private(set) var schedule: [PMScheduledEvent]?
    @Published private(set) var scheduleError: String?

    @Published private(set) var energy: ProcessEnergySample?
    @Published private(set) var energyError: String?

    @Published private(set) var logEvents: [PMLogEvent]?
    @Published private(set) var logLoading = false
    @Published private(set) var logError: String?

    @Published var pendingChange: PowerSettingChange?
    @Published private(set) var applying = false
    @Published var applyMessage: (text: String, success: Bool)?

    private let runner: any PMSetPrivilegedRunning
    private var sampler = ProcessEnergySampler()
    private var logTask: Task<Void, Never>?
    static let wattCapacity = 150

    init(runner: any PMSetPrivilegedRunning = AppleScriptPMSetRunner()) {
        self.runner = runner
    }

    // MARK: Polling

    /// Runs while the page is visible. Cheap IOKit reads every 2 s, pmset reads every 6 s,
    /// energy sampling every 3 s only on the tabs that show it.
    func run() async {
        sampler = ProcessEnergySampler()
        async let settings: Void = loadSettings()
        async let schedule: Void = loadSchedule()
        _ = await (settings, schedule)
        var tick = 0
        while !Task.isCancelled {
            refreshOverview()
            if tick % 3 == 0 { await refreshAssertionsAndThermal() }
            if tab == .energy || tab == .overview, tick % 3 == 1 || energy == nil { await refreshEnergy() }
            if tab == .history, logEvents == nil, !logLoading { loadLog() }
            tick += 1
            do { try await Task.sleep(for: .seconds(2)) } catch { break }
        }
        logTask?.cancel()
        logTask = nil
        if logLoading { logLoading = false }
    }

    func refreshOverview() {
        let next = PowerInspector.overview()
        let previous = overview
        overview = next
        if let watts = Self.currentWatts(next, previous: previous) {
            wattHistory.append(PowerWattSample(date: next.capturedAt, watts: watts))
            if wattHistory.count > Self.wattCapacity { wattHistory.removeFirst(wattHistory.count - Self.wattCapacity) }
        }
    }

    /// Whole-system input power: the instantaneous telemetry value, else the accumulator average since the
    /// previous read (desktops often report 0 instantaneously), else battery discharge power.
    static func currentWatts(_ overview: PowerOverview, previous: PowerOverview? = nil) -> Double? {
        if let milliwatts = overview.battery?.systemPowerInMilliwatts { return Double(milliwatts) / 1000 }
        if let battery = overview.battery, let earlier = previous?.battery,
           let average = battery.averageSystemWatts(since: earlier) { return average }
        if let watts = overview.battery?.batteryWatts, watts < 0 { return -watts }
        return nil
    }

    func refreshAssertionsAndThermal() async {
        do {
            assertions = try await PowerCommandReader.assertions()
            assertionsError = nil
        } catch is CancellationError {
            return
        } catch {
            assertionsError = error.localizedDescription
        }
        thermal = try? await PowerCommandReader.thermal()
    }

    func refreshEnergy() async {
        let sample = await sampler.sample(limit: 60)
        // The first call only primes the counters.
        if sample.interval > 0 { energy = sample }
        energyError = sample.readableCount == 0 ? String(localized: "Süreç enerji sayaçları okunamadı.") : nil
    }

    func loadSettings() async {
        settingsLoading = true
        defer { settingsLoading = false }
        do {
            let result = try await PowerCommandReader.settings()
            profiles = result.profiles
            live = result.live
            settingsError = nil
        } catch is CancellationError {
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func loadSchedule() async {
        do {
            schedule = try await PowerCommandReader.schedule()
            scheduleError = nil
        } catch is CancellationError {
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func loadLog() {
        logTask?.cancel()
        logLoading = true
        logError = nil
        logTask = Task { [weak self] in
            do {
                let events = try await PowerCommandReader.recentLogEvents(limit: 200)
                guard !Task.isCancelled else { return }
                self?.logEvents = events
            } catch is CancellationError {
                return
            } catch {
                self?.logError = error.localizedDescription
                self?.logEvents = []
            }
            self?.logLoading = false
        }
    }

    // MARK: Settings changes

    func request(profile: PMPowerProfile, key: PMSettingKey, value: Int) {
        let current = profiles.first { $0.profile == profile }?.value(key)?.number
        applyMessage = nil
        pendingChange = PowerSettingChange(profile: profile, key: key, currentValue: current, newValue: value)
    }

    /// Runs only after the confirmation sheet; the command is rebuilt and validated here.
    func apply(_ change: PowerSettingChange) async {
        guard !applying else { return }
        let command: PMSetCommand
        do { command = try PMSetCommand(scope: change.profile.scope, key: change.key, value: change.newValue) }
        catch {
            applyMessage = (error.localizedDescription, false)
            return
        }
        applying = true
        defer { applying = false }
        do {
            try await runner.run(command)
            await loadSettings()
            let now = profiles.first { $0.profile == change.profile }?.value(change.key)?.number
            if now == change.newValue {
                applyMessage = (String(localized: "\(change.key.title) (\(change.profile.title)): \(change.key.display(change.newValue)) olarak ayarlandı."), true)
            } else {
                let shown = now.map(change.key.display) ?? String(localized: "okunamadı")
                applyMessage = (String(localized: "Komut çalıştı ancak \(change.key.title) değeri \(shown) görünüyor. Bu Mac bu ayarı desteklemiyor olabilir."), false)
            }
        } catch {
            applyMessage = (error.localizedDescription, false)
        }
    }

    // MARK: Derived

    var hasBattery: Bool { overview?.hasBattery ?? false }

    var visibleTabs: [PowerTab] { PowerTab.allCases.filter { $0 != .battery || hasBattery } }

    /// System Settings pane: Battery on portables, Energy on desktops.
    func openSystemSettings() {
        let pane = hasBattery ? "com.apple.Battery-Settings.extension" : "com.apple.Energy-Saver-Settings.extension"
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}

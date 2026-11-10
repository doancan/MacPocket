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
@Observable
final class PowerCenterModel {
    var tab: PowerTab = .overview
    private(set) var overview: PowerOverview?
    private(set) var wattHistory: [PowerWattSample] = []

    private(set) var assertions: PMAssertionReport?
    private(set) var assertionsError: String?
    private(set) var thermal: PMThermalReport?

    private(set) var profiles: [PMSettingsProfile] = []
    private(set) var live: PMLiveSettings?
    private(set) var settingsError: String?
    private(set) var settingsLoading = false

    private(set) var schedule: [PMScheduledEvent]?
    private(set) var scheduleError: String?

    private(set) var energy: ProcessEnergySample?
    private(set) var energyError: String?

    private(set) var logEvents: [PMLogEvent]?
    private(set) var logLoading = false
    private(set) var logError: String?

    var pendingChange: PowerSettingChange?
    private(set) var applying = false
    var applyMessage: (text: String, success: Bool)?

    private let runner: any PMSetPrivilegedRunning
    @ObservationIgnored private var sampler = ProcessEnergySampler()
    @ObservationIgnored private var logTask: Task<Void, Never>?
    /// Most recent raw overview, including readings not published because only the timestamp changed.
    @ObservationIgnored private var lastOverviewReading: PowerOverview?
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
        let previous = lastOverviewReading
        lastOverviewReading = next
        // `capturedAt` is not shown; republishing an otherwise identical reading would redraw every card that
        // reads the overview every 2 s. Watt averaging below still uses the latest raw reading.
        if overview.map({ !$0.hasSameReading(as: next) }) ?? true { overview = next }
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

    /// Observation notifies readers on every write, even an equal one; the polling loop writes only changes.
    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PowerCenterModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func refreshAssertionsAndThermal() async {
        do {
            assign(\.assertions, try await PowerCommandReader.assertions())
            assign(\.assertionsError, nil)
        } catch is CancellationError {
            return
        } catch {
            assign(\.assertionsError, error.localizedDescription)
        }
        assign(\.thermal, try? await PowerCommandReader.thermal())
    }

    func refreshEnergy() async {
        let sample = await sampler.sample(limit: 60)
        // The first call only primes the counters.
        if sample.interval > 0 { assign(\.energy, sample) }
        assign(\.energyError, sample.readableCount == 0 ? String(localized: "Süreç enerji sayaçları okunamadı.") : nil)
    }

    func loadSettings() async {
        settingsLoading = true
        defer { settingsLoading = false }
        do {
            let result = try await PowerCommandReader.settings()
            assign(\.profiles, result.profiles)
            assign(\.live, result.live)
            assign(\.settingsError, nil)
        } catch is CancellationError {
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func loadSchedule() async {
        do {
            assign(\.schedule, try await PowerCommandReader.schedule())
            assign(\.scheduleError, nil)
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

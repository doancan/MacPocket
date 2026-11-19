import AppKit
import MacPocketCore
import Observation
import os

/// Long-range history, the event timeline and the health report behind the menu bar's Overview, Health and
/// Events pages. Fed with every snapshot by the status item controller; persisted to Application Support so
/// the 24-hour and 7-day charts and the timeline survive relaunches.
@MainActor @Observable
final class MenuBarInsights {
    static let shared = MenuBarInsights()

    private(set) var history = MetricHistory()
    private(set) var events = SystemEventLog()

    @ObservationIgnored private var detector = SystemEventDetector()
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let logger = Logger(subsystem: "com.doancan.MacPocket", category: "MenuBarInsights")

    /// Writes are batched: the history changes every second, and a lost few minutes after a crash is acceptable.
    private static let saveInterval: TimeInterval = 300

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPocket", isDirectory: true)
        history = load(MetricHistory.self, "metric-history.json") ?? MetricHistory()
        events = load(SystemEventLog.self, "system-events.json") ?? SystemEventLog()
        observeWorkspace()
    }

    func record(_ snapshot: SystemSnapshot) {
        history.record(MetricPoint(snapshot))
        events.append(detector.events(from: snapshot), now: snapshot.capturedAt)
        if snapshot.capturedAt.timeIntervalSince(lastSave) >= Self.saveInterval { save(now: snapshot.capturedAt) }
    }

    /// Days until the startup disk is full at the pace of the last week; nil while there is no shrinking trend.
    var diskDaysLeft: Double? {
        DiskForecast.daysUntilFull(history.points(.week).compactMap { point in point.diskFree.map { (point.date, $0) } })
    }

    func health(_ snapshot: SystemSnapshot, processes: [ProcessEntry]) -> HealthReport {
        let busiest = processes.filter(\.cpuSampleAvailable).max { $0.cpuPercent < $1.cpuPercent }
        return SystemHealth.evaluate(snapshot, busiestProcess: busiest.map(\.name), diskDaysLeft: diskDaysLeft)
    }

    func save(now: Date = Date()) {
        lastSave = now
        let history = history, events = events, directory = directory, logger = logger
        Task.detached(priority: .utility) { Self.write(history: history, events: events, to: directory, logger: logger) }
    }

    /// At quit the write cannot wait for a background task, which the exiting process would cut short.
    func saveBeforeQuitting() {
        Self.write(history: history, events: events, to: directory, logger: logger)
    }

    private nonisolated static func write(history: MetricHistory, events: SystemEventLog, to directory: URL, logger: Logger) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: directory.appendingPathComponent("metric-history.json"), options: .atomic)
            try JSONEncoder().encode(events).write(to: directory.appendingPathComponent("system-events.json"), options: .atomic)
        } catch {
            logger.error("Saving menu bar insights failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, _ name: String) -> Value? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            // An unreadable file starts a fresh history rather than blocking the menu bar.
            logger.error("Discarding unreadable \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Sleep, wake and disks come from the workspace, not from snapshots (nothing samples while the Mac sleeps).
    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        // Only the volume name crosses into the main actor; the notification itself is not Sendable.
        func on(_ name: Notification.Name, _ handle: @escaping @MainActor (_ volume: String?) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let volume = note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String
                MainActor.assumeIsolated { handle(volume) }
            })
        }
        on(NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.events.append([SystemEvent(date: Date(), kind: .sleep)], now: Date())
            self?.save()
        }
        on(NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.events.append([SystemEvent(date: Date(), kind: .wake)], now: Date())
        }
        on(NSWorkspace.didMountNotification) { [weak self] volume in
            self?.events.append([SystemEvent(date: Date(), kind: .diskMounted, detail: volume)], now: Date())
        }
        on(NSWorkspace.didUnmountNotification) { [weak self] volume in
            self?.events.append([SystemEvent(date: Date(), kind: .diskUnmounted, detail: volume)], now: Date())
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MenuBarInsights.shared.saveBeforeQuitting() }
        })
    }
}

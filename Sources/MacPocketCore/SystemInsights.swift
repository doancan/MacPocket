import Foundation

// MARK: - Disk forecast

/// When the startup disk fills up if it keeps shrinking at the pace of the recorded history.
public enum DiskForecast {
    /// Shortest history a trend is drawn from; a few minutes of noise is not a trend.
    public static let minimumSpan: TimeInterval = 6 * 3_600
    public static let minimumPoints = 12

    /// Days until the free space reaches zero by a least-squares line through `points` (date, free bytes);
    /// nil while the history is too short or the disk is not losing space.
    public static func daysUntilFull(_ points: [(date: Date, free: Double)]) -> Double? {
        guard points.count >= minimumPoints, let first = points.first, let last = points.last,
              last.date.timeIntervalSince(first.date) >= minimumSpan else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first.date) }, ys = points.map(\.free)
        let meanX = xs.reduce(0, +) / Double(xs.count), meanY = ys.reduce(0, +) / Double(ys.count)
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard variance > 0 else { return nil }
        let bytesPerSecond = covariance / variance
        guard bytesPerSecond < 0 else { return nil }
        return max(0, last.free / -bytesPerSecond / 86_400)
    }
}

// MARK: - Health

/// Something slowing the Mac down right now, with how serious it is.
public struct HealthIssue: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case cpuBusy, memoryPressure, swap, thermal, diskLow, diskFillingSoon }
    public enum Severity: Int, Sendable, Comparable {
        case warning, critical
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public let kind: Kind
    public let severity: Severity
    /// The process behind a busy CPU, the free share of the disk, the days left: what the message names.
    public var subject: String?
    public var value: Double?
    public var id: Kind { kind }
}

public struct HealthReport: Equatable, Sendable {
    /// 0…100; 100 when nothing is wrong.
    public let score: Int
    /// Most serious first.
    public let issues: [HealthIssue]
}

/// Scores the Mac's state from one snapshot. Thresholds follow what macOS itself reports (memory pressure
/// level, thermal state) and sustained load, never a momentary CPU spike.
public enum SystemHealth {
    public static let warningPenalty = 12
    public static let criticalPenalty = 25

    public static func evaluate(_ snapshot: SystemSnapshot, busiestProcess: String? = nil, diskDaysLeft: Double? = nil) -> HealthReport {
        var issues: [HealthIssue] = []
        // One-minute load per logical CPU: above 1 the CPUs have more work than they can run.
        if let load = snapshot.loadAverages?.first {
            let perCore = load / Double(max(1, snapshot.logicalCPUCount))
            if perCore >= 1.5 { issues.append(HealthIssue(kind: .cpuBusy, severity: .critical, subject: busiestProcess, value: perCore)) }
            else if perCore >= 1 { issues.append(HealthIssue(kind: .cpuBusy, severity: .warning, subject: busiestProcess, value: perCore)) }
        }
        switch snapshot.memoryPressureLevel {
        case 4: issues.append(HealthIssue(kind: .memoryPressure, severity: .critical))
        case 2: issues.append(HealthIssue(kind: .memoryPressure, severity: .warning))
        default: break
        }
        if let used = snapshot.swapUsedBytes, used >= 2 << 30 {
            issues.append(HealthIssue(kind: .swap, severity: used >= 8 << 30 ? .critical : .warning, value: Double(used)))
        }
        switch snapshot.thermalState.lowercased() {
        case "serious", "critical": issues.append(HealthIssue(kind: .thermal, severity: .critical))
        case "fair": issues.append(HealthIssue(kind: .thermal, severity: .warning))
        default: break
        }
        if let startup = snapshot.startupVolume, startup.totalBytes > 0 {
            let freeShare = Double(startup.availableBytes) / Double(startup.totalBytes)
            if freeShare < 0.05 { issues.append(HealthIssue(kind: .diskLow, severity: .critical, value: freeShare)) }
            else if freeShare < 0.10 { issues.append(HealthIssue(kind: .diskLow, severity: .warning, value: freeShare)) }
        }
        if let days = diskDaysLeft, !issues.contains(where: { $0.kind == .diskLow }) {
            if days < 7 { issues.append(HealthIssue(kind: .diskFillingSoon, severity: .critical, value: days)) }
            else if days < 30 { issues.append(HealthIssue(kind: .diskFillingSoon, severity: .warning, value: days)) }
        }
        let penalty = issues.reduce(0) { $0 + ($1.severity == .critical ? criticalPenalty : warningPenalty) }
        return HealthReport(score: max(0, 100 - penalty), issues: issues.sorted { $0.severity > $1.severity })
    }
}

// MARK: - Events

/// Something that happened to the Mac, for the timeline.
public struct SystemEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case sleep, wake, networkLost, networkRestored, thermalRaised, thermalNormal
        case memoryPressureCritical, memoryPressureNormal, diskMounted, diskUnmounted
    }

    public var id = UUID()
    public let date: Date
    public let kind: Kind
    /// A volume name or thermal state; nil when the kind says it all.
    public var detail: String?

    public init(date: Date, kind: Kind, detail: String? = nil) {
        self.date = date; self.kind = kind; self.detail = detail
    }
}

/// Turns consecutive snapshots into events: only changes are events, so a steady state logs nothing.
public struct SystemEventDetector: Sendable {
    private var previous: SystemSnapshot?
    public init() {}

    public mutating func events(from snapshot: SystemSnapshot) -> [SystemEvent] {
        defer { previous = snapshot }
        guard let previous else { return [] }
        var events: [SystemEvent] = []
        let date = snapshot.capturedAt
        if let was = previous.connectivity?.online, let now = snapshot.connectivity?.online, was != now {
            events.append(SystemEvent(date: date, kind: now ? .networkRestored : .networkLost))
        }
        let wasHot = Self.isElevated(previous.thermalState), isHot = Self.isElevated(snapshot.thermalState)
        if wasHot != isHot {
            events.append(SystemEvent(date: date, kind: isHot ? .thermalRaised : .thermalNormal, detail: snapshot.thermalState))
        }
        let wasCritical = previous.memoryPressureLevel == 4, isCritical = snapshot.memoryPressureLevel == 4
        if wasCritical != isCritical, previous.memoryPressureLevel != nil, snapshot.memoryPressureLevel != nil {
            events.append(SystemEvent(date: date, kind: isCritical ? .memoryPressureCritical : .memoryPressureNormal))
        }
        return events
    }

    static func isElevated(_ state: String) -> Bool { !["nominal", ""].contains(state.lowercased()) }
}

/// The timeline's events: newest last, at most `maximumCount` and none older than `maximumAge`.
public struct SystemEventLog: Codable, Sendable, Equatable {
    public static let maximumCount = 500
    public static let maximumAge: TimeInterval = 7 * 86_400
    public private(set) var events: [SystemEvent] = []

    public init(events: [SystemEvent] = []) { self.events = events }

    public mutating func append(_ new: [SystemEvent], now: Date) {
        guard !new.isEmpty else { return }
        events.append(contentsOf: new)
        events.sort { $0.date < $1.date }
        let oldest = now.addingTimeInterval(-Self.maximumAge)
        events.removeAll { $0.date < oldest }
        if events.count > Self.maximumCount { events.removeFirst(events.count - Self.maximumCount) }
    }
}

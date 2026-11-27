import Foundation

/// Everything here is opt-in and off by default. Nothing in this file touches the disk or the network: it
/// only decides.
public struct SystemDataAutomationSettings: Codable, Equatable, Sendable {
    public static let key = "MacPocket.systemData.automation"
    public static let allowedLowSpaceGigabytes = [5, 10, 20, 50]

    /// A scan in the background once a day, feeding the history the other alerts rely on.
    public var dailyScan = false
    public var lowSpaceAlert = false
    public var lowSpaceGigabytes = 10
    public var growthAlert = false
    public var weeklySummary = false
    /// Once a week, removes Safe items that need no password. The only thing MacPocket ever does on its own.
    public var autoClean = false

    public init() {}

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(to defaults: UserDefaults) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) } }

    /// Any alert or the clean needs fresh numbers, so they imply the daily scan.
    public var needsBackgroundScan: Bool { dailyScan || lowSpaceAlert || growthAlert || weeklySummary || autoClean }
    public var lowSpaceBytes: Int64 {
        Int64(Self.allowedLowSpaceGigabytes.contains(lowSpaceGigabytes) ? lowSpaceGigabytes : 10) * 1_000_000_000
    }
}

public struct SystemDataAutomationState: Codable, Equatable, Sendable {
    public static let key = "MacPocket.systemData.automationState"

    public var lastScan: Date?
    public var lastAutoClean: Date?
    public var lastWeeklySummary: Date?
    /// The low-space alert fires on the way down and stays quiet until free space has been back above the
    /// line.
    public var lowSpaceFired = false

    public init() {}

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(to defaults: UserDefaults) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) } }
}

public enum SystemDataAutomationAction: Equatable, Sendable {
    case lowSpace(freeBytes: Int64, safeBytes: Int64)
    case growth(SystemDataGrowthAlert)
    case weeklySummary(changeBytes: Int64, topGroup: SystemDataGroup?)
    case autoClean
}

public enum SystemDataAutomationPolicy {
    public static let scanInterval: TimeInterval = 86_400
    public static let weeklyThresholdBytes: Int64 = 2_000_000_000

    public static func isScanDue(_ settings: SystemDataAutomationSettings, state: SystemDataAutomationState, now: Date) -> Bool {
        guard settings.needsBackgroundScan else { return false }
        guard let last = state.lastScan else { return true }
        return now.timeIntervalSince(last) >= scanInterval
    }

    /// Decides what a finished scan should lead to and updates `state`. `watching` is true when the user
    /// started the scan from the open window: the clean never runs under someone's eyes, and alerts only for
    /// background scans.
    public static func decide(settings: SystemDataAutomationSettings, state: inout SystemDataAutomationState,
                              report: SystemDataReport, history: SystemDataHistory, watching: Bool, now: Date) -> [SystemDataAutomationAction] {
        state.lastScan = now
        var actions: [SystemDataAutomationAction] = []

        let free = report.freeBytes
        if report.totalBytes > 0 {
            if free >= settings.lowSpaceBytes {
                state.lowSpaceFired = false
            } else if settings.lowSpaceAlert, !state.lowSpaceFired, !watching {
                state.lowSpaceFired = true
                actions.append(.lowSpace(freeBytes: free, safeBytes: report.safeBytes))
            }
        }

        if settings.growthAlert, !watching {
            actions += history.growthAlerts().map(SystemDataAutomationAction.growth)
        }

        if settings.weeklySummary, !watching, isWeeklyDue(state.lastWeeklySummary, now: now) {
            state.lastWeeklySummary = now
            if let change = history.totalChange(currentBytes: report.systemDataBytes, overDays: 7, now: now), change > weeklyThresholdBytes {
                actions.append(.weeklySummary(changeBytes: change, topGroup: history.growthAlerts().first?.group ?? topGrowingGroup(report: report, history: history)))
            }
        }

        if settings.autoClean, !watching, SystemDataAutoClean.isDue(lastRun: state.lastAutoClean, now: now) {
            actions.append(.autoClean)
        }
        return actions
    }

    private static func isWeeklyDue(_ last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= 7 * 86_400
    }

    private static func topGrowingGroup(report: SystemDataReport, history: SystemDataHistory) -> SystemDataGroup? {
        guard let earlier = history.scans.last(where: { $0.date <= report.scannedAt.addingTimeInterval(-7 * 86_400) }) else { return nil }
        var now: [String: Int64] = [:]
        for item in report.items { now[item.group.rawValue, default: 0] += item.sizeBytes }
        return now.max { ($0.value - (earlier.groupBytes[$0.key] ?? 0)) < ($1.value - (earlier.groupBytes[$1.key] ?? 0)) }
            .flatMap { SystemDataGroup(rawValue: $0.key) }
    }
}

import Foundation

/// One calendar day of foreground app use.
public struct UsageDay: Codable, Equatable, Sendable {
    /// Seconds per app bundle identifier.
    public var apps: [String: Double] = [:]
    /// Seconds per hour of the day (0…23).
    public var hours: [Int: Double] = [:]
    /// How many times the frontmost app changed.
    public var switches = 0

    public init(apps: [String: Double] = [:], hours: [Int: Double] = [:], switches: Int = 0) {
        self.apps = apps; self.hours = hours; self.switches = switches
    }

    public var total: Double { apps.values.reduce(0, +) }
}

/// Foreground app time per day, split at hour and day boundaries. Kept small: one entry per app per day.
public struct UsageLedger: Codable, Equatable, Sendable {
    public static let retentionDays = 30
    /// Keyed by `dayKey` ("2026-11-04").
    public var days: [String: UsageDay] = [:]
    /// Last seen display name per bundle identifier.
    public var names: [String: String] = [:]

    public init(days: [String: UsageDay] = [:], names: [String: String] = [:]) {
        self.days = days; self.names = names
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds `app` as frontmost from `start` to `end`. Intervals crossing an hour (or midnight) are split so each
    /// hour and day gets its own share.
    public mutating func record(app: String, name: String, from start: Date, to end: Date, calendar: Calendar = .current) {
        guard end > start, !app.isEmpty else { return }
        names[app] = name
        var cursor = start
        while cursor < end {
            guard let hourStart = calendar.dateInterval(of: .hour, for: cursor) else { return }
            let sliceEnd = min(end, hourStart.end)
            let seconds = sliceEnd.timeIntervalSince(cursor)
            let key = Self.dayKey(cursor, calendar: calendar)
            let hour = calendar.component(.hour, from: cursor)
            days[key, default: UsageDay()].apps[app, default: 0] += seconds
            days[key, default: UsageDay()].hours[hour, default: 0] += seconds
            cursor = sliceEnd
        }
    }

    public mutating func countSwitch(at date: Date, calendar: Calendar = .current) {
        days[Self.dayKey(date, calendar: calendar), default: UsageDay()].switches += 1
    }

    public func day(_ date: Date, calendar: Calendar = .current) -> UsageDay {
        days[Self.dayKey(date, calendar: calendar)] ?? UsageDay()
    }

    /// The `count` days ending with `last`, oldest first.
    public func range(endingAt last: Date, count: Int, calendar: Calendar = .current) -> [(date: Date, day: UsageDay)] {
        let end = calendar.startOfDay(for: last)
        return (0..<max(1, count)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map { ($0, day($0, calendar: calendar)) }
        }
    }

    /// App totals over several days, longest first; ties by name for a stable order.
    public static func appTotals(_ days: [UsageDay], names: [String: String]) -> [(app: String, seconds: Double)] {
        var totals: [String: Double] = [:]
        for day in days { for (app, seconds) in day.apps { totals[app, default: 0] += seconds } }
        return totals.map { ($0.key, $0.value) }.sorted {
            $0.seconds != $1.seconds ? $0.seconds > $1.seconds : (names[$0.app] ?? $0.app) < (names[$1.app] ?? $1.app)
        }
    }

    /// Hour totals over several days (0…23, zeros included).
    public static func hourTotals(_ days: [UsageDay]) -> [Double] {
        (0..<24).map { hour in days.reduce(0) { $0 + ($1.hours[hour] ?? 0) } }
    }

    /// Drops days older than `keepingDays` (today counts as one).
    public mutating func prune(keepingDays: Int = retentionDays, now: Date = Date(), calendar: Calendar = .current) {
        guard let oldest = calendar.date(byAdding: .day, value: -(keepingDays - 1), to: calendar.startOfDay(for: now)) else { return }
        let cutoff = Self.dayKey(oldest, calendar: calendar)
        days = days.filter { $0.key >= cutoff }
        let used = Set(days.values.flatMap(\.apps.keys))
        names = names.filter { used.contains($0.key) }
    }

    public mutating func remove(app: String) {
        for key in days.keys {
            guard let seconds = days[key]?.apps.removeValue(forKey: app) else { continue }
            // Hour buckets don't know the app; take its share out proportionally so totals stay consistent.
            if var day = days[key] {
                let before = day.total + seconds
                if before > 0 { day.hours = day.hours.mapValues { $0 * (day.total / before) } }
                days[key] = day
            }
        }
        names.removeValue(forKey: app)
    }
}

/// Durations as the screen time page shows them: "2 sa 5 dk", "45 dk", "< 1 dk".
public enum UsageFormatter {
    public static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 { return seconds > 0 ? String(localized: "< 1 dk") : String(localized: "0 dk") }
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) dk") }
        return rest == 0 ? String(localized: "\(hours) sa") : String(localized: "\(hours) sa \(rest) dk")
    }
}

/// Apps that are never counted: the lock screen and the screen saver are not "use".
public enum UsageExclusions {
    public static let bundleIdentifiers: Set<String> = [
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.SecurityAgent", "com.apple.UserNotificationCenter",
    ]
}

/// Reads and writes the ledger as one small JSON file in Application Support.
public actor UsageStore {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPocket/screen-time.json")
    }

    public func load() -> UsageLedger {
        guard let data = try? Data(contentsOf: url), let ledger = try? JSONDecoder().decode(UsageLedger.self, from: data) else {
            return UsageLedger()
        }
        return ledger
    }

    public func save(_ ledger: UsageLedger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: url, options: .atomic)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

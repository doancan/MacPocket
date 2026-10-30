import Foundation

/// A timed focus session that changes a few things at once and puts back exactly what it changed.
public struct FocusSettings: Codable, Equatable, Sendable {
    public var minutes = 50
    public var keepAwake = true
    public var hideDesktopIcons = true
    /// Dim external displays other than the one in use to this level; nil leaves them alone.
    public var dimOtherDisplays: Double? = 0.35
    public var guardQuit = true
    /// Macros run when the session starts and ends (e.g. one that runs a Shortcut to turn on a Focus mode).
    public var startMacro: UUID?
    public var endMacro: UUID?

    public static let minuteChoices = [25, 50, 90, 120]
    public static let storageKey = "MacPocket.focus.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> FocusSettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(FocusSettings.self, from: $0) } ?? FocusSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// The state of the Mac before a session, as far as the session may change it.
public struct FocusEnvironment: Equatable, Sendable {
    public var desktopIconsVisible: Bool
    public var quitGuardOff: Bool
    /// External displays and their brightness, keyed by display ID.
    public var displayLevels: [UInt32: Double]
    /// The display the user works on; never dimmed.
    public var activeDisplay: UInt32?

    public init(desktopIconsVisible: Bool, quitGuardOff: Bool, displayLevels: [UInt32: Double], activeDisplay: UInt32?) {
        self.desktopIconsVisible = desktopIconsVisible; self.quitGuardOff = quitGuardOff
        self.displayLevels = displayLevels; self.activeDisplay = activeDisplay
    }
}

/// One change a session makes, with what to restore.
public enum FocusChange: Equatable, Sendable {
    case keepAwake(minutes: Int)
    case hideDesktopIcons
    case dimDisplay(UInt32, to: Double, from: Double)
    case guardQuit
    case runMacro(UUID)
}

public enum FocusPlanner {
    /// Changes to make now. Things already in the wanted state are skipped, so ending the session never undoes
    /// something the user had set up themselves.
    public static func start(_ settings: FocusSettings, environment: FocusEnvironment) -> [FocusChange] {
        var changes: [FocusChange] = []
        if settings.keepAwake { changes.append(.keepAwake(minutes: settings.minutes)) }
        if settings.hideDesktopIcons && environment.desktopIconsVisible { changes.append(.hideDesktopIcons) }
        if let level = settings.dimOtherDisplays {
            for (display, current) in environment.displayLevels.sorted(by: { $0.key < $1.key })
            where display != environment.activeDisplay && current > level + 0.01 {
                changes.append(.dimDisplay(display, to: level, from: current))
            }
        }
        if settings.guardQuit && environment.quitGuardOff { changes.append(.guardQuit) }
        if let macro = settings.startMacro { changes.append(.runMacro(macro)) }
        return changes
    }
}

public struct FocusSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let plannedMinutes: Int

    public init(start: Date, end: Date, plannedMinutes: Int) {
        self.start = start; self.end = end; self.plannedMinutes = plannedMinutes
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    public var completed: Bool { minutes >= plannedMinutes }
}

public struct FocusHistory: Codable, Equatable, Sendable {
    public private(set) var records: [FocusSessionRecord] = []
    public static let limit = 200
    public static let storageKey = "MacPocket.focus.history"

    public init(records: [FocusSessionRecord] = []) { self.records = records }

    public mutating func add(_ record: FocusSessionRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
    }

    /// Focused minutes on the calendar day of `date`.
    public func minutes(on date: Date, calendar: Calendar = .current) -> Int {
        records.filter { calendar.isDate($0.start, inSameDayAs: date) }.reduce(0) { $0 + $1.minutes }
    }

    /// Consecutive days, ending today or yesterday, with at least one completed session.
    public func streak(until date: Date, calendar: Calendar = .current) -> Int {
        let days = Set(records.filter(\.completed).map { calendar.startOfDay(for: $0.start) })
        var day = calendar.startOfDay(for: date)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    public static func load(from defaults: UserDefaults) -> FocusHistory {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(FocusHistory.self, from: $0) } ?? FocusHistory()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

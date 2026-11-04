import Foundation
import Darwin

/// Days for repeating power events, in IOKit's order: bit 0 is Monday, bit 6 is Sunday.
public struct PowerWeekdays: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue & 0x7F }

    public static let monday = Self(rawValue: 1 << 0)
    public static let tuesday = Self(rawValue: 1 << 1)
    public static let wednesday = Self(rawValue: 1 << 2)
    public static let thursday = Self(rawValue: 1 << 3)
    public static let friday = Self(rawValue: 1 << 4)
    public static let saturday = Self(rawValue: 1 << 5)
    public static let sunday = Self(rawValue: 1 << 6)
    public static let weekdays: Self = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekend: Self = [.saturday, .sunday]
    public static let everyDay: Self = [.weekdays, .weekend]

    /// Monday first, as the settings show them.
    public static let ordered: [Self] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    /// `pmset repeat` letters: "MTWRFSU".
    public var pmsetLetters: String {
        zip(Self.ordered, Array("MTWRFSU")).filter { contains($0.0) }.map { String($0.1) }.joined()
    }

    public var shortTitle: String {
        switch self {
        case .monday: String(localized: "Pzt")
        case .tuesday: String(localized: "Sal")
        case .wednesday: String(localized: "Çar")
        case .thursday: String(localized: "Per")
        case .friday: String(localized: "Cum")
        case .saturday: String(localized: "Cmt")
        case .sunday: String(localized: "Paz")
        default: ""
        }
    }

    public var summary: String {
        switch self {
        case .everyDay: String(localized: "her gün")
        case .weekdays: String(localized: "hafta içi")
        case .weekend: String(localized: "hafta sonu")
        case []: String(localized: "hiçbir gün")
        default: Self.ordered.filter(contains).map(\.shortTitle).joined(separator: ", ")
        }
    }
}

/// What a scheduled event does. `pmset` accepts these words as the event type.
public enum PowerEventKind: String, CaseIterable, Identifiable, Sendable {
    case wakeOrPowerOn = "wakeorpoweron"
    case wake
    case powerOn = "poweron"
    case sleep
    case shutdown

    public var id: String { rawValue }
    /// Repeating events come in one "on" and one "off" slot.
    public var isOn: Bool { self == .wakeOrPowerOn || self == .wake || self == .powerOn }
    public static var onKinds: [Self] { allCases.filter(\.isOn) }
    public static var offKinds: [Self] { allCases.filter { !$0.isOn } }

    public var title: String {
        switch self {
        case .wakeOrPowerOn: String(localized: "Uyandır veya aç")
        case .wake: String(localized: "Uyandır")
        case .powerOn: String(localized: "Aç")
        case .sleep: String(localized: "Uyut")
        case .shutdown: String(localized: "Kapat")
        }
    }

    public var symbol: String {
        switch self {
        case .wakeOrPowerOn, .powerOn: "power"
        case .wake: "sun.max"
        case .sleep: "moon.zzz"
        case .shutdown: "power.circle"
        }
    }

    /// IOKit reports "wakepoweron" for what `pmset` calls "wakeorpoweron".
    public init?(eventType: String) {
        switch eventType.lowercased() {
        case "wakepoweron", "wakeorpoweron": self = .wakeOrPowerOn
        case "wake": self = .wake
        case "poweron": self = .powerOn
        case "sleep": self = .sleep
        case "shutdown": self = .shutdown
        default: return nil
        }
    }
}

public struct RepeatingPowerEvent: Equatable, Sendable {
    public var kind: PowerEventKind
    /// Minutes after midnight.
    public var minutes: Int
    public var days: PowerWeekdays

    public init(kind: PowerEventKind, minutes: Int, days: PowerWeekdays) {
        self.kind = kind; self.minutes = min(max(0, minutes), 24 * 60 - 1); self.days = days
    }

    public var timeText: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    var pmsetTime: String { String(format: "%02d:%02d:00", minutes / 60, minutes % 60) }
}

public struct ScheduledPowerEvent: Equatable, Sendable, Identifiable {
    public let kind: PowerEventKind
    public let date: Date
    public let owner: String
    public var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)-\(owner)" }

    public init(kind: PowerEventKind, date: Date, owner: String) {
        self.kind = kind; self.date = date; self.owner = owner
    }
}

public struct PowerScheduleSnapshot: Equatable, Sendable {
    public var powerOn: RepeatingPowerEvent?
    public var powerOff: RepeatingPowerEvent?
    /// One-time events a person scheduled; the system's own invisible wakes are left out.
    public var scheduled: [ScheduledPowerEvent]

    public init(powerOn: RepeatingPowerEvent? = nil, powerOff: RepeatingPowerEvent? = nil, scheduled: [ScheduledPowerEvent] = []) {
        self.powerOn = powerOn; self.powerOff = powerOff; self.scheduled = scheduled
    }

    /// Parses `IOPMCopyRepeatingPowerEvents` and `IOPMCopyScheduledPowerEvents` results.
    public init(repeating: [String: Any]?, scheduled: [[String: Any]]?, now: Date = Date()) {
        func repeatingEvent(_ key: String) -> RepeatingPowerEvent? {
            guard let entry = repeating?[key] as? [String: Any],
                  let type = entry["eventtype"] as? String, let kind = PowerEventKind(eventType: type),
                  let minutes = (entry["time"] as? NSNumber)?.intValue,
                  let days = (entry["weekdays"] as? NSNumber)?.intValue else { return nil }
            return RepeatingPowerEvent(kind: kind, minutes: minutes, days: PowerWeekdays(rawValue: days))
        }
        let events = (scheduled ?? []).compactMap { entry -> ScheduledPowerEvent? in
            guard let type = entry["eventtype"] as? String, let kind = PowerEventKind(eventType: type),
                  let date = entry["time"] as? Date, date > now else { return nil }
            let owner = entry["scheduledby"] as? String ?? ""
            // Calendar, analytics and other system timers mark themselves invisible.
            if (entry["UserVisible"] as? Bool) == false || owner.contains("user-invisible") { return nil }
            return ScheduledPowerEvent(kind: kind, date: date, owner: owner)
        }
        self.init(powerOn: repeatingEvent("RepeatingPowerOn"), powerOff: repeatingEvent("RepeatingPowerOff"),
                  scheduled: events.sorted { $0.date < $1.date })
    }
}

/// Builds the `pmset` commands; every word comes from fixed values, so the result is safe for the administrator shell.
public enum PowerScheduleCommand {
    public static let owner = "MacPocket"
    static let pmset = "/usr/bin/pmset"

    /// Replaces the repeating pair. With neither event, cancels repeating events.
    public static func repeating(on: RepeatingPowerEvent?, off: RepeatingPowerEvent?) -> String {
        let events = [on, off].compactMap { $0 }.filter { !$0.days.isEmpty }
        guard !events.isEmpty else { return "\(pmset) repeat cancel" }
        let parts = events.map { "\($0.kind.rawValue) \($0.days.pmsetLetters) \($0.pmsetTime)" }
        // `repeat` replaces both slots, so cancel first to drop a slot the user turned off.
        return "\(pmset) repeat cancel && \(pmset) repeat " + parts.joined(separator: " ")
    }

    public static func schedule(_ kind: PowerEventKind, at date: Date) -> String {
        "\(pmset) schedule \(kind.rawValue) '\(dateText(date))' \(owner)"
    }

    public static func cancel(_ event: ScheduledPowerEvent) -> String {
        let owner = event.owner.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) } && !event.owner.isEmpty ? " \(event.owner)" : ""
        return "\(pmset) schedule cancel \(event.kind.rawValue) '\(dateText(event.date))'" + owner
    }

    /// `pmset` wants "MM/dd/yy HH:mm:ss" in local time.
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd/yy HH:mm:ss"
        return formatter.string(from: date)
    }
}

public enum PowerScheduleReader {
    public static func read() -> PowerScheduleSnapshot {
        let repeating = copy("IOPMCopyRepeatingPowerEvents") as? [String: Any]
        let scheduled = copy("IOPMCopyScheduledPowerEvents") as? [[String: Any]]
        return PowerScheduleSnapshot(repeating: repeating, scheduled: scheduled)
    }

    /// Both functions live in IOKit but aren't imported into Swift; they take no arguments and follow the Copy rule.
    private static func copy(_ symbol: String) -> CFTypeRef? {
        typealias Copier = @convention(c) () -> Unmanaged<CFTypeRef>?
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: Copier.self)()?.takeRetainedValue()
    }

    public static func apply(_ command: String) async throws {
        _ = try await AdministratorShell.run(command)
    }
}

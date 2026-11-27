import Foundation

// MARK: - Assertions (`pmset -g assertions`)

public enum PMAssertionEffect: String, Sendable, Comparable {
    case preventsSystemSleep, preventsDisplaySleep, userActivity, other

    private var rank: Int {
        switch self {
        case .preventsSystemSleep: 0
        case .preventsDisplaySleep: 1
        case .userActivity: 2
        case .other: 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    public var title: String {
        switch self {
        case .preventsSystemSleep: String(localized: "Sistem uykusunu engelliyor")
        case .preventsDisplaySleep: String(localized: "Ekran uykusunu engelliyor")
        case .userActivity: String(localized: "Kullanıcı etkinliği")
        case .other: String(localized: "Diğer")
        }
    }

    public var blocksSleep: Bool { self == .preventsSystemSleep || self == .preventsDisplaySleep }

    public init(type: String) {
        switch type {
        case "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion", "BackgroundTask",
             "ApplePushServiceTask", "NetworkClientActive", "SystemIsActive", "SoftwareUpdateTask",
             "PreventSystemSleepSecurityIndicator", "ExternalMedia":
            self = .preventsSystemSleep
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion":
            self = .preventsDisplaySleep
        case "UserIsActive":
            self = .userActivity
        default:
            self = .other
        }
    }
}

public func pmAssertionTypeTitle(_ type: String) -> String {
    switch type {
    case "PreventUserIdleSystemSleep": String(localized: "Boşta sistem uykusunu engelle")
    case "PreventSystemSleep": String(localized: "Sistem uykusunu engelle")
    case "NoIdleSleepAssertion": String(localized: "Boşta uykuyu engelle")
    case "PreventUserIdleDisplaySleep": String(localized: "Boşta ekran uykusunu engelle")
    case "NoDisplaySleepAssertion": String(localized: "Ekran uykusunu engelle")
    case "UserIsActive": String(localized: "Kullanıcı etkin")
    case "BackgroundTask": String(localized: "Arka plan görevi")
    case "ApplePushServiceTask": String(localized: "Anlık bildirim görevi")
    case "NetworkClientActive": String(localized: "Ağ istemcisi etkin")
    case "SystemIsActive": String(localized: "Sistem etkin")
    case "SoftwareUpdateTask": String(localized: "Yazılım güncelleme")
    case "ExternalMedia": String(localized: "Harici ortam")
    case "PreventSystemSleepSecurityIndicator": String(localized: "Güvenlik göstergesi")
    default: type
    }
}

public struct PMAssertion: Identifiable, Equatable, Sendable {
    public let id: String
    public let pid: Int32
    public let process: String
    public let ageSeconds: Int?
    public let type: String
    public let name: String
    public let details: [String]
    public var effect: PMAssertionEffect { PMAssertionEffect(type: type) }
    /// "Timeout will fire in 73 secs" if reported.
    public var timeoutSeconds: Int? {
        for line in details {
            guard let range = line.range(of: #"Timeout will fire in (\d+) secs"#, options: .regularExpression) else { continue }
            return Int(line[range].split(separator: " ")[4])
        }
        return nil
    }
}

public struct PMKernelAssertion: Identifiable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let owner: String
    public let detail: String
}

public struct PMAssertionReport: Equatable, Sendable {
    /// System-wide totals, e.g. `PreventUserIdleSystemSleep: 1`.
    public let systemWide: [String: Int]
    public let assertions: [PMAssertion]
    public let kernelAssertions: [PMKernelAssertion]

    public var sleepBlockers: [PMAssertion] { assertions.filter { $0.effect.blocksSleep } }
    public var preventsIdleSystemSleep: Bool {
        (systemWide["PreventUserIdleSystemSleep"] ?? 0) > 0 || (systemWide["PreventSystemSleep"] ?? 0) > 0
    }
    public var preventsIdleDisplaySleep: Bool { (systemWide["PreventUserIdleDisplaySleep"] ?? 0) > 0 }
}

public enum PMAssertionParser {
    private static let ownerPattern = try! NSRegularExpression(
        pattern: #"^\s*pid (\d+)\((.*)\): \[(0x[0-9A-Fa-f]+)\] (.+?) (\w+) named: "(.*)"\s*$"#)

    public static func parse(_ text: String) -> PMAssertionReport {
        enum Section { case none, system, owners, kernel }
        var section = Section.none
        var totals: [String: Int] = [:]
        var assertions: [PMAssertion] = []
        var kernel: [PMKernelAssertion] = []
        var pending: (pid: Int32, process: String, id: String, age: Int?, type: String, name: String, details: [String])?

        func flush() {
            if let item = pending {
                // Duplicate ids can appear across pmset revisions; keep the identifier unique for SwiftUI.
                let unique = assertions.contains { $0.id == item.id } ? "\(item.id)-\(assertions.count)" : item.id
                assertions.append(PMAssertion(id: unique, pid: item.pid, process: item.process, ageSeconds: item.age,
                                              type: item.type, name: item.name, details: item.details))
            }
            pending = nil
        }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Assertion status system-wide") { flush(); section = .system; continue }
            if trimmed.hasPrefix("Listed by owning process") { flush(); section = .owners; continue }
            if trimmed.hasPrefix("Kernel Assertions") { flush(); section = .kernel; continue }
            if trimmed.hasPrefix("Idle sleep preventers") || trimmed.hasPrefix("No kernel assertions") { flush(); section = .none; continue }
            switch section {
            case .none:
                continue
            case .system:
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count == 2, let value = Int(parts[1]) { totals[String(parts[0])] = value }
            case .owners:
                let range = NSRange(line.startIndex..., in: line)
                if let match = ownerPattern.firstMatch(in: line, range: range) {
                    flush()
                    func group(_ index: Int) -> String {
                        Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
                    }
                    pending = (Int32(group(1)) ?? 0, group(2), group(3), parseAge(group(4)), group(5), group(6), [])
                } else if raw.first == "\t" || line.hasPrefix("        "), pending != nil, !trimmed.isEmpty {
                    pending?.details.append(trimmed)
                }
            case .kernel:
                guard trimmed.hasPrefix("id=") else { continue }
                var fields: [String: String] = [:]
                var type = ""
                // `id=582  level=255 0x4=USB creat=… description=… owner=USB2.1 Hub`; owner is last and may
                // contain spaces.
                if let ownerRange = trimmed.range(of: " owner=") { fields["owner"] = String(trimmed[ownerRange.upperBound...]) }
                let head = trimmed.range(of: " owner=").map { String(trimmed[..<$0.lowerBound]) } ?? trimmed
                for token in head.split(separator: " ") {
                    let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2 else { continue }
                    if pair[0].hasPrefix("0x") { type = pair[1] } else { fields[pair[0]] = pair[1] }
                }
                kernel.append(PMKernelAssertion(id: fields["id"] ?? UUID().uuidString, type: type,
                                                owner: fields["owner"] ?? "", detail: fields["description"] ?? ""))
            }
        }
        flush()
        return PMAssertionReport(systemWide: totals, assertions: assertions, kernelAssertions: kernel)
    }

    /// `HH:MM:SS`, optionally preceded by a day count (`2d 01:02:03`).
    static func parseAge(_ text: String) -> Int? {
        var days = 0
        var clock = text.trimmingCharacters(in: .whitespaces)
        if let space = clock.lastIndex(of: " ") {
            let prefix = clock[..<space].filter(\.isNumber)
            days = Int(prefix) ?? 0
            clock = String(clock[clock.index(after: space)...])
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return days * 86_400 + parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}

// MARK: - Thermal (`pmset -g therm`)

public struct PMThermalReport: Equatable, Sendable {
    public let notes: [String]
    public let values: [String: Int]
    public var cpuSpeedLimit: Int? { values["CPU_Speed_Limit"] }
    public var schedulerLimit: Int? { values["CPU_Scheduler_Limit"] }
    public var availableCPUs: Int? { values["CPU_Available_CPUs"] }
    public var thermalWarningLevel: Int? { values["Thermal_Warning_Level"] ?? values["ThermalWarningLevel"] }
    public var performanceWarningLevel: Int? { values["Performance_Warning_Level"] ?? values["PerformanceWarningLevel"] }
    /// True when a limit below 100% was recorded.
    public var isThrottled: Bool { (cpuSpeedLimit ?? 100) < 100 || (schedulerLimit ?? 100) < 100 }
}

public enum PMThermalParser {
    public static func parse(_ text: String) -> PMThermalReport {
        var notes: [String] = []
        var values: [String: Int] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Note:") {
                notes.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                continue
            }
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, !pair[0].isEmpty, !pair[0].contains(" "), let value = Int(pair[1]) {
                values[pair[0]] = value
            }
        }
        return PMThermalReport(notes: notes, values: values)
    }
}

// MARK: - Sleep/wake log (`pmset -g log`)

public enum PMLogEventKind: String, Codable, Sendable, CaseIterable {
    case sleep, wake, darkWake, start, shutdown, restart, failure, displayOn, displayOff

    public var title: String {
        switch self {
        case .sleep: String(localized: "Uyku")
        case .wake: String(localized: "Uyanma")
        case .darkWake: String(localized: "Arka plan uyanması")
        case .start: String(localized: "Güç yönetimi başladı")
        case .shutdown: String(localized: "Kapanma")
        case .restart: String(localized: "Yeniden başlatma")
        case .failure: String(localized: "Hata")
        case .displayOn: String(localized: "Ekran açıldı")
        case .displayOff: String(localized: "Ekran kapandı")
        }
    }
}

public struct PMLogEvent: Identifiable, Equatable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)-\(message.hashValue)" }
    public let date: Date
    public let kind: PMLogEventKind
    public let message: String
    /// Text after "due to", e.g. "Idle Sleep" or "EC.LidOpen/Lid Open".
    public let reason: String?
    /// "AC" or "BATT" from "Using AC/BATT".
    public let powerSource: String?
    public let chargePercent: Int?
    public let durationSeconds: Int?
}

public enum PMLogParser {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    /// Cheap pre-filter for streaming: rejects the dominant "Assertions" rows without decoding the line.
    public static func isCandidate(_ line: Substring) -> Bool {
        guard line.count > 27, line.first?.isNumber == true else { return false }
        let type = line.dropFirst(26).prefix(12)
        return !type.hasPrefix("Assertions") && !type.hasPrefix("Kernel")
    }

    public static func parse(_ text: String) -> [PMLogEvent] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    public static func parseLine(_ line: String) -> PMLogEvent? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 2, fields[0].count > 26 else { return nil }
        let head = fields[0]
        let stamp = String(head.prefix(25))
        guard let date = formatter.date(from: stamp) else { return nil }
        let type = head.dropFirst(25).trimmingCharacters(in: .whitespaces)
        let message = fields[1]
        let kind: PMLogEventKind
        switch type {
        case "Sleep": kind = .sleep
        case "Wake": kind = .wake
        case "DarkWake": kind = .darkWake
        case "Start": kind = .start
        case "Shutdown", "Shutdown Cause": kind = .shutdown
        case "Restart": kind = .restart
        case "Failure", "Sleep Failure", "Wake Failure": kind = .failure
        case "Notification":
            if message.hasPrefix("Display is turned on") { kind = .displayOn }
            else if message.hasPrefix("Display is turned off") { kind = .displayOff }
            else { return nil }
        default:
            return nil
        }
        let duration = fields.count > 2 ? firstInt(in: fields[2], pattern: #"(\d+) secs?"#) : nil
        return PMLogEvent(date: date, kind: kind, message: message, reason: reason(in: message),
                          powerSource: firstMatch(in: message, pattern: #"Using (AC|BATT|UPS)"#),
                          chargePercent: firstInt(in: message, pattern: #"Charge:\s*(\d+)%"#),
                          durationSeconds: duration)
    }

    static func reason(in message: String) -> String? {
        if let quoted = firstMatch(in: message, pattern: #"due to '([^']+)'"#) { return quoted }
        guard let value = firstMatch(in: message, pattern: #"due to (.+?)(?: Using (?:AC|BATT|UPS)|$)"#) else { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func firstInt(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern).flatMap { Int($0) }
    }
}

// MARK: - Scheduled events (`pmset -g sched`)

public struct PMScheduledEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let repeating: Bool
    public let type: String
    /// Parsed one-shot date; repeating events keep their schedule in `when`.
    public let date: Date?
    public let when: String
    public let owner: String?

    public var typeTitle: String {
        switch type.lowercased() {
        case "wake": String(localized: "Uyan")
        case "wakeorpoweron", "wakepoweron": String(localized: "Uyan veya aç")
        case "poweron": String(localized: "PowerEvent.powerOn", defaultValue: "Aç")
        case "sleep": String(localized: "Uyu")
        case "shutdown": String(localized: "PowerEvent.shutDown", defaultValue: "Kapat")
        case "restart": String(localized: "Yeniden başlat")
        default: type
        }
    }
}

public enum PMScheduleParser {
    public static func parse(_ text: String) -> [PMScheduledEvent] {
        var events: [PMScheduledEvent] = []
        var repeating = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Repeating power events") { repeating = true; continue }
            if line.hasPrefix("Scheduled power events") { repeating = false; continue }
            guard !line.isEmpty else { continue }
            var body = line
            if body.hasPrefix("["), let close = body.firstIndex(of: "]") {
                body = body[body.index(after: close)...].trimmingCharacters(in: .whitespaces)
            }
            guard let atRange = body.range(of: " at ") else { continue }
            let type = String(body[..<atRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard !type.isEmpty, !type.contains(" ") else { continue }
            var rest = String(body[atRange.upperBound...])
            var owner: String?
            if let byRange = rest.range(of: " by '") {
                owner = String(rest[byRange.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "' "))
                rest = String(rest[..<byRange.lowerBound])
            }
            let when = rest.trimmingCharacters(in: .whitespaces)
            events.append(PMScheduledEvent(id: "\(events.count)-\(type)-\(when)", repeating: repeating, type: type,
                                           date: repeating ? nil : parseDate(when), when: when, owner: owner))
        }
        return events
    }

    static func parseDate(_ text: String) -> Date? {
        // pmset prints either a 2- or 4-digit year; a 4-digit pattern would read "26" as year 26.
        guard let datePart = text.split(separator: " ").first,
              let year = datePart.split(separator: "/").last else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = year.count == 2 ? "MM/dd/yy HH:mm:ss" : "MM/dd/yyyy HH:mm:ss"
        return formatter.date(from: text)
    }
}

// MARK: - Timeline merge

/// One row of the sleep/wake history combining `pmset -g log` with MacPocket's own records.
public struct PowerTimelineItem: Identifiable, Equatable, Sendable {
    public enum Origin: String, Sendable { case system, local }
    public let id: String
    public let date: Date
    public let kind: PMLogEventKind
    public let detail: String?
    public let chargePercent: Int?
    public let origin: Origin
}

public enum PowerTimeline {
    /// Merges system log events with local "Uyku"/"Uyanma" records, newest first. A local record within
    /// `tolerance` of a system event of the same kind is a duplicate; the system event (with its reason)
    /// wins.
    public static func merge(log: [PMLogEvent], local: [PowerHistoryEntry], tolerance: TimeInterval = 120,
                             limit: Int = 200) -> [PowerTimelineItem] {
        var items = log.map { event in
            PowerTimelineItem(id: "s-\(event.id)", date: event.date, kind: event.kind,
                              detail: event.reason ?? (event.kind == .start ? nil : event.message),
                              chargePercent: event.chargePercent, origin: .system)
        }
        for entry in local {
            let kind: PMLogEventKind
            switch entry.event {
            case "Uyku": kind = .sleep
            case "Uyanma": kind = .wake
            default: continue
            }
            let duplicate = log.contains { event in
                (event.kind == kind || (kind == .wake && event.kind == .darkWake))
                    && abs(event.date.timeIntervalSince(entry.date)) <= tolerance
            }
            guard !duplicate else { continue }
            items.append(PowerTimelineItem(id: "l-\(entry.id.uuidString)", date: entry.date, kind: kind,
                                           detail: String(localized: "MacPocket kaydı"), chargePercent: entry.chargePercent.map { Int($0.rounded()) },
                                           origin: .local))
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(limit))
    }
}

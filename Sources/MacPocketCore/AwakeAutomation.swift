import Foundation

public enum AwakeAutomationCondition: String, Codable, CaseIterable, Sendable, Identifiable {
    case applicationRunning, externalDisplay, externalPower
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .applicationRunning: String(localized: "Seçili uygulamalardan biri açık")
        case .externalDisplay: String(localized: "Harici ekran bağlı")
        case .externalPower: String(localized: "Şebeke gücüne bağlı")
        }
    }
}
public enum AwakeAutomationMatch: String, Codable, CaseIterable, Sendable, Identifiable {
    case all, any
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .all: String(localized: "Tüm koşullar")
        case .any: String(localized: "En az bir koşul")
        }
    }
}
public struct AwakeAutomationSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var conditions: Set<AwakeAutomationCondition> = []
    public var match = AwakeAutomationMatch.all
    public var applicationIDs: Set<String> = []
    public var applicationNames: [String: String] = [:]
    public var maximumMinutes = 120
    public var keepDisplayAwake = false
    public var pauseWhenLocked = true
    public init() {}
    public static let key = "MacPocket.power.awakeAutomation"
    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(to defaults: UserDefaults) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) } }
    public var durationSeconds: Double { Double(maximumMinutes > 0 && maximumMinutes <= 10_080 ? maximumMinutes : 120) * 60 }
    public var validApplicationIDs: Set<String> { Set(applicationIDs.filter(ApplicationUpdateURL.validBundleID).sorted().prefix(128)) }
}
public struct AwakeAutomationInput: Sendable {
    public var runningApplicationIDs: Set<String>
    public var externalDisplay: Bool?
    public var externalPower: Bool?
    public var locked: Bool?
    public var uptime: TimeInterval
    public init(runningApplicationIDs: Set<String>, externalDisplay: Bool?, externalPower: Bool?, locked: Bool?, uptime: TimeInterval) {
        self.runningApplicationIDs = runningApplicationIDs
        self.externalDisplay = externalDisplay
        self.externalPower = externalPower
        self.locked = locked
        self.uptime = uptime
    }
}
public enum AwakeAutomationStatus: Sendable, Equatable {
    case disabled, configure, waiting, locked, manualSession, manualPause, limitReached, ready, clockUnavailable
    public var localizedTitle: String {
        switch self {
        case .disabled: String(localized: "Otomasyon kapalı")
        case .configure: String(localized: "Koşulları yapılandır")
        case .waiting: String(localized: "Koşulların sağlanması bekleniyor")
        case .locked: String(localized: "Oturum kilitliyken otomasyon duraklatıldı")
        case .manualSession: String(localized: "Elle başlatılan oturum öncelikli")
        case .manualPause: String(localized: "Elle durduruldu; koşulların yeniden sağlanması bekleniyor")
        case .limitReached: String(localized: "Otomasyonun süre sınırına ulaşıldı")
        case .ready: String(localized: "Koşullar sağlandı")
        case .clockUnavailable: String(localized: "Otomasyon için süre bilgisi alınamadı")
        }
    }
}
public struct AwakeAutomationDecision: Sendable, Equatable {
    public let status: AwakeAutomationStatus
    public let matching: Set<AwakeAutomationCondition>
    public let remainingSeconds: Double?
    public var shouldHold: Bool { status == .ready && remainingSeconds != nil }
}

/// Pure policy. A condition cycle has one monotonic budget, including pauses and a lost/expired assertion.
public struct AwakeAutomationPolicy: Sendable {
    private var startedAt: TimeInterval?
    private var suppressed = false
    public init() {}
    public mutating func reset() { startedAt = nil; suppressed = false }
    public mutating func pauseForManualControl() { suppressed = true }
    public mutating func evaluate(_ settings: AwakeAutomationSettings, input: AwakeAutomationInput, manualSession: Bool) -> AwakeAutomationDecision {
        var matching: Set<AwakeAutomationCondition> = []
        func result(_ status: AwakeAutomationStatus, remaining: Double? = nil) -> AwakeAutomationDecision {
            .init(status: status, matching: matching, remainingSeconds: remaining)
        }
        guard settings.enabled else { reset(); return result(.disabled) }
        guard !settings.conditions.isEmpty,
              !settings.conditions.contains(.applicationRunning) || !settings.validApplicationIDs.isEmpty else {
            reset()
            return result(.configure)
        }
        for condition in settings.conditions {
            let matched: Bool
            switch condition {
            case .applicationRunning: matched = !settings.validApplicationIDs.isDisjoint(with: input.runningApplicationIDs)
            case .externalDisplay: matched = input.externalDisplay == true
            case .externalPower: matched = input.externalPower == true
            }
            if matched { matching.insert(condition) }
        }
        let satisfied = settings.match == .all ? matching == settings.conditions : !matching.isEmpty
        guard satisfied else { reset(); return result(.waiting) }
        if manualSession { suppressed = true; return result(.manualSession) }
        if suppressed { return result(.manualPause) }
        if settings.pauseWhenLocked, input.locked != false { return result(.locked) }
        guard input.uptime.isFinite, input.uptime >= 0 else { return result(.clockUnavailable) }
        if startedAt == nil { startedAt = input.uptime }
        guard let startedAt, input.uptime >= startedAt else { return result(.clockUnavailable) }
        let remaining = settings.durationSeconds - (input.uptime - startedAt)
        guard remaining > 0 else { return result(.limitReached) }
        return result(.ready, remaining: remaining)
    }
}

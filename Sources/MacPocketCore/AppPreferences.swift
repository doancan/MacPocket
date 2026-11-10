import Foundation
import CoreFoundation

// MARK: - Language

/// The app-wide language choice. "System" follows the macOS language order; the others pin the app
/// to one localization by writing the app-domain `AppleLanguages` default, which macOS reads at launch.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, turkish = "tr", english = "en"

    public static let defaultsKey = "AppleLanguages"
    public var id: String { rawValue }

    /// Maps an app-domain `AppleLanguages` value back to a choice. Nil or an unsupported first language means system.
    public init(appleLanguages: [String]?) {
        guard let first = appleLanguages?.first?.lowercased() else { self = .system; return }
        if first == "tr" || first.hasPrefix("tr-") || first.hasPrefix("tr_") { self = .turkish }
        else if first == "en" || first.hasPrefix("en-") || first.hasPrefix("en_") { self = .english }
        else { self = .system }
    }

    /// The value to store under `AppleLanguages`; nil removes the override.
    public var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .turkish: ["tr"]
        case .english: ["en"]
        }
    }

    /// Reads only the app's own domain: `UserDefaults.array(forKey:)` would also return the global language list.
    public static func load(from defaults: UserDefaults, domain: String) -> AppLanguage {
        AppLanguage(appleLanguages: defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String])
    }

    /// App-domain `AppleLocale`, kept in step with the pinned language so `Locale.current` speaks it.
    /// SwiftUI resolves `Text` literals through the bundle's cached string table only when the environment
    /// locale is `Locale.current`; any other locale reloads the table from disk for every literal.
    public static let localeKey = "AppleLocale"

    /// The system-wide locale identifier (for example `en_TR`), ignoring this app's own override.
    public static var systemLocaleIdentifier: String? {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[localeKey] as? String
    }

    /// `systemLocale` with only its language replaced (region, calendar and other keywords are kept);
    /// nil for `.system` or when there is no system locale to adapt.
    public func appleLocale(systemLocale: String?) -> String? {
        guard let language = appleLanguages?.first, let systemLocale, !systemLocale.isEmpty else { return nil }
        var components = Locale.Components(identifier: systemLocale)
        components.languageComponents.languageCode = Locale.LanguageCode(language)
        return Locale(components: components).identifier
    }

    public func save(to defaults: UserDefaults, systemLocale: String? = AppLanguage.systemLocaleIdentifier) {
        if let appleLanguages { defaults.set(appleLanguages, forKey: Self.defaultsKey) }
        else { defaults.removeObject(forKey: Self.defaultsKey) }
        alignLocale(in: defaults, systemLocale: systemLocale)
    }

    /// Writes or removes the app-domain `AppleLocale` to match this choice; also run at launch so a changed
    /// system region is picked up. Takes effect for `Locale.current` from the next launch at the latest.
    public func alignLocale(in defaults: UserDefaults, systemLocale: String? = AppLanguage.systemLocaleIdentifier) {
        if let locale = appleLocale(systemLocale: systemLocale) {
            if defaults.string(forKey: Self.localeKey) != locale { defaults.set(locale, forKey: Self.localeKey) }
        } else {
            defaults.removeObject(forKey: Self.localeKey)
        }
    }
}

// MARK: - Settings export / import

public enum SettingsTransferError: Error, LocalizedError, Equatable, Sendable {
    case unreadable
    case wrongFormat
    case unsupportedVersion(Int)
    case invalidValue(String)
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Ayar dosyası okunamadı.")
        case .wrongFormat: String(localized: "Bu dosya bir MacPocket ayar dosyası değil.")
        case .unsupportedVersion(let version): String(localized: "Ayar dosyası sürümü desteklenmiyor (\(version)).")
        case .invalidValue(let key): String(localized: "Ayar dosyasında geçersiz bir değer var (\(key)). Mevcut ayarlar korunuyor.")
        case .tooLarge: String(localized: "Ayar dosyası çok büyük (en fazla 8 MB).")
        }
    }
}

/// Serialises MacPocket's own preferences (keys starting with `MacPocket.` or `switcher.`) to JSON and back.
/// Data and Date values are wrapped so the file stays plain JSON.
public enum SettingsTransfer {
    public static let format = "MacPocket.settings"
    public static let version = 1
    public static let keyPrefixes = ["MacPocket.", "switcher."]
    public static let maximumFileBytes = 8 * 1024 * 1024

    public static func isTransferable(_ key: String) -> Bool {
        keyPrefixes.contains { key.hasPrefix($0) && key.count > $0.count }
    }

    /// Only transferable keys whose values can be represented are kept.
    public static func filtered(_ values: [String: Any]) -> [String: Any] {
        values.filter { isTransferable($0.key) && encode($0.value) != nil }
    }

    public static func exportData(from values: [String: Any]) throws -> Data {
        let encoded = values.compactMapValues(encode).filter { isTransferable($0.key) }
        let document: [String: Any] = ["format": format, "version": version, "values": encoded]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        guard data.count <= maximumFileBytes else { throw SettingsTransferError.tooLarge }
        return data
    }

    public static func importValues(from data: Data) throws -> [String: Any] {
        guard data.count <= maximumFileBytes else { throw SettingsTransferError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw SettingsTransferError.unreadable }
        guard let document = object as? [String: Any], document["format"] as? String == format,
              let values = document["values"] as? [String: Any] else { throw SettingsTransferError.wrongFormat }
        let number = document["version"] as? NSNumber
        let fileVersion = number.flatMap { n in
            CFGetTypeID(n) != CFBooleanGetTypeID() && n.doubleValue == Double(n.intValue) ? n.intValue : nil
        } ?? 0
        guard fileVersion >= 1 && fileVersion <= version else { throw SettingsTransferError.unsupportedVersion(fileVersion) }
        var decoded: [String: Any] = [:]
        for (key,value) in values where isTransferable(key) {
            guard let result = decode(value),validSwitcherValue(result,for: key) else { throw SettingsTransferError.invalidValue(key) }
            decoded[key] = result
        }
        return decoded
    }

    /// Read at most the admitted size, even when a selected file is much larger or changes size.
    public static func readImportData(from url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maximumFileBytes {
            let count = min(64 * 1024,maximumFileBytes + 1 - data.count)
            guard let chunk = try file.read(upToCount: count),!chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= maximumFileBytes else { throw SettingsTransferError.tooLarge }
        return data
    }

    /// Parse and validate every selected value before any preference changes.
    public static func importAndApply(_ data: Data,to defaults: UserDefaults,domain: String) throws {
        let values = try importValues(from: data)
        apply(values,to: defaults,domain: domain)
    }

    /// One domain replacement avoids exposing a reset-then-write intermediate state to observers.
    /// Unrelated defaults, including the language and other applications' keys, are preserved.
    public static func apply(_ values: [String: Any], to defaults: UserDefaults, domain: String) {
        var next = defaults.persistentDomain(forName: domain) ?? [:]
        next = next.filter { !isTransferable($0.key) }
        next.merge(filtered(values)) { _,new in new }
        // Imported disabled shortcuts must survive first module startup instead of being enabled
        // again by the old first-run migration when the archive omitted this internal marker.
        if values["switcher.globalEnabled"] != nil { next["switcher.cardOverlayConfigured"] = true }
        defaults.setPersistentDomain(next,forName: domain)
    }

    public static func reset(_ defaults: UserDefaults, domain: String) {
        let remaining = (defaults.persistentDomain(forName: domain) ?? [:]).filter { !isTransferable($0.key) }
        defaults.setPersistentDomain(remaining,forName: domain)
    }

    public static func currentValues(_ defaults: UserDefaults, domain: String) -> [String: Any] {
        filtered(defaults.persistentDomain(forName: domain) ?? [:])
    }

    private struct ImportedShortcutIdentity: Decodable { let id: UUID }
    private static func validSwitcherValue(_ value: Any,for key: String) -> Bool {
        switch key {
        case SwitcherShortcutStore.key:
            guard let data = value as? Data,let identities = try? JSONDecoder().decode([ImportedShortcutIdentity].self,from: data),
                  let list = try? JSONDecoder().decode([SwitcherShortcut].self,from: data),identities.count == list.count else { return false }
            return SwitcherShortcutValidation.problems(list).isEmpty && Set(list.map(\.id)).count == list.count
        case SwitcherActionBindings.key:
            guard let data = value as? Data,let list = try? JSONDecoder().decode([SwitcherActionBinding].self,from: data) else { return false }
            let merged = SwitcherActionBinding.defaults.map { original in list.first { $0.action == original.action } ?? original }
            return SwitcherActionBindings.problems(list).isEmpty && SwitcherActionBindings.problems(merged).isEmpty
        case SwitcherExceptionStore.key:
            guard let data = value as? Data,let list = try? JSONDecoder().decode([SwitcherExceptionRule].self,from: data) else { return false }
            return list.count <= SwitcherExceptionStore.maximumCount && Set(list.map(\.id)).count == list.count && list.allSatisfy { $0.validationMessage == nil }
        default: return true // Preserve compatible legacy and future preferences byte-for-byte.
        }
    }

    private static func encode(_ value: Any) -> Any? {
        switch value {
        case let data as Data: return ["$data": data.base64EncodedString()]
        case let date as Date: return ["$date": date.timeIntervalSince1970]
        case let string as String: return string
        case let number as NSNumber: return number
        case let array as [Any]:
            let items = array.compactMap(encode)
            return items.count == array.count ? items : nil
        case let dictionary as [String: Any]:
            let items = dictionary.compactMapValues(encode)
            return items.count == dictionary.count ? items : nil
        default: return nil
        }
    }

    private static func decode(_ value: Any) -> Any? {
        switch value {
        case let dictionary as [String: Any]:
            if dictionary.count == 1,dictionary["$data"] != nil {
                guard let base64 = dictionary["$data"] as? String else { return nil }
                return Data(base64Encoded: base64)
            }
            if dictionary.count == 1,dictionary["$date"] != nil {
                guard let seconds = dictionary["$date"] as? NSNumber,CFGetTypeID(seconds) != CFBooleanGetTypeID(),seconds.doubleValue.isFinite else { return nil }
                return Date(timeIntervalSince1970: seconds.doubleValue)
            }
            let items = dictionary.compactMapValues(decode)
            return items.count == dictionary.count ? items : nil
        case let array as [Any]:
            let items = array.compactMap(decode)
            return items.count == array.count ? items : nil
        case is NSNull: return nil
        case let string as String: return string
        case let number as NSNumber: return number.doubleValue.isFinite ? number : nil
        default: return nil
        }
    }
}

// MARK: - Resource alerts

public enum ResourceAlertKind: String, CaseIterable, Identifiable, Sendable {
    case lowDisk, thermal, memoryPressure, sustainedCPU, lowBattery
    public var id: String { rawValue }
}

public struct ResourceAlertSettings: Equatable, Sendable {
    public var enabled: Set<ResourceAlertKind>
    /// Alert when the startup volume's free space falls below this share (percent).
    public var diskFreePercent: Double

    /// Alert when total CPU stays at or above this percentage for `cpuMinutes`.
    public var cpuPercent: Double
    public var cpuMinutes: Int
    /// Alert when the battery falls to this percentage while discharging.
    public var batteryPercent: Double

    public static let diskThresholdChoices: [Double] = [5, 10, 15, 20]
    public static let cpuThresholdChoices: [Double] = [70, 85, 95]
    public static let cpuMinuteChoices = [2, 5, 10, 15]
    public static let batteryThresholdChoices: [Double] = [10, 15, 20, 30]

    public init(enabled: Set<ResourceAlertKind> = [], diskFreePercent: Double = 10, cpuPercent: Double = 85, cpuMinutes: Int = 5,
                batteryPercent: Double = 15) {
        self.enabled = enabled
        self.diskFreePercent = diskFreePercent
        self.cpuPercent = cpuPercent
        self.cpuMinutes = cpuMinutes
        self.batteryPercent = batteryPercent
    }

    public static let enabledKeyPrefix = "MacPocket.alerts."
    public static let diskThresholdKey = "MacPocket.alerts.diskThreshold"
    public static let cpuThresholdKey = "MacPocket.alerts.cpuThreshold"
    public static let cpuMinutesKey = "MacPocket.alerts.cpuMinutes"
    public static let batteryThresholdKey = "MacPocket.alerts.batteryThreshold"
    public static func enabledKey(_ kind: ResourceAlertKind) -> String { enabledKeyPrefix + kind.rawValue }

    public static func load(from defaults: UserDefaults) -> ResourceAlertSettings {
        let enabled = Set(ResourceAlertKind.allCases.filter { defaults.bool(forKey: enabledKey($0)) })
        let threshold = defaults.double(forKey: diskThresholdKey)
        let cpu = defaults.double(forKey: cpuThresholdKey), minutes = defaults.integer(forKey: cpuMinutesKey)
        let battery = defaults.double(forKey: batteryThresholdKey)
        return ResourceAlertSettings(enabled: enabled, diskFreePercent: threshold > 0 ? min(50, threshold) : 10,
                                     cpuPercent: cpu > 0 ? min(100, cpu) : 85, cpuMinutes: minutes > 0 ? min(120, minutes) : 5,
                                     batteryPercent: battery > 0 ? min(50, battery) : 15)
    }
}

/// The values alerts look at, extracted from a snapshot so the rules stay testable.
public struct ResourceAlertReading: Equatable, Sendable {
    public var diskFreePercent: Double?
    public var thermalState: String
    public var memoryPressureLevel: Int?
    /// How long total CPU has stayed at or above the alert threshold (see `SustainedThreshold`).
    public var cpuHighDuration: TimeInterval?
    public var batteryPercent: Double?
    /// On battery and not charging.
    public var discharging: Bool

    public init(diskFreePercent: Double?, thermalState: String, memoryPressureLevel: Int?, cpuHighDuration: TimeInterval? = nil,
                batteryPercent: Double? = nil, discharging: Bool = false) {
        self.diskFreePercent = diskFreePercent
        self.thermalState = thermalState
        self.memoryPressureLevel = memoryPressureLevel
        self.cpuHighDuration = cpuHighDuration
        self.batteryPercent = batteryPercent
        self.discharging = discharging
    }

    public init(_ snapshot: SystemSnapshot, cpuHighDuration: TimeInterval? = nil) {
        let volume = snapshot.volumes.first { $0.path == "/" } ?? snapshot.volumes.first
        let free = volume.flatMap { $0.totalBytes > 0 ? Double($0.availableBytes) / Double($0.totalBytes) * 100 : nil }
        let power = snapshot.power
        self.init(diskFreePercent: free, thermalState: snapshot.thermalState, memoryPressureLevel: snapshot.memoryPressureLevel,
                  cpuHighDuration: cpuHighDuration, batteryPercent: power.batteryPresent ? power.chargePercent : nil,
                  discharging: power.batteryPresent && power.source == "Battery Power" && power.isCharging != true)
    }

    /// Conditions currently met for the enabled alerts.
    public func triggered(_ settings: ResourceAlertSettings) -> Set<ResourceAlertKind> {
        var result = Set<ResourceAlertKind>()
        if settings.enabled.contains(.lowDisk), let free = diskFreePercent, free < settings.diskFreePercent { result.insert(.lowDisk) }
        if settings.enabled.contains(.thermal), thermalState == "serious" || thermalState == "critical" { result.insert(.thermal) }
        // kern.memorystatus_vm_pressure_level: 4 is critical.
        if settings.enabled.contains(.memoryPressure), (memoryPressureLevel ?? 0) >= 4 { result.insert(.memoryPressure) }
        if settings.enabled.contains(.sustainedCPU), let duration = cpuHighDuration, duration >= Double(settings.cpuMinutes) * 60 {
            result.insert(.sustainedCPU)
        }
        if settings.enabled.contains(.lowBattery), discharging, let battery = batteryPercent, battery <= settings.batteryPercent {
            result.insert(.lowBattery)
        }
        return result
    }
}

/// How long a value has stayed at or above a threshold without a break. A missing sample breaks the streak.
public struct SustainedThreshold: Sendable {
    private var since: Date?

    public init() {}

    /// Feeds one sample; returns the length of the current streak, or nil when below the threshold.
    public mutating func update(_ value: Double?, threshold: Double, at date: Date) -> TimeInterval? {
        guard let value, value >= threshold else { since = nil; return nil }
        let start = since ?? date
        since = start
        return date.timeIntervalSince(start)
    }
}

/// Never sends the same alert more than once per `interval`, however long the condition lasts.
public struct ResourceAlertLimiter: Sendable {
    public let interval: TimeInterval
    public private(set) var lastSent: [ResourceAlertKind: Date] = [:]

    public init(interval: TimeInterval = 3600) { self.interval = interval }

    /// Returns the alerts that may be sent now and records them as sent.
    public mutating func admit(_ triggered: Set<ResourceAlertKind>, now: Date) -> [ResourceAlertKind] {
        let due = ResourceAlertKind.allCases.filter { kind in
            guard triggered.contains(kind) else { return false }
            guard let last = lastSent[kind] else { return true }
            return now.timeIntervalSince(last) >= interval || now < last
        }
        for kind in due { lastSent[kind] = now }
        return due
    }
}

// MARK: - History length

public enum PowerHistoryRetention {
    public static let key = "MacPocket.historyDays"
    public static let dayChoices = [1, 7, 14, 30]
    public static let defaultDays = 14
    /// One sample per minute at most.
    public static func maximumEntries(days: Int) -> Int { max(1, days) * 24 * 60 }

    public static func days(from defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: key)
        return dayChoices.contains(value) ? value : defaultDays
    }
}

// MARK: - Process CPU scale

/// How a process's CPU share is shown. Samples are always per-core ("Unix" style, as `top` and Activity
/// Monitor report them: a process busy on 5 cores reads 500%); `wholeMac` divides by the core count so
/// every process stays within 0–100%.
public enum ProcessCPUScale: String, CaseIterable, Identifiable, Sendable {
    case wholeMac, perCore

    public static let key = "MacPocket.processCPUScale"
    public static let defaultValue = ProcessCPUScale.wholeMac
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wholeMac: String(localized: "Tüm Mac (%100 üst sınır)")
        case .perCore: String(localized: "Çekirdek başına (Unix/Linux)")
        }
    }

    public static func load(from defaults: UserDefaults) -> ProcessCPUScale {
        defaults.string(forKey: key).flatMap(ProcessCPUScale.init(rawValue:)) ?? defaultValue
    }

    /// `perCorePercent` as shown in this scale.
    public func value(_ perCorePercent: Double, logicalCPUCount: Int) -> Double {
        switch self {
        case .wholeMac: perCorePercent / Double(max(1, logicalCPUCount))
        case .perCore: perCorePercent
        }
    }
}

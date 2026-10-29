import Foundation

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

    public func save(to defaults: UserDefaults) {
        if let appleLanguages { defaults.set(appleLanguages, forKey: Self.defaultsKey) }
        else { defaults.removeObject(forKey: Self.defaultsKey) }
    }
}

// MARK: - Settings export / import

public enum SettingsTransferError: Error, LocalizedError, Equatable, Sendable {
    case unreadable
    case wrongFormat
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Ayar dosyası okunamadı.")
        case .wrongFormat: String(localized: "Bu dosya bir MacPocket ayar dosyası değil.")
        case .unsupportedVersion(let version): String(localized: "Ayar dosyası sürümü desteklenmiyor (\(version)).")
        }
    }
}

/// Serialises MacPocket's own preferences (keys starting with `MacPocket.` or `switcher.`) to JSON and back.
/// Data and Date values are wrapped so the file stays plain JSON.
public enum SettingsTransfer {
    public static let format = "MacPocket.settings"
    public static let version = 1
    public static let keyPrefixes = ["MacPocket.", "switcher."]

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
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    public static func importValues(from data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw SettingsTransferError.unreadable }
        guard let document = object as? [String: Any], document["format"] as? String == format,
              let values = document["values"] as? [String: Any] else { throw SettingsTransferError.wrongFormat }
        let fileVersion = document["version"] as? Int ?? 0
        guard fileVersion >= 1 && fileVersion <= version else { throw SettingsTransferError.unsupportedVersion(fileVersion) }
        return values.filter { isTransferable($0.key) }.compactMapValues(decode)
    }

    /// Replaces every transferable key: values missing from the import fall back to their defaults.
    public static func apply(_ values: [String: Any], to defaults: UserDefaults, domain: String) {
        reset(defaults, domain: domain)
        for (key, value) in values where isTransferable(key) { defaults.set(value, forKey: key) }
    }

    /// Removes every transferable key from the app's own domain.
    public static func reset(_ defaults: UserDefaults, domain: String) {
        for key in (defaults.persistentDomain(forName: domain) ?? [:]).keys where isTransferable(key) {
            defaults.removeObject(forKey: key)
        }
    }

    /// The transferable part of the app's own domain.
    public static func currentValues(_ defaults: UserDefaults, domain: String) -> [String: Any] {
        filtered(defaults.persistentDomain(forName: domain) ?? [:])
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
            if dictionary.count == 1, let base64 = dictionary["$data"] as? String { return Data(base64Encoded: base64) }
            if dictionary.count == 1, let seconds = dictionary["$date"] as? Double { return Date(timeIntervalSince1970: seconds) }
            let items = dictionary.compactMapValues(decode)
            return items.count == dictionary.count ? items : nil
        case let array as [Any]:
            let items = array.compactMap(decode)
            return items.count == array.count ? items : nil
        case is NSNull: return nil
        case let string as String: return string
        case let number as NSNumber: return number
        default: return nil
        }
    }
}

// MARK: - Resource alerts

public enum ResourceAlertKind: String, CaseIterable, Identifiable, Sendable {
    case lowDisk, thermal, memoryPressure
    public var id: String { rawValue }
}

public struct ResourceAlertSettings: Equatable, Sendable {
    public var enabled: Set<ResourceAlertKind>
    /// Alert when the startup volume's free space falls below this share (percent).
    public var diskFreePercent: Double

    public static let diskThresholdChoices: [Double] = [5, 10, 15, 20]

    public init(enabled: Set<ResourceAlertKind> = [], diskFreePercent: Double = 10) {
        self.enabled = enabled
        self.diskFreePercent = diskFreePercent
    }

    public static let enabledKeyPrefix = "MacPocket.alerts."
    public static let diskThresholdKey = "MacPocket.alerts.diskThreshold"
    public static func enabledKey(_ kind: ResourceAlertKind) -> String { enabledKeyPrefix + kind.rawValue }

    public static func load(from defaults: UserDefaults) -> ResourceAlertSettings {
        let enabled = Set(ResourceAlertKind.allCases.filter { defaults.bool(forKey: enabledKey($0)) })
        let threshold = defaults.double(forKey: diskThresholdKey)
        return ResourceAlertSettings(enabled: enabled, diskFreePercent: threshold > 0 ? min(50, threshold) : 10)
    }
}

/// The values alerts look at, extracted from a snapshot so the rules stay testable.
public struct ResourceAlertReading: Equatable, Sendable {
    public var diskFreePercent: Double?
    public var thermalState: String
    public var memoryPressureLevel: Int?

    public init(diskFreePercent: Double?, thermalState: String, memoryPressureLevel: Int?) {
        self.diskFreePercent = diskFreePercent
        self.thermalState = thermalState
        self.memoryPressureLevel = memoryPressureLevel
    }

    public init(_ snapshot: SystemSnapshot) {
        let volume = snapshot.volumes.first { $0.path == "/" } ?? snapshot.volumes.first
        let free = volume.flatMap { $0.totalBytes > 0 ? Double($0.availableBytes) / Double($0.totalBytes) * 100 : nil }
        self.init(diskFreePercent: free, thermalState: snapshot.thermalState, memoryPressureLevel: snapshot.memoryPressureLevel)
    }

    /// Conditions currently met for the enabled alerts.
    public func triggered(_ settings: ResourceAlertSettings) -> Set<ResourceAlertKind> {
        var result = Set<ResourceAlertKind>()
        if settings.enabled.contains(.lowDisk), let free = diskFreePercent, free < settings.diskFreePercent { result.insert(.lowDisk) }
        if settings.enabled.contains(.thermal), thermalState == "serious" || thermalState == "critical" { result.insert(.thermal) }
        // kern.memorystatus_vm_pressure_level: 4 is critical.
        if settings.enabled.contains(.memoryPressure), (memoryPressureLevel ?? 0) >= 4 { result.insert(.memoryPressure) }
        return result
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

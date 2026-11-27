import Foundation

/// Ready-made choices for what the cleanup scan covers. Editing a single location by hand turns the choice
/// into `.custom`.
public enum CleanupProfile: String, CaseIterable, Identifiable, Sendable {
    /// Locations apps rebuild on their own, plus the Trash. Developer tooling is left out.
    case recommended
    /// Recommended plus the safe Xcode and package manager locations.
    case developer
    /// Every location, including the ones marked "review" and the separately managed data.
    case all
    case custom

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .recommended: String(localized: "Önerilen")
        case .developer: String(localized: "Geliştirici")
        case .all: String(localized: "Tümü")
        case .custom: String(localized: "Özel")
        }
    }

    public var localizedDetail: String {
        switch self {
        case .recommended: String(localized: "Uygulamaların yeniden oluşturduğu önbellekler, günlükler ve Çöp.")
        case .developer: String(localized: "Önerilene ek olarak Xcode ve paket yöneticisi önbellekleri.")
        case .all: String(localized: "İncelenmesi gerekenler dahil tüm konumlar.")
        case .custom: String(localized: "Konumları kendin seçtin.")
        }
    }

    /// The locations this profile scans; `.custom` has no fixed set and returns nil.
    public func targetIDs(in targets: [CleanupTarget]) -> Set<CleanupTargetID>? {
        let developerGroups: Set<CleanupGroup> = [.developer, .packages]
        switch self {
        case .recommended:
            return Set(targets.filter { $0.isTrash || ($0.safety == .safe && !developerGroups.contains($0.group)) }.map(\.id))
        case .developer:
            return Set(targets.filter { $0.isTrash || $0.safety == .safe }.map(\.id))
        case .all:
            return Set(targets.map(\.id))
        case .custom:
            return nil
        }
    }
}

/// The locations the next cleanup scan covers, remembered between launches.
public struct CleanupScanSelection: Equatable, Sendable {
    public static let storageKey = "MacPocket.cleanup.scanTargets"
    public private(set) var ids: Set<CleanupTargetID>

    public init(ids: Set<CleanupTargetID>) { self.ids = ids }

    public init(profile: CleanupProfile, targets: [CleanupTarget]) {
        ids = profile.targetIDs(in: targets) ?? []
    }

    /// The profile whose set matches exactly, otherwise `.custom`.
    public func profile(in targets: [CleanupTarget]) -> CleanupProfile {
        let known = ids.intersection(targets.map(\.id))
        return CleanupProfile.allCases.first { $0.targetIDs(in: targets) == known } ?? .custom
    }

    public func contains(_ id: CleanupTargetID) -> Bool { ids.contains(id) }

    public mutating func set(_ id: CleanupTargetID, included: Bool) {
        if included { ids.insert(id) } else { ids.remove(id) }
    }

    public mutating func set(_ group: CleanupGroup, included: Bool, targets: [CleanupTarget]) {
        let members = targets.filter { $0.group == group }.map(\.id)
        if included { ids.formUnion(members) } else { ids.subtract(members) }
    }

    public mutating func apply(_ profile: CleanupProfile, targets: [CleanupTarget]) {
        if let profileIDs = profile.targetIDs(in: targets) { ids = profileIDs }
    }

    /// First launch (nothing stored) starts with the recommended profile; unknown stored names are dropped.
    public static func load(from defaults: UserDefaults, targets: [CleanupTarget]) -> CleanupScanSelection {
        guard let stored = defaults.stringArray(forKey: storageKey) else {
            return CleanupScanSelection(profile: .recommended, targets: targets)
        }
        return CleanupScanSelection(ids: Set(stored.compactMap(CleanupTargetID.init(rawValue:))))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(ids.map(\.rawValue).sorted(), forKey: Self.storageKey)
    }
}

/// Bytes found per location in the most recent scan that covered it, shown on the category tiles before
/// scanning.
public struct CleanupLastScanSizes: Equatable, Sendable {
    public static let storageKey = "MacPocket.cleanup.lastScanBytes"
    public private(set) var bytes: [CleanupTargetID: Int64]

    public init(bytes: [CleanupTargetID: Int64] = [:]) { self.bytes = bytes }

    /// Updates only the locations the report covers; locations missing on this Mac are forgotten.
    public mutating func record(_ report: CleanupReport) {
        for target in report.targets {
            if target.state == .missing { bytes.removeValue(forKey: target.id) } else { bytes[target.id] = target.bytes }
        }
    }

    /// Total of the known sizes for these locations, or nil when none of them has been scanned yet.
    public func total(of ids: some Sequence<CleanupTargetID>) -> Int64? {
        let known = ids.compactMap { bytes[$0] }
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    public static func load(from defaults: UserDefaults) -> CleanupLastScanSizes {
        let stored = defaults.dictionary(forKey: storageKey) as? [String: Int64] ?? [:]
        var bytes: [CleanupTargetID: Int64] = [:]
        for (key, value) in stored { if let id = CleanupTargetID(rawValue: key) { bytes[id] = value } }
        return CleanupLastScanSizes(bytes: bytes)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(Dictionary(uniqueKeysWithValues: bytes.map { ($0.key.rawValue, $0.value) }), forKey: Self.storageKey)
    }
}

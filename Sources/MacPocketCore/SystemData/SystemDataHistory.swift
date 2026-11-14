import Foundation

public struct SystemDataScanRecord: Codable, Sendable, Equatable {
    public let date: Date
    /// Item id → bytes at that scan.
    public let itemBytes: [String: Int64]
    /// Group raw value → bytes at that scan.
    public let groupBytes: [String: Int64]

    public init(date: Date, itemBytes: [String: Int64], groupBytes: [String: Int64]) {
        self.date = date; self.itemBytes = itemBytes; self.groupBytes = groupBytes
    }

    public init(report: SystemDataReport) {
        var groups: [String: Int64] = [:]
        for item in report.items { groups[item.group.rawValue, default: 0] += item.sizeBytes }
        self.init(date: report.scannedAt, itemBytes: Dictionary(report.items.map { ($0.id, $0.sizeBytes) }, uniquingKeysWith: +),
                  groupBytes: groups)
    }
}

public struct SystemDataDeletionRecord: Codable, Sendable, Equatable {
    public let date: Date
    public let itemID: String
    public let title: String
    public let bytes: Int64
    public let paths: [String]
    public init(date: Date, itemID: String, title: String, bytes: Int64, paths: [String]) {
        self.date = date; self.itemID = itemID; self.title = title; self.bytes = bytes; self.paths = paths
    }
}

/// A category that grew well past its recent size.
public struct SystemDataGrowthAlert: Sendable, Equatable {
    public let group: SystemDataGroup
    public let currentBytes: Int64
    public let medianBytes: Int64
    public var growthBytes: Int64 { currentBytes - medianBytes }
}

/// An item that was deleted and is large again.
public struct SystemDataReturnedItem: Sendable, Equatable {
    public let itemID: String
    public let title: String
    public let deletedBytes: Int64
    public let currentBytes: Int64
    public let deletedAt: Date
}

public struct SystemDataHistory: Codable, Sendable, Equatable {
    /// Six months of scans is what the history view can use; older records only cost disk.
    public static let retentionDays = 183
    public static let maximumScans = 400
    public static let maximumDeletions = 2_000
    public static let growthWindow = 14
    public static let growthRatio = 1.5
    public static let growthMinimumBytes: Int64 = 2_000_000_000

    public private(set) var scans: [SystemDataScanRecord] = []
    public private(set) var deletions: [SystemDataDeletionRecord] = []
    /// Per group: the size at which a growth alert last fired, so the same growth does not speak twice.
    public private(set) var lastAlertBytes: [String: Int64] = [:]

    public init() {}

    public mutating func record(_ report: SystemDataReport) {
        scans.append(SystemDataScanRecord(report: report))
        scans.sort { $0.date < $1.date }
        prune(now: report.scannedAt)
    }

    public mutating func recordDeletion(_ record: SystemDataDeletionRecord) {
        deletions.append(record)
        prune(now: record.date)
    }

    public mutating func markAlerted(_ alert: SystemDataGrowthAlert) {
        lastAlertBytes[alert.group.rawValue] = alert.currentBytes
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        scans.removeAll { $0.date < cutoff }
        deletions.removeAll { $0.date < cutoff }
        if scans.count > Self.maximumScans { scans.removeFirst(scans.count - Self.maximumScans) }
        if deletions.count > Self.maximumDeletions { deletions.removeFirst(deletions.count - Self.maximumDeletions) }
    }

    // MARK: Analysis

    /// Sizes of one item over the last scans, oldest first; scans that did not know the item are skipped.
    public func trend(forItem id: String, limit: Int = 12) -> [Int64] {
        Array(scans.compactMap { $0.itemBytes[id] }.suffix(max(0, limit)))
    }

    /// Change of one item against the newest scan taken at least `days` days before `now`; nil without such a scan.
    public func change(forItem id: String, currentBytes: Int64, overDays days: Int, now: Date = Date()) -> Int64? {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        guard let earlier = scans.last(where: { $0.date <= cutoff }), let before = earlier.itemBytes[id] else { return nil }
        return currentBytes - before
    }

    /// Change of the whole of System Data over `days` days.
    public func totalChange(currentBytes: Int64, overDays days: Int, now: Date = Date()) -> Int64? {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        guard let earlier = scans.last(where: { $0.date <= cutoff }) else { return nil }
        return currentBytes - earlier.groupBytes.values.reduce(0, +)
    }

    /// Groups at least 50% and 2 GB above their median over the last 14 scans before the newest one. A group that
    /// already alerted stays quiet until it is another 2 GB larger.
    public func growthAlerts() -> [SystemDataGrowthAlert] {
        guard let latest = scans.last else { return [] }
        let previous = Array(scans.dropLast().suffix(Self.growthWindow))
        guard previous.count >= 3 else { return [] }
        return SystemDataGroup.allCases.compactMap { group in
            let key = group.rawValue
            guard let current = latest.groupBytes[key] else { return nil }
            let median = Self.median(previous.map { $0.groupBytes[key] ?? 0 })
            let grew = current - median
            guard grew >= Self.growthMinimumBytes, Double(current) >= Double(median) * Self.growthRatio else { return nil }
            if let last = lastAlertBytes[key], current < last + Self.growthMinimumBytes { return nil }
            return SystemDataGrowthAlert(group: group, currentBytes: current, medianBytes: median)
        }.sorted { $0.growthBytes > $1.growthBytes }
    }

    /// Items inside a group, ordered by how much they grew over their own median, for the history view.
    public func growthDrivers(in group: SystemDataGroup, items: [SystemDataItem]) -> [(item: SystemDataItem, usualBytes: Int64?)] {
        let previous = Array(scans.dropLast().suffix(Self.growthWindow))
        return items.filter { $0.group == group }.map { item -> (SystemDataItem, Int64?) in
            let sizes = previous.compactMap { $0.itemBytes[item.id] }
            return (item, sizes.isEmpty ? nil : Self.median(sizes))
        }.sorted { ($0.0.sizeBytes - ($0.1 ?? 0)) > ($1.0.sizeBytes - ($1.1 ?? 0)) }
    }

    /// Deleted items that have regrown to at least half their deleted size and 500 MB, newest deletion per item.
    public func returnedItems(current: [SystemDataItem], now: Date = Date()) -> [SystemDataReturnedItem] {
        let sizes = Dictionary(current.map { ($0.id, $0.sizeBytes) }, uniquingKeysWith: max)
        var latest: [String: SystemDataDeletionRecord] = [:]
        for deletion in deletions where deletion.date <= now { latest[deletion.itemID] = deletion }
        return latest.values.compactMap { deletion -> SystemDataReturnedItem? in
            guard let size = sizes[deletion.itemID], size >= 500_000_000, size * 2 >= deletion.bytes else { return nil }
            return SystemDataReturnedItem(itemID: deletion.itemID, title: deletion.title, deletedBytes: deletion.bytes,
                                          currentBytes: size, deletedAt: deletion.date)
        }.sorted { $0.currentBytes > $1.currentBytes }
    }

    static func median(_ values: [Int64]) -> Int64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// The history file. Reading a missing or damaged file starts an empty history; the app must never fail to
/// open because of it, and it holds only sizes and paths the window already showed.
public actor SystemDataHistoryStore {
    private let url: URL
    private var history: SystemDataHistory?

    public init(url: URL = SystemDataHistoryStore.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "MacPocket", directoryHint: .isDirectory)
            .appending(path: "system-data-history.json", directoryHint: .notDirectory)
    }

    public func load() -> SystemDataHistory {
        if let history { return history }
        let loaded: SystemDataHistory
        if let data = try? Data(contentsOf: url), let decoded = try? Self.decoder.decode(SystemDataHistory.self, from: data) {
            loaded = decoded
        } else {
            loaded = SystemDataHistory()
        }
        history = loaded
        return loaded
    }

    public func update(_ change: @Sendable (inout SystemDataHistory) -> Void) throws -> SystemDataHistory {
        var current = load()
        change(&current)
        history = current
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(current).write(to: url, options: .atomic)
        return current
    }

    /// Switching "remember what changed" off removes the file along with everything in memory.
    public func erase() throws {
        history = SystemDataHistory()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }()
}

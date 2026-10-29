import Foundation

public struct PowerHistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let source: String
    public let chargePercent: Double?
    public let charging: Bool?
    public let lowPower: Bool
    public let thermalState: String
    public let event: String
}

public actor PowerHistoryStore {
    private struct Document: Codable { var version = 1; var entries: [PowerHistoryEntry] }
    private let url: URL
    private let maximumEntries: Int
    private var cached: [PowerHistoryEntry]?
    public init(url: URL? = nil, maximumEntries: Int = 20_160) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPocket/power-history.json")
        self.maximumEntries = max(1, maximumEntries)
    }
    public func entries() throws -> [PowerHistoryEntry] {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { cached = []; return [] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        cached = Array(document.entries.suffix(maximumEntries))
        return cached ?? []
    }
    @discardableResult
    public func record(_ snapshot: SystemSnapshot, event: String = "sample", minimumInterval: TimeInterval = 60) throws -> [PowerHistoryEntry]? {
        var values = try entries()
        if event == "sample", let previous = values.last {
            let interval = snapshot.capturedAt.timeIntervalSince(previous.date)
            if interval >= 0 && interval < minimumInterval { return nil }
        }
        values.append(.init(id: UUID(), date: snapshot.capturedAt, source: snapshot.power.source,
                            chargePercent: snapshot.power.chargePercent, charging: snapshot.power.isCharging,
                            lowPower: snapshot.power.lowPowerMode, thermalState: snapshot.thermalState, event: event))
        values = Array(values.suffix(maximumEntries))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Document(entries: values))
        try data.write(to: url, options: .atomic)
        cached = values
        return values
    }
}

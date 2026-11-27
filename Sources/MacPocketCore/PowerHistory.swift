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

/// Append-only JSON Lines log: one small write per sample instead of rewriting the whole history.
/// Compacted to `maximumEntries` once it grows past a slack margin. Legacy single-document files migrate.
public actor PowerHistoryStore {
    private struct LegacyDocument: Codable { var version = 1; var entries: [PowerHistoryEntry] }
    private let url: URL
    private let maximumEntries: Int
    private var cached: [PowerHistoryEntry]?
    private var linesOnDisk = 0
    public init(url: URL? = nil, maximumEntries: Int = 20_160) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPocket/power-history.json")
        self.maximumEntries = max(1, maximumEntries)
    }

    /// Where an unreadable history is preserved before a fresh log starts.
    public nonisolated var corruptBackupURL: URL { url.appendingPathExtension("corrupt") }

    public func entries() throws -> [PowerHistoryEntry] {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { cached = []; return [] }
        let data = try Data(contentsOf: url)
        if let legacy = try? JSONDecoder().decode(LegacyDocument.self, from: data), legacy.version == 1 {
            let values = Array(legacy.entries.suffix(maximumEntries))
            try rewrite(values)
            cached = values
            return values
        }
        let decoder = JSONDecoder()
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // A torn final line after a crash is skipped; a file with no readable line is corrupt.
        let decoded = lines.compactMap { try? decoder.decode(PowerHistoryEntry.self, from: Data($0)) }
        if decoded.isEmpty && !lines.isEmpty {
            try? FileManager.default.removeItem(at: corruptBackupURL)
            try FileManager.default.moveItem(at: url, to: corruptBackupURL)
            linesOnDisk = 0
            cached = []
            return []
        }
        linesOnDisk = lines.count
        cached = Array(decoded.suffix(maximumEntries))
        return cached ?? []
    }

    @discardableResult
    public func record(_ snapshot: SystemSnapshot, event: String = "sample", minimumInterval: TimeInterval = 60) throws -> [PowerHistoryEntry]? {
        var values = try entries()
        if event == "sample", let previous = values.last {
            let interval = snapshot.capturedAt.timeIntervalSince(previous.date)
            if interval >= 0 && interval < minimumInterval { return nil }
        }
        let entry = PowerHistoryEntry(id: UUID(), date: snapshot.capturedAt, source: snapshot.power.source,
                                      chargePercent: snapshot.power.chargePercent, charging: snapshot.power.isCharging,
                                      lowPower: snapshot.power.lowPowerMode, thermalState: snapshot.thermalState, event: event)
        values.append(entry)
        values = Array(values.suffix(maximumEntries))
        if linesOnDisk + 1 > maximumEntries + max(64, maximumEntries / 4) {
            try rewrite(values)
        } else {
            try append(entry)
        }
        cached = values
        return values
    }

    /// Deletes the history file (and any corrupt backup) and starts an empty log.
    public func clear() throws {
        for file in [url, corruptBackupURL] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        cached = []
        linesOnDisk = 0
    }

    private func append(_ entry: PowerHistoryEntry) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try JSONEncoder().encode(entry)
        line.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: url.path) {
            try line.write(to: url, options: .atomic)
        } else {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
        linesOnDisk += 1
    }

    private func rewrite(_ values: [PowerHistoryEntry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(UInt8(ascii: "\n"))
        }
        try data.write(to: url, options: .atomic)
        linesOnDisk = values.count
    }
}

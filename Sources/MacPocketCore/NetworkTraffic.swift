import Foundation

/// Cumulative bytes one process has moved over its sockets, as `nettop` reports them.
public struct NetworkTrafficSample: Equatable, Sendable {
    public let pid: Int32
    /// `nettop` truncates names to ~15 characters; the app replaces it with the full name when it can.
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.pid = pid
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// One process in the traffic list: current rate and what it moved since the list started watching.
public struct NetworkTrafficRow: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    /// Bytes per second over the last interval.
    public let downloadRate: Double
    public let uploadRate: Double
    /// Bytes since the process was first seen in this session.
    public let sessionDownload: UInt64
    public let sessionUpload: UInt64
    public var id: Int32 { pid }

    public var totalRate: Double { downloadRate + uploadRate }
    public var sessionTotal: UInt64 { sessionDownload &+ sessionUpload }
    public var isActive: Bool { totalRate > 0 }
}

/// Processes that belong together (an app and its helpers) summed into one line.
public struct NetworkTrafficGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let rows: [NetworkTrafficRow]

    // Rows are immutable: calculate their sums once, rather than on every sort comparison and UI read.
    public let downloadRate: Double
    public let uploadRate: Double
    public let sessionDownload: UInt64
    public let sessionUpload: UInt64
    public var totalRate: Double { downloadRate + uploadRate }

    init(id: String, name: String, rows: [NetworkTrafficRow]) {
        self.id = id
        self.name = name
        self.rows = rows
        var download = 0.0, upload = 0.0
        var received: UInt64 = 0, sent: UInt64 = 0
        for row in rows {
            download += row.downloadRate
            upload += row.uploadRate
            received = received &+ row.sessionDownload
            sent = sent &+ row.sessionUpload
        }
        downloadRate = download
        uploadRate = upload
        sessionDownload = received
        sessionUpload = sent
    }
    public var sessionTotal: UInt64 { sessionDownload &+ sessionUpload }
    public var isActive: Bool { totalRate > 0 }
}

public enum NetworkTraffic {
    /// Sums rows sharing an owner (e.g. the `.app` bundle a helper lives in). Rows without one stay alone.
    public static func group(_ rows: [NetworkTrafficRow],
                             owner: (NetworkTrafficRow) -> (id: String, name: String)?) -> [NetworkTrafficGroup] {
        var order: [String] = []
        var names: [String: String] = [:]
        var members: [String: [NetworkTrafficRow]] = [:]
        for row in rows {
            let key: String, name: String
            if let found = owner(row) { key = found.id; name = found.name } else { key = "pid:\(row.pid)"; name = row.name }
            if members[key] == nil { order.append(key); names[key] = name }
            members[key, default: []].append(row)
        }
        return order.map { NetworkTrafficGroup(id: $0, name: names[$0] ?? $0, rows: members[$0] ?? []) }
            .sorted {
                $0.totalRate != $1.totalRate ? $0.totalRate > $1.totalRate
                    : $0.sessionTotal != $1.sessionTotal ? $0.sessionTotal > $1.sessionTotal : $0.name < $1.name
            }
    }

    /// One sample, per process, raw byte counts, no header resolution.
    public static let nettopArguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
    public static let nettopPath = "/usr/bin/nettop"

    /// Parses `nettop -P -L 1 -x -J bytes_in,bytes_out` CSV: a header line, then `name.pid,in,out,`.
    /// Names may contain dots and commas, so fields are taken from the right.
    public static func parse(_ output: String) -> [NetworkTrafficSample] {
        var samples: [NetworkTrafficSample] = []
        for line in output.split(whereSeparator: \.isNewline) {
            var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if fields.last?.isEmpty == true { fields.removeLast() }
            guard fields.count >= 3,
                  let bytesOut = UInt64(fields[fields.count - 1].trimmingCharacters(in: .whitespaces)),
                  let bytesIn = UInt64(fields[fields.count - 2].trimmingCharacters(in: .whitespaces)) else { continue }
            let label = fields[0..<(fields.count - 2)].joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]), pid > 0 else { continue }
            let name = String(label[..<dot])
            samples.append(NetworkTrafficSample(pid: pid, name: name.isEmpty ? String(localized: "PID \(pid)") : name, bytesIn: bytesIn, bytesOut: bytesOut))
        }
        return samples
    }
}

/// Turns successive cumulative samples into rates and session totals.
public struct NetworkTrafficTracker: Sendable {
    private struct Entry: Sendable {
        var name: String
        var baselineIn: UInt64
        var baselineOut: UInt64
        var lastIn: UInt64
        var lastOut: UInt64
    }

    private var entries: [Int32: Entry] = [:]
    private var lastTime: Date?

    public init() {}

    /// A process seen for the first time starts at zero: its earlier traffic happened before we were
    /// watching. A counter that goes backwards means the PID was reused, so it starts over the same way.
    public mutating func update(_ samples: [NetworkTrafficSample], at time: Date) -> [NetworkTrafficRow] {
        let interval = lastTime.map { time.timeIntervalSince($0) } ?? 0
        lastTime = time
        var next: [Int32: Entry] = [:]
        var rows: [NetworkTrafficRow] = []
        for sample in samples {
            var downloadRate = 0.0, uploadRate = 0.0
            var entry: Entry
            if var known = entries[sample.pid], sample.bytesIn >= known.lastIn, sample.bytesOut >= known.lastOut {
                if interval > 0 {
                    downloadRate = Double(sample.bytesIn - known.lastIn) / interval
                    uploadRate = Double(sample.bytesOut - known.lastOut) / interval
                }
                known.lastIn = sample.bytesIn
                known.lastOut = sample.bytesOut
                known.name = sample.name
                entry = known
            } else {
                entry = Entry(name: sample.name, baselineIn: sample.bytesIn, baselineOut: sample.bytesOut,
                              lastIn: sample.bytesIn, lastOut: sample.bytesOut)
            }
            next[sample.pid] = entry
            rows.append(NetworkTrafficRow(pid: sample.pid, name: entry.name, downloadRate: downloadRate, uploadRate: uploadRate,
                                          sessionDownload: entry.lastIn - entry.baselineIn, sessionUpload: entry.lastOut - entry.baselineOut))
        }
        entries = next
        return rows.sorted {
            $0.totalRate != $1.totalRate ? $0.totalRate > $1.totalRate
                : $0.sessionTotal != $1.sessionTotal ? $0.sessionTotal > $1.sessionTotal : $0.pid < $1.pid
        }
    }

    public mutating func reset() {
        entries = [:]
        lastTime = nil
    }
}

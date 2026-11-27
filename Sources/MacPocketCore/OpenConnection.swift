import Foundation

/// One established TCP/UDP connection as `lsof -F` reports it.
public struct OpenConnection: Equatable, Hashable, Sendable {
    public var process: String
    public var pid: Int32
    public var local: String
    public var remote: String

    public init(process: String, pid: Int32, local: String, remote: String) {
        self.process = process
        self.pid = pid
        self.local = local
        self.remote = remote
    }

    /// The port after the last colon ("[fe80::1]:443" and "1.2.3.4:443" both give 443).
    public var remotePort: Int? {
        guard let colon = remote.lastIndex(of: ":") else { return nil }
        return Int(remote[remote.index(after: colon)...])
    }

    /// Parses `lsof -n -P -iTCP -iUDP -Fpcn`: "p<pid>", "c<command>" and "n<local>-><remote>" lines.
    /// Listening sockets (no "->") are skipped; only connections with a peer are interesting here.
    public static func parseLsof(_ output: String, limit: Int = 500) -> [OpenConnection] {
        var pid: Int32 = 0, name = "", rows: [OpenConnection] = []
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": name = String(value)
            case "n":
                guard let arrow = value.range(of: "->") else { continue }
                rows.append(OpenConnection(process: name, pid: pid, local: String(value[..<arrow.lowerBound]),
                                           remote: String(value[arrow.upperBound...])))
                if rows.count >= limit { return rows }
            default: continue
            }
        }
        return rows
    }

    public struct Group: Identifiable, Sendable, Equatable {
        public var process: String
        public var pid: Int32
        public var connections: [OpenConnection]
        public var id: String { "\(pid)-\(process)" }
    }

    /// One group per process, the one with the most connections first.
    public static func grouped(_ rows: [OpenConnection]) -> [Group] {
        Dictionary(grouping: rows) { "\($0.pid)-\($0.process)" }.values
            .map { Group(process: $0[0].process, pid: $0[0].pid, connections: $0) }
            .sorted { $0.connections.count != $1.connections.count ? $0.connections.count > $1.connections.count
                                                                    : $0.process.localizedStandardCompare($1.process) == .orderedAscending }
    }
}

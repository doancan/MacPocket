import Foundation

/// One socket accepting connections (TCP LISTEN) or bound to a fixed port (UDP).
public struct ListeningSocket: Hashable, Sendable {
    public enum Transport: String, Sendable { case tcp = "TCP", udp = "UDP" }

    public let transport: Transport
    public let address: String
    public let port: Int
    public let isIPv6: Bool

    /// Reachable only from this Mac (loopback); everything else is open to the network.
    public var isLocalOnly: Bool {
        address == "127.0.0.1" || address == "::1" || address == "[::1]" || address.hasPrefix("127.") || address == "localhost"
    }

    /// A common name for the port, when there is a well-known one.
    public var serviceName: String? { ListeningPorts.wellKnown[port] }
}

/// A process with its listening sockets, IPv4/IPv6 twins merged.
public struct PortOwner: Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let command: String
    public let sockets: [ListeningSocket]

    public var ports: [Int] { Array(Set(sockets.map(\.port))).sorted() }
    public var isExposed: Bool { sockets.contains { !$0.isLocalOnly } }
}

public enum ListeningPorts {
    static let wellKnown: [Int: String] = [
        22: "SSH", 53: "DNS", 80: "HTTP", 88: "Kerberos", 443: "HTTPS", 445: "SMB", 548: "AFP", 631: "IPP",
        3000: "Node / dev", 3306: "MySQL", 3283: "Remote Desktop", 5000: "AirPlay", 5173: "Vite", 5353: "mDNS",
        5432: "PostgreSQL", 5900: "VNC", 6379: "Redis", 7000: "AirPlay", 8000: "HTTP dev", 8080: "HTTP alt",
        8443: "HTTPS alt", 9000: "PHP-FPM", 9200: "Elasticsearch", 11434: "Ollama", 27017: "MongoDB",
    ]

    /// `lsof` arguments for the current user's sockets. UDP has no listening state; bound ports are listed.
    public static func arguments(includeUDP: Bool, userID: uid_t = getuid()) -> [String] {
        var arguments = ["-nP", "-a", "-u", String(userID)]
        arguments += includeUDP ? ["-iTCP", "-sTCP:LISTEN", "-iUDP"] : ["-iTCP", "-sTCP:LISTEN"]
        return arguments + ["-F", "pcPtn"]
    }

    /// Parses `lsof -F pcPtn` field output: p=pid, c=command, P=protocol, t=type (IPv4/IPv6), n=name.
    /// UDP sockets without a fixed local port (`*:*`, client sockets) are skipped.
    public static func parse(_ output: String) -> [PortOwner] {
        var owners: [Int32: (command: String, sockets: [ListeningSocket])] = [:]
        var order: [Int32] = []
        var pid: Int32?
        var transport: ListeningSocket.Transport?
        var isIPv6 = false
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                if let pid, owners[pid] == nil { owners[pid] = ("", []); order.append(pid) }
            case "c":
                if let pid { owners[pid]?.command = value }
            case "f":
                transport = nil
                isIPv6 = false
            case "P":
                transport = ListeningSocket.Transport(rawValue: value.uppercased())
            case "t":
                isIPv6 = value == "IPv6"
            case "n":
                guard let pid, let transport, let socket = socket(value, transport: transport, isIPv6: isIPv6) else { continue }
                if !(owners[pid]?.sockets.contains(socket) ?? true) { owners[pid]?.sockets.append(socket) }
            default:
                continue
            }
        }
        return order.compactMap { pid in
            guard let owner = owners[pid], !owner.sockets.isEmpty else { return nil }
            // IPv4 and IPv6 sockets on the same port and scope are one entry to the user.
            var seen = Set<String>()
            let merged = owner.sockets.filter { seen.insert("\($0.transport.rawValue)/\($0.port)/\($0.isLocalOnly)").inserted }
                .sorted { ($0.port, $0.transport.rawValue) < ($1.port, $1.transport.rawValue) }
            return PortOwner(pid: pid, command: owner.command, sockets: merged)
        }
        .sorted { ($0.ports.first ?? 0, $0.pid) < ($1.ports.first ?? 0, $1.pid) }
    }

    /// "*:7000", "127.0.0.1:5432", "[::1]:8080". Connected sockets ("a->b") and wildcard ports are not
    /// listeners.
    static func socket(_ name: String, transport: ListeningSocket.Transport, isIPv6: Bool) -> ListeningSocket? {
        guard !name.contains("->"), let colon = name.lastIndex(of: ":"), let port = Int(name[name.index(after: colon)...]), port > 0
        else { return nil }
        var address = String(name[..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
        return ListeningSocket(transport: transport, address: address, port: port, isIPv6: isIPv6)
    }
}

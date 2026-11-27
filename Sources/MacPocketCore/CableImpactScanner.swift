import Darwin
import Foundation

public enum CableSessionParser {
    public struct Result: Sendable {
        public let sessions: [CableNetworkSession]
        public let limited: Bool
    }
    /// lsof -F0 is a tagged, NUL-delimited protocol. Do not split IPv6 endpoints on colons.
    public static func parse(_ output: String) -> Result {
        var pid: Int32?, command = "", sessions: [CableNetworkSession] = [], seen = Set<String>()
        for raw in output.split(separator: "\0") {
            let field = raw.drop(while: { $0 == "\n" || $0 == "\r" })
            guard let tag = field.first else { continue }
            let value = String(field.dropFirst())
            switch tag {
            case "p": pid = Int32(value)
            command = ""
            case "c": command = value
            case "n":
                guard let pid, pid > 0, !command.isEmpty, let arrow = value.range(of: "->") else { continue }
                let local = String(value[..<arrow.lowerBound]), remote = String(value[arrow.upperBound...])
                guard let address = socketAddress(local), socketAddress(remote) != nil else { continue }
                let session = CableNetworkSession(pid: pid, command: command, local: local, remote: remote, localAddress: address)
                if seen.insert(session.id).inserted { sessions.append(session) }
                if sessions.count >= 2000 { return .init(sessions: sessions, limited: true) }
            default: break
            }
        }
        return .init(sessions: sessions, limited: false)
    }

    static func socketAddress(_ endpoint: String) -> String? {
        guard let colon = endpoint.lastIndex(of: ":"), let port = UInt16(endpoint[endpoint.index(after: colon)...]), port > 0 else { return nil }
        var address = String(endpoint[..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
        return canonicalAddress(address)
    }
    public static func canonicalAddress(_ text: String) -> String? {
        let address = String(text.split(separator: "%", maxSplits: 1).first ?? "")
        var v4 = in_addr(), v6 = in6_addr(), buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if inet_pton(AF_INET, address, &v4) == 1 {
            guard inet_ntop(AF_INET, &v4, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        } else if inet_pton(AF_INET6, address, &v6) == 1 {
            guard inet_ntop(AF_INET6, &v6, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        } else { return nil }
        let normalized = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if normalized.hasPrefix("::ffff:"), normalized.contains(".") { return String(normalized.dropFirst(7)) }
        return normalized
    }
}

public enum CableImpactScanner {
    public static func scan(connection: CableConnection, inventory: CableInventory, additionalConnections: Set<String> = [],
                            manualEndpoints: Set<String> = [], execute: @escaping USBEject.Execute = USBEject.execute) async throws -> CableImpactReport {
        try Task.checkCancellation()
        let affected = CableTopology.affected(connection: connection, inventory: inventory,
                                               additionalConnections: additionalConnections, manualEndpoints: manualEndpoints)
        let disks = affected.filter { inventory.drives[$0.id] != nil }
        var users: [String: [DiskUser]] = [:], issues = inventory.issues
        async let network = networkSessions(affected: affected, inventory: inventory, execute: execute)
        let results = await withTaskGroup(of: (String, DiskUsageReport?, String?).self, returning: [(String, DiskUsageReport?, String?)].self) { group in
            for item in disks.prefix(8) {
                guard let drive = inventory.drives[item.id] else { continue }
                group.addTask {
                    do { return (item.id, try await USBEject.usage(of: drive, execute: execute), nil) }
                    catch { return (item.id, nil, String(localized: "\(drive.name): açık dosyalar okunamadı.")) }
                }
            }
            var results: [(String, DiskUsageReport?, String?)] = []
            for await result in group { results.append(result) }
            return results
        }
        try Task.checkCancellation()
        for (id, report, error) in results {
            if let report {
                users[id] = report.users
                if report.limited { issues.append(String(localized: "Disk kullanımının bir kısmına erişilemedi; liste eksik olabilir.")) }
            }
            if let error { issues.append(error) }
        }
        if disks.count > 8 { issues.append(String(localized: "Açık dosyalar ilk 8 disk için denetlendi.")) }
        let sockets = await network
        try Task.checkCancellation()
        issues += sockets.issues
        return .init(connectionID: connection.id, capturedAt: .now, affected: affected, diskUsers: users,
                     sessions: sockets.byEndpoint, issues: Array(Set(issues)).sorted())
    }

    private static func networkSessions(affected: [CableAffectedEndpoint], inventory: CableInventory,
                                        execute: USBEject.Execute) async -> (byEndpoint: [String: [CableNetworkSession]], issues: [String]) {
        let networks = affected.filter { $0.endpoint.kind == .network }
        guard !networks.isEmpty else { return ([:], []) }
        do {
            let result = try await execute("/usr/sbin/lsof", ["-nP", "+c", "0", "-iTCP", "-sTCP:ESTABLISHED", "-F0pcn"], 8)
            guard result.status == 0 || (result.status == 1 && result.output.isEmpty && result.errorOutput.isEmpty) else {
                return ([:], [String(localized: "Ağ oturumları okunamadı; bağlantı yok sayılmadı.")])
            }
            let parsed = CableSessionParser.parse(result.output)
            // A local address must identify one interface. Overlapping addresses, VPNs and multipath must not
            // be guessed.
            var owners = inventory.networkAddressInterfaces
            if owners.isEmpty {
                for endpoint in inventory.endpoints where endpoint.kind == .network {
                    for address in endpoint.addresses { owners[address, default: []].insert(endpoint.interfaceName ?? endpoint.id) }
                }
            }
            var byEndpoint: [String: [CableNetworkSession]] = [:], ambiguous = false
            for item in networks {
                byEndpoint[item.id] = parsed.sessions.filter { session in
                    guard item.endpoint.addresses.contains(session.localAddress) else { return false }
                    guard owners[session.localAddress] == Set([item.endpoint.interfaceName ?? item.id]) else { ambiguous = true; return false }
                    return true
                }
            }
            var issues: [String] = []
            if parsed.limited || !result.errorOutput.isEmpty { issues.append(String(localized: "Ağ oturumları kısmen okunabildi; liste eksik olabilir.")) }
            if ambiguous { issues.append(String(localized: "Birden çok arayüzdeki aynı adresin oturumları eşleştirilmedi.")) }
            return (byEndpoint, issues)
        } catch { return ([:], [String(localized: "Ağ oturumları okunamadı; bağlantı yok sayılmadı.")]) }
    }
}

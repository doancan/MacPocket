import Darwin
import Foundation
import Network

// MARK: - Manufacturer

/// IEEE and MACLookup assignments ("OUI"): a hardware address prefix names its manufacturer. The tables ship
/// inside the app, so lookups never leave the Mac.
public struct OUIDatabase: Sendable {
    /// Keyed by upper-case hex prefix: 6 digits (MA-L), 7 (MA-M) or 9 (MA-S and IAB).
    private let vendors: [String: String]

    public init(vendors: [String: String]) { self.vendors = vendors }

    /// Lines of "001B21<TAB>Intel Corporate"; longer prefixes refine shorter ones.
    public init(tsv: String) {
        var table: [String: String] = [:]
        table.reserveCapacity(60_000)
        for line in tsv.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            table[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        vendors = table
    }

    /// MACLookup's downloadable JSON includes private placeholders and CID assignments, which cannot identify
    /// hardware.
    public init(macLookupJSON data: Data) throws {
        struct Entry: Decodable {
            let macPrefix: String
            let vendorName: String
            let `private`: Bool
            let blockType: String
        }
        var table: [String: String] = [:]
        for entry in try JSONDecoder().decode([Entry].self, from: data) where !entry.private {
            let hex = entry.macPrefix.replacingOccurrences(of: ":", with: "").uppercased()
            let length = ["MA-L": 6, "MA-M": 7, "MA-S": 9, "IAB": 9][entry.blockType]
            let name = entry.vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard hex.count == length, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
                  !name.isEmpty else { continue }
            table[hex] = name
        }
        vendors = table
    }

    func merging(_ supplement: OUIDatabase) -> OUIDatabase {
        OUIDatabase(vendors: vendors.merging(supplement.vendors) { _, newer in newer })
    }

    /// The table shipped in the app bundle (`oui.tsv.lzfse`), or nil when it's missing.
    public static func bundled(in bundle: Bundle = .main) -> OUIDatabase? {
        func read(_ name: String) -> Data? {
            guard let url = bundle.url(forResource: name, withExtension: "lzfse"),
                  let compressed = try? Data(contentsOf: url) else { return nil }
            return try? (compressed as NSData).decompressed(using: .lzfse) as Data
        }
        let ieee = read("oui.tsv").map { OUIDatabase(tsv: String(decoding: $0, as: UTF8.self)) }
        let macLookup = read("maclookup.json").flatMap { try? OUIDatabase(macLookupJSON: $0) }
        if let ieee, let macLookup { return ieee.merging(macLookup) }
        return macLookup ?? ieee
    }

    public var count: Int { vendors.count }

    /// Nil for private (randomized) addresses, which carry no manufacturer.
    public func vendor(for mac: String?) -> String? {
        guard let mac, let mac = MACAddress.normalize(mac), !MACAddress.isPrivate(mac),
              !MACAddress.isMulticastOrBroadcast(mac) else { return nil }
        let hex = mac.replacingOccurrences(of: ":", with: "").uppercased()
        for length in [9, 7, 6] where hex.count >= length {
            if let name = vendors[String(hex.prefix(length))] { return Self.tidy(name) }
        }
        return nil
    }

    /// "Sony Interactive Entertainment Inc." → "Sony Interactive Entertainment".
    static func tidy(_ name: String) -> String {
        var result = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        for suffix in [", Inc.", " Inc.", " Inc", ", Ltd.", " Co.,Ltd.", " Co., Ltd.", " Co.,Ltd", " Co., Ltd", " Ltd.,", " Ltd.", " Ltd",
                       " Corporation", " Corp.", " GmbH", " LLC", " S.A.", " B.V.", " AG", " Limited", " Technologies"]
        where result.hasSuffix(suffix) && result.count > suffix.count + 2 {
            result = String(result.dropLast(suffix.count))
            break
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
    }
}

extension LANDeviceKind {
    /// A weaker hint than Bonjour: the manufacturer often says what kind of thing a device is.
    public static func infer(vendor: String?) -> Self? {
        guard let vendor = vendor?.lowercased() else { return nil }
        let table: [(String, Self)] = [
            ("espressif", .smartHome), ("tuya", .smartHome), ("shelly", .smartHome), ("signify", .smartHome), ("philips lighting", .smartHome),
            ("xiaomi", .smartHome), ("ezviz", .smartHome), ("hikvision", .smartHome), ("ring", .smartHome), ("nest", .smartHome),
            ("hewlett packard", .printer), ("hp inc", .printer), ("canon", .printer), ("seiko epson", .printer), ("brother", .printer),
            ("sonos", .speaker), ("bose", .speaker), ("roku", .tv), ("lg electronics", .tv), ("vizio", .tv), ("tcl", .tv),
            ("raspberry", .computer), ("synology", .computer), ("qnap", .computer), ("intel", .computer), ("dell", .computer), ("lenovo", .computer),
            ("ubiquiti", .router), ("tp-link", .router), ("netgear", .router), ("zyxel", .router), ("mikrotik", .router), ("huawei", .unknown),
            ("apple", .appleDevice), ("samsung", .unknown),
        ]
        return table.first { vendor.contains($0.0) }?.1
    }
}

// MARK: - Ports

public struct LANPort: Hashable, Sendable, Identifiable {
    public let number: UInt16
    public let name: String
    public let risk: String?
    public var id: UInt16 { number }
    /// Opens in a browser.
    public var isWeb: Bool { [80, 443, 8080, 8443, 8000, 8008, 5000].contains(number) }
    public var scheme: String { [443, 8443].contains(number) ? "https" : "http" }

    /// Common services on home and office networks, with a note for the ones that are risky to leave open.
    public static let common: [LANPort] = [
        .init(number: 21, name: "FTP", risk: String(localized: "FTP parolaları şifrelemeden gönderir.")),
        .init(number: 22, name: "SSH", risk: nil),
        .init(number: 23, name: "Telnet", risk: String(localized: "Telnet şifresizdir; uzaktan erişim için güvenli değildir.")),
        .init(number: 53, name: "DNS", risk: nil),
        .init(number: 80, name: String(localized: "Web (HTTP)"), risk: nil),
        .init(number: 139, name: "NetBIOS", risk: String(localized: "Eski Windows paylaşımı; gerekmiyorsa kapatılmalı.")),
        .init(number: 443, name: String(localized: "Web (HTTPS)"), risk: nil),
        .init(number: 445, name: String(localized: "Dosya paylaşımı (SMB)"), risk: nil),
        .init(number: 548, name: "AFP", risk: nil),
        .init(number: 554, name: String(localized: "Kamera akışı (RTSP)"), risk: nil),
        .init(number: 631, name: String(localized: "Yazdırma (IPP)"), risk: nil),
        .init(number: 1883, name: "MQTT", risk: String(localized: "MQTT şifresiz; akıllı ev mesajları ağda okunabilir.")),
        .init(number: 3389, name: String(localized: "Uzak Masaüstü (RDP)"), risk: String(localized: "RDP sık saldırı hedefidir; ağ dışına açık olmamalı.")),
        .init(number: 5000, name: String(localized: "Web / AirPlay"), risk: nil),
        .init(number: 5900, name: String(localized: "Ekran paylaşımı (VNC)"), risk: nil),
        .init(number: 7000, name: "AirPlay", risk: nil),
        .init(number: 8008, name: "Google Cast", risk: nil),
        .init(number: 8080, name: String(localized: "Web (alternatif)"), risk: nil),
        .init(number: 8443, name: String(localized: "Web (HTTPS alternatif)"), risk: nil),
        .init(number: 9100, name: String(localized: "Ham yazdırma"), risk: nil),
        .init(number: 62078, name: String(localized: "iPhone eşzamanlama"), risk: nil),
    ]
}

public enum LANPortScanner {
    /// TCP connect to each port; a completed handshake means open. Refused or silent ports count as closed.
    public static func scan(_ ip: String, ports: [LANPort] = LANPort.common, timeout: TimeInterval = 1.2) async -> [LANPort] {
        await withTaskGroup(of: LANPort?.self) { group in
            for port in ports {
                group.addTask { await isOpen(ip, port.number, timeout: timeout) ? port : nil }
            }
            var open: [LANPort] = []
            for await port in group { if let port { open.append(port) } }
            return open.sorted { $0.number < $1.number }
        }
    }

    static func isOpen(_ ip: String, _ port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: endpointPort, using: .tcp)
        let gate = OnceGate()
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if gate.open() { continuation.resume(returning: true) }
                connection.cancel()
                case .failed, .waiting: if gate.open() { continuation.resume(returning: false) }
                connection.cancel()
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if gate.open() { continuation.resume(returning: false) }
                connection.cancel()
            }
        }
    }

    /// The `<title>` of a device's web interface, read once with a short timeout.
    public static func webTitle(_ ip: String, port: LANPort) async -> String? {
        guard let url = URL(string: "\(port.scheme)://\(ip):\(port.number)/") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration, delegate: TrustingDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        return title(in: String(decoding: data.prefix(64_000), as: UTF8.self))
    }

    public static func title(in html: String) -> String? {
        guard let start = html.range(of: "<title", options: .caseInsensitive),
              let open = html[start.upperBound...].firstIndex(of: ">"),
              let end = html[open...].range(of: "</title>", options: .caseInsensitive) else { return nil }
        let raw = html[html.index(after: open)..<end.lowerBound]
        let text = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(120))
    }
}

/// Local devices use self-signed certificates; the title is read-only information, so any certificate is
/// accepted.
private final class TrustingDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trust = challenge.protectionSpace.serverTrust { return (.useCredential, URLCredential(trust: trust)) }
        return (.performDefaultHandling, nil)
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func open() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

// MARK: - Ping series

public struct PingStatistics: Equatable, Sendable {
    public let sent: Int
    public let received: Int
    public let average: TimeInterval?
    public let minimum: TimeInterval?
    public let maximum: TimeInterval?
    /// Mean difference between consecutive replies.
    public let jitter: TimeInterval?

    public var lossPercent: Double { sent == 0 ? 0 : Double(sent - received) / Double(sent) * 100 }

    /// `samples` holds one entry per ping: the round trip, or nil when it timed out.
    public init(samples: [TimeInterval?]) {
        let replies = samples.compactMap { $0 }
        sent = samples.count
        received = replies.count
        average = replies.isEmpty ? nil : replies.reduce(0, +) / Double(replies.count)
        minimum = replies.min()
        maximum = replies.max()
        jitter = replies.count < 2 ? nil : zip(replies, replies.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(replies.count - 1)
    }
}

extension LANScanner {
    /// One echo to one host; nil when it doesn't answer within `timeout`.
    public static func ping(_ ip: String, timeout: TimeInterval = 1) async -> TimeInterval? {
        guard let host = IPv4.parse(ip) else { return nil }
        return await pingSweep([host], timeout: timeout)[ip]
    }
}

// MARK: - Wake-on-LAN

public enum WakeOnLAN {
    /// Six 0xFF bytes followed by the target address sixteen times.
    public static func magicPacket(for mac: String) -> [UInt8]? {
        let octets = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard octets.count == 6 else { return nil }
        return [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: octets, count: 16).joined())
    }

    /// Broadcasts the magic packet on the local subnet (UDP port 9). Works only if the device enabled wake on
    /// LAN.
    @discardableResult
    public static func wake(mac: String, broadcast: String) -> Bool {
        guard var packet = magicPacket(for: mac), let address = IPv4.parse(broadcast) else { return false }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UInt16(9).bigEndian
        target.sin_addr.s_addr = address.bigEndian
        let sent = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(descriptor, &packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return sent == packet.count
    }
}

// MARK: - NetBIOS

/// NetBIOS node status ("NBSTAT", UDP 137): the reply carries the device's own names and its MAC address.
/// Unlike ARP it is an ordinary IP packet, so it also works across routers; but only Windows PCs, Samba
/// servers (NAS, Linux) and some printers answer it.
public enum NetBIOS {
    public struct Status: Equatable, Sendable {
        public let name: String?
        public let workgroup: String?
        public let mac: String?
    }

    /// A status query for the wildcard name "*".
    public static func statusQuery(transaction: UInt16) -> [UInt8] {
        var packet: [UInt8] = [UInt8(transaction >> 8), UInt8(transaction & 0xFF), 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        var name = [UInt8]("*".utf8) + [UInt8](repeating: 0, count: 15)
        name = Array(name.prefix(16))
        packet.append(0x20)
        for byte in name { packet += [0x41 + (byte >> 4), 0x41 + (byte & 0x0F)] }  // First-level encoding
        packet += [0x00, 0x00, 0x21, 0x00, 0x01]  // NBSTAT, IN
        return packet
    }

    public static func parseStatus(_ bytes: [UInt8]) -> Status? {
        guard bytes.count > 12, bytes[2] & 0x80 != 0, (UInt16(bytes[6]) << 8 | UInt16(bytes[7])) >= 1 else { return nil }
        var offset = 12
        // Answer name: labels until a zero byte (or a compression pointer).
        while offset < bytes.count {
            let length = Int(bytes[offset])
            if length == 0 { offset += 1; break }
            if length & 0xC0 == 0xC0 { offset += 2; break }
            offset += 1 + length
        }
        offset += 2 + 2 + 4  // type, class, ttl
        guard offset + 3 <= bytes.count else { return nil }
        offset += 2  // rdlength
        let count = Int(bytes[offset])
        offset += 1
        var name: String?, workgroup: String?
        for _ in 0..<count {
            guard offset + 18 <= bytes.count else { return nil }
            let raw = bytes[offset..<offset + 15]
            let suffix = bytes[offset + 15]
            let flags = UInt16(bytes[offset + 16]) << 8 | UInt16(bytes[offset + 17])
            let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces.union(.controlCharacters))
            let group = flags & 0x8000 != 0
            if suffix == 0x00, !text.isEmpty, !text.hasPrefix("\u{01}") {
                if group { workgroup = workgroup ?? text } else { name = name ?? text }
            }
            offset += 18
        }
        var mac: String?
        if offset + 6 <= bytes.count {
            let octets = bytes[offset..<offset + 6]
            if octets.contains(where: { $0 != 0 }) { mac = octets.map { String(format: "%02X", $0) }.joined(separator: ":") }
        }
        return Status(name: name, workgroup: workgroup, mac: mac)
    }

    /// Queries every address from one UDP socket and collects the replies that arrive within `timeout`.
    public static func status(of ips: [String], timeout: TimeInterval = 1.5) async -> [String: Status] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: statusBlocking(ips, timeout: timeout)) }
        }
    }

    private static func statusBlocking(_ ips: [String], timeout: TimeInterval) -> [String: Status] {
        guard !ips.isEmpty else { return [:] }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return [:] }
        defer { close(descriptor) }
        let transaction = UInt16.random(in: 1...UInt16.max)
        var packet = statusQuery(transaction: transaction)
        for ip in ips {
            guard let value = IPv4.parse(ip) else { continue }
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = UInt16(137).bigEndian
            target.sin_addr.s_addr = value.bigEndian
            _ = withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, &packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        var results: [String: Status] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 1500)
        while Date() < deadline, results.count < ips.count {
            var poll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&poll, 1, Int32(max(1, deadline.timeIntervalSinceNow * 1000))) > 0 else { break }
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(descriptor, &buffer, buffer.count, 0, $0, &length) }
            }
            let reply = Array(buffer.prefix(max(0, count)))
            let ip = IPv4.text(UInt32(bigEndian: source.sin_addr.s_addr))
            guard count > 12, source.sin_port == UInt16(137).bigEndian, ips.contains(ip),
                  UInt16(reply[0]) << 8 | UInt16(reply[1]) == transaction, let status = parseStatus(reply) else { continue }
            results[ip] = status
        }
        return results
    }
}

// MARK: - SNMP

/// Minimal SNMP v2c ("public" community) client: the device's name, description and own hardware address.
/// Switches, access points, printers and NAS boxes often answer it, and like NetBIOS it works across routers.
public enum SNMP {
    public struct Info: Equatable, Sendable {
        public var name: String?
        public var description: String?
        public var mac: String?
        /// False for an agent's first interface address when it does not expose its IP-to-interface mapping.
        public var macMatchesIP = false
    }

    static let sysDescr = [1, 3, 6, 1, 2, 1, 1, 1, 0]
    static let sysName = [1, 3, 6, 1, 2, 1, 1, 5, 0]
    static let ifPhysAddress = [1, 3, 6, 1, 2, 1, 2, 2, 1, 6]
    static let ipAdEntIfIndex = [1, 3, 6, 1, 2, 1, 4, 20, 1, 2]
    static let ipAddressIfIndex = [1, 3, 6, 1, 2, 1, 4, 34, 1, 3]

    static func interfaceIndexOIDs(for ip: String) -> [[Int]] {
        guard let value = IPv4.parse(ip) else { return [] }
        let octets = [24, 16, 8, 0].map { Int(value >> $0 & 0xFF) }
        return [ipAdEntIfIndex + octets, ipAddressIfIndex + [1, 4] + octets]
    }

    static func positiveInteger(_ bytes: [UInt8]) -> Int? {
        guard !bytes.isEmpty, bytes.count <= 4, bytes[0] & 0x80 == 0 else { return nil }
        let value = bytes.reduce(0) { $0 << 8 | Int($1) }
        return value > 0 ? value : nil
    }

    static func applyMAC(_ bytes: [UInt8], matchingIP: Bool, to info: inout Info) {
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes[0] & 1 == 0 else { return }
        guard matchingIP || info.mac == nil else { return }
        info.mac = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        info.macMatchesIP = matchingIP
    }

    // BER encoding.
    static func tlv(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] { [tag] + length(body.count) + body }
    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
    static func integer(_ value: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var rest = value
        repeat { bytes.insert(UInt8(truncatingIfNeeded: rest & 0xFF), at: 0); rest >>= 8 } while rest > 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, bytes)
    }
    static func oid(_ arcs: [Int]) -> [UInt8] {
        var body: [UInt8] = [UInt8(arcs[0] * 40 + arcs[1])]
        for arc in arcs.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(arc & 0x7F)]
            var value = arc >> 7
            while value > 0 { chunk.insert(UInt8(value & 0x7F) | 0x80, at: 0); value >>= 7 }
            body += chunk
        }
        return tlv(0x06, body)
    }

    /// GetRequest (0xA0) or GetNextRequest (0xA1) for the given OIDs.
    public static func request(id: Int, next: Bool, oids: [[Int]], community: String = "public") -> [UInt8] {
        let bindings = oids.flatMap { tlv(0x30, oid($0) + [0x05, 0x00]) }
        let pdu = tlv(next ? 0xA1 : 0xA0, integer(id) + integer(0) + integer(0) + tlv(0x30, bindings))
        return tlv(0x30, integer(1) + tlv(0x04, Array(community.utf8)) + pdu)
    }

    struct Element { let tag: UInt8; let body: ArraySlice<UInt8> }

    static func elements(_ bytes: ArraySlice<UInt8>) -> [Element]? {
        var result: [Element] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let tag = bytes[index]
            index += 1
            guard index < bytes.endIndex else { return nil }
            var count = Int(bytes[index])
            index += 1
            if count & 0x80 != 0 {
                let octets = count & 0x7F
                guard octets <= 3, index + octets <= bytes.endIndex else { return nil }
                count = bytes[index..<index + octets].reduce(0) { $0 << 8 | Int($1) }
                index += octets
            }
            guard index + count <= bytes.endIndex else { return nil }
            result.append(Element(tag: tag, body: bytes[index..<index + count]))
            index += count
        }
        return result
    }

    static func decodeOID(_ body: ArraySlice<UInt8>) -> [Int] {
        guard let first = body.first else { return [] }
        var arcs = [Int(first) / 40, Int(first) % 40]
        var value = 0
        for byte in body.dropFirst() {
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { arcs.append(value); value = 0 }
        }
        return arcs
    }

    /// A GetResponse: request id and (oid, raw value) pairs.
    public static func response(_ bytes: [UInt8]) -> (id: Int, bindings: [([Int], UInt8, [UInt8])])? {
        guard let message = elements(bytes[...])?.first, message.tag == 0x30, let parts = elements(message.body), parts.count == 3,
              parts[2].tag == 0xA2, let pdu = elements(parts[2].body), pdu.count == 4, pdu[3].tag == 0x30,
              pdu[0].tag == 0x02, !pdu[0].body.isEmpty, pdu[0].body.count <= 4,
              pdu[1].tag == 0x02, Array(pdu[1].body) == [0],
              let list = elements(pdu[3].body) else { return nil }
        let id = pdu[0].body.reduce(0) { $0 << 8 | Int($1) }
        let bindings = list.compactMap { binding -> ([Int], UInt8, [UInt8])? in
            guard let pair = elements(binding.body), pair.count == 2, pair[0].tag == 0x06 else { return nil }
            return (decodeOID(pair[0].body), pair[1].tag, Array(pair[1].body))
        }
        return (id, bindings)
    }

    /// Asks every address for its name, description and first non-zero interface address.
    public static func query(_ ips: [String], timeout: TimeInterval = 2) async -> [String: Info] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: queryBlocking(ips, timeout: timeout)) }
        }
    }

    private static func queryBlocking(_ ips: [String], timeout: TimeInterval) -> [String: Info] {
        guard !ips.isEmpty else { return [:] }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return [:] }
        defer { close(descriptor) }
        var pending: [String: Set<Int>] = [:]
        func send(_ packet: [UInt8], id: Int, to ip: String) {
            guard let value = IPv4.parse(ip) else { return }
            pending[ip, default: []].insert(id)
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = UInt16(161).bigEndian
            target.sin_addr.s_addr = value.bigEndian
            var bytes = packet
            _ = withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, &bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        let base = Int.random(in: 1_000...1_000_000)
        for (index, ip) in ips.enumerated() {
            let id = base + index * 16
            send(request(id: id, next: false, oids: [sysName, sysDescr]), id: id, to: ip)
            for (offset, oid) in interfaceIndexOIDs(for: ip).enumerated() {
                let mappingID = id + 1 + offset
                send(request(id: mappingID, next: false, oids: [oid]), id: mappingID, to: ip)
            }
            send(request(id: id + 3, next: true, oids: [ifPhysAddress]), id: id + 3, to: ip)
        }
        var results: [String: Info] = [:]
        var steps: [String: Int] = [:]
        var interfaceIndices: [String: Int] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var poll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&poll, 1, Int32(max(1, deadline.timeIntervalSinceNow * 1000))) > 0 else { break }
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(descriptor, &buffer, buffer.count, 0, $0, &length) }
            }
            let ip = IPv4.text(UInt32(bigEndian: source.sin_addr.s_addr))
            guard count > 0, source.sin_port == UInt16(161).bigEndian, let index = ips.firstIndex(of: ip),
                  let reply = response(Array(buffer.prefix(count))), pending[ip]?.remove(reply.id) != nil else { continue }
            var info = results[ip] ?? Info()
            for (oid, tag, value) in reply.bindings {
                if tag == 0x02, interfaceIndexOIDs(for: ip).contains(oid), let interfaceIndex = positiveInteger(value) {
                    if interfaceIndices[ip] == nil {
                        interfaceIndices[ip] = interfaceIndex
                        let id = base + index * 16 + 4
                        send(request(id: id, next: false, oids: [ifPhysAddress + [interfaceIndex]]), id: id, to: ip)
                    }
                    continue
                }
                guard tag == 0x04 else { continue }
                if oid == sysName { info.name = text(value) }
                else if oid == sysDescr { info.description = text(value) }
                else if Array(oid.prefix(ifPhysAddress.count)) == ifPhysAddress {
                    let matchingIP = interfaceIndices[ip].map { oid == ifPhysAddress + [$0] } ?? false
                    applyMAC(value, matchingIP: matchingIP, to: &info)
                    if info.mac == nil, steps[ip, default: 0] < 6 {
                        // Loopback and virtual interfaces report no address: walk on to the next one.
                        steps[ip, default: 0] += 1
                        let id = base + index * 16 + 4 + steps[ip]!
                        send(request(id: id, next: true, oids: [oid]), id: id, to: ip)
                    }
                }
            }
            results[ip] = info
        }
        return results
    }

    static func text(_ bytes: [UInt8]) -> String? {
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return value.isEmpty ? nil : String(value.prefix(160))
    }
}

// MARK: - Same-wire ARP for routed ranges

/// Management VLANs often share the wire with the main network. Marking the range as on-link for a moment
/// lets macOS ARP the hosts directly, the way Windows does for any address; the route is removed again in the
/// same command.
public enum LANOnLinkProbe {
    /// Built only from a parsed subnet, a validated interface name and host numbers; safe for the
    /// administrator shell.
    public static func command(subnet: LANSubnet, interface: String, hosts: [String]) -> String? {
        guard !interface.isEmpty, interface.allSatisfy({ $0.isLetter || $0.isNumber }), interface.count <= 15 else { return nil }
        let ips = hosts.filter { IPv4.parse($0).map { $0 & subnet.mask == subnet.network } ?? false }
        guard !ips.isEmpty else { return nil }
        let net = subnet.description
        // Bound concurrent child processes when probing the full /22–/30 range, including hosts silent to
        // routed ICMP.
        let pings = ips.enumerated().map { index, ip in
            "/sbin/ping -c 1 -t 1 \(ip) >/dev/null 2>&1 &" + ((index + 1) % 32 == 0 ? " wait;" : "")
        }.joined(separator: " ")
        // Install cleanup only after adding our own route. An existing route must never be deleted when add
        // fails.
        let cleanup = "/sbin/route -n delete -net \(net) -interface \(interface) >/dev/null 2>&1"
        return "/sbin/route -n add -net \(net) -interface \(interface) >/dev/null 2>&1 || exit $?; "
            + "trap '\(cleanup)' EXIT; trap 'exit 1' HUP INT TERM; \(pings) wait; sleep 2; /usr/sbin/arp -an"
    }

    public static func run(subnet: LANSubnet, interface: String, hosts: [String]) async throws -> [ARPEntry] {
        guard let command = command(subnet: subnet, interface: interface, hosts: hosts) else { return [] }
        let output = try await AdministratorShell.runInSeparateProcess(command)
        let normalized = output.replacingOccurrences(of: "\r", with: "\n")
        return entries(in: normalized, subnet: subnet, interface: interface, hosts: hosts)
    }

    static func entries(in output: String, subnet: LANSubnet, interface: String, hosts: [String]) -> [ARPEntry] {
        let requested = Set(hosts)
        return ARPTable.parse(output).filter { $0.interface == interface && requested.contains($0.ip)
            && (IPv4.parse($0.ip).map { $0 & subnet.mask == subnet.network } ?? false) }
    }
}

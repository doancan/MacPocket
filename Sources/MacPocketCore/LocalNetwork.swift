import Darwin
import Foundation
import Network
import SystemConfiguration

// MARK: - Addresses

public enum IPv4 {
    public static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = value << 8 | UInt32(octet)
        }
        return value
    }

    public static func text(_ value: UInt32) -> String {
        "\(value >> 24 & 0xFF).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }
}

/// The hosts worth probing on the local subnet. Large networks are narrowed to the /24 around this Mac, so a
/// scan stays a few hundred packets.
public struct LANSubnet: Equatable, Sendable {
    public let address: UInt32
    public let mask: UInt32
    public static let maximumHosts = 1022

    public init(address: UInt32, mask: UInt32) {
        self.address = address
        // Anything bigger than /22 is scanned as the /24 this Mac sits in.
        self.mask = (~mask) > UInt32(Self.maximumHosts + 1) ? 0xFFFF_FF00 : mask
    }

    public var prefixLength: Int { mask.nonzeroBitCount }
    public var network: UInt32 { address & mask }
    public var broadcast: UInt32 { network | ~mask }

    /// Every usable host address except this Mac's own.
    public var hosts: [UInt32] {
        guard broadcast > network + 1 else { return [] }
        return (network + 1 ..< broadcast).filter { $0 != address }
    }

    public var description: String { "\(IPv4.text(network))/\(prefixLength)" }
}

public enum MACAddress {
    /// "0:1b:21:bc:4c:d3" → "00:1B:21:BC:4C:D3"; nil for anything that isn't six octets.
    public static func normalize(_ text: String) -> String? {
        let parts = text.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var octets: [String] = []
        for part in parts {
            guard part.count <= 2, let value = UInt8(part, radix: 16) else { return nil }
            octets.append(String(format: "%02X", value))
        }
        return octets.joined(separator: ":")
    }

    /// Locally administered: phones and computers use these as private, per-network Wi-Fi addresses.
    public static func isPrivate(_ mac: String) -> Bool {
        guard let first = UInt8(mac.prefix(2), radix: 16) else { return false }
        return first & 0x02 != 0
    }

    public static func isMulticastOrBroadcast(_ mac: String) -> Bool {
        guard let first = UInt8(mac.prefix(2), radix: 16) else { return true }
        return first & 0x01 != 0
    }
}

public struct ARPEntry: Equatable, Sendable {
    public let ip: String
    public let mac: String
    public let interface: String
}

public enum ARPTable {
    /// Parses `arp -an`: "? (192.168.0.1) at 0:1b:21:bc:4c:d3 on en1 ifscope [ethernet]". Incomplete entries,
    /// broadcast and multicast addresses are skipped.
    public static func parse(_ output: String) -> [ARPEntry] {
        output.split(separator: "\n").compactMap { line in
            let words = line.split(separator: " ")
            guard let at = words.firstIndex(of: "at"), at > 0, words.indices.contains(at + 1),
                  let on = words.firstIndex(of: "on"), words.indices.contains(on + 1) else { return nil }
            let ip = words[at - 1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            guard IPv4.parse(ip) != nil, let mac = MACAddress.normalize(String(words[at + 1])),
                  !MACAddress.isMulticastOrBroadcast(mac) else { return nil }
            return ARPEntry(ip: ip, mac: mac, interface: String(words[on + 1]))
        }
    }
}

// MARK: - ICMP

public enum ICMPEcho {
    /// Echo request (type 8) with a checksum; the payload carries nothing but padding.
    public static func request(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet: [UInt8] = [8, 0, 0, 0, UInt8(identifier >> 8), UInt8(identifier & 0xFF),
                               UInt8(sequence >> 8), UInt8(sequence & 0xFF)] + [UInt8](repeating: 0x4D, count: 24)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count { sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1]); index += 2 }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// An echo reply (type 0) as received on a datagram ICMP socket, which still carries the IPv4 header.
    public static func reply(_ bytes: [UInt8]) -> (identifier: UInt16, sequence: UInt16)? {
        var offset = 0
        if let first = bytes.first, first >> 4 == 4 { offset = Int(first & 0x0F) * 4 }
        guard bytes.count >= offset + 8, bytes[offset] == 0 else { return nil }
        return (UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5]), UInt16(bytes[offset + 6]) << 8 | UInt16(bytes[offset + 7]))
    }
}

// MARK: - Devices

public enum LANDeviceKind: String, Codable, Sendable, CaseIterable {
    case router, thisMac, appleDevice, computer, printer, tv, speaker, smartHome, unknown

    public var title: String {
        switch self {
        case .router: String(localized: "Yönlendirici")
        case .thisMac: String(localized: "Bu Mac")
        case .appleDevice: String(localized: "Apple aygıtı")
        case .computer: String(localized: "Bilgisayar")
        case .printer: String(localized: "Yazıcı")
        case .tv: String(localized: "TV / yayın")
        case .speaker: String(localized: "Hoparlör")
        case .smartHome: String(localized: "Akıllı ev")
        case .unknown: String(localized: "Bilinmeyen")
        }
    }

    public var symbol: String {
        switch self {
        case .router: "wifi.router"
        case .thisMac: "desktopcomputer"
        case .appleDevice: "iphone"
        case .computer: "laptopcomputer"
        case .printer: "printer"
        case .tv: "tv"
        case .speaker: "hifispeaker"
        case .smartHome: "homekit"
        case .unknown: "questionmark.circle"
        }
    }

    /// The most telling Bonjour service wins: a TV that also offers AirPlay audio is still a TV.
    public static func infer(services: Set<String>, model: String?, name: String? = nil) -> Self {
        if let model = model?.lowercased() {
            if model.contains("appletv") { return .tv }
            if model.contains("audioaccessory") || model.contains("homepod") { return .speaker }
            if model.hasPrefix("mac") || model.contains("imac") { return .computer }
            if model.contains("iphone") || model.contains("ipad") { return .appleDevice }
        }
        // Macs also advertise AirPlay receivers; the name a person gave them is the clearer hint.
        if let name = name?.lowercased(), services.contains("_companion-link._tcp") {
            if name.contains("iphone") || name.contains("ipad") || name.contains("watch") { return .appleDevice }
            if name.contains("mac") { return .computer }
            if name.contains("homepod") { return .speaker }
            if name.contains("apple tv") { return .tv }
        }
        if services.contains("_ipp._tcp") || services.contains("_ipps._tcp") || services.contains("_printer._tcp")
            || services.contains("_pdl-datastream._tcp") { return .printer }
        if services.contains("_googlecast._tcp") || services.contains("_airplay._tcp") { return .tv }
        if services.contains("_raop._tcp") || services.contains("_spotify-connect._tcp") || services.contains("_sonos._tcp") { return .speaker }
        if services.contains("_hap._tcp") || services.contains("_matter._tcp") || services.contains("_matterc._udp") { return .smartHome }
        if services.contains("_companion-link._tcp") || services.contains("_apple-mobdev2._tcp") { return .appleDevice }
        if services.contains("_smb._tcp") || services.contains("_afpovertcp._tcp") || services.contains("_ssh._tcp")
            || services.contains("_sftp-ssh._tcp") || services.contains("_rfb._tcp") { return .computer }
        return .unknown
    }
}

public struct LANDevice: Equatable, Sendable, Identifiable {
    public var ip: String
    public var mac: String?
    public var bonjourName: String?
    public var hostName: String?
    public var model: String?
    public var services: Set<String> = []
    /// Round trip of the ping, nil when the device didn't answer (many phones and IoT devices ignore pings).
    public var latency: TimeInterval?
    public var isGateway = false
    public var isSelf = false
    /// Computer name and workgroup from a NetBIOS status reply (Windows, Samba).
    public var netbiosName: String?
    public var workgroup: String?
    /// Name and description an SNMP agent reported (often the model and firmware).
    public var snmpName: String?
    public var snmpDescription: String?
    /// Where the hardware address came from; only ARP sees it directly, NetBIOS and SNMP replies carry it
    /// across routers.
    public enum MACSource: String, Sendable { case arp, netbios, snmp, snmpInterface }
    public var macSource = MACSource.arp
    public var macFromNetBIOS: Bool { macSource == .netbios }

    public init(ip: String, mac: String? = nil) { self.ip = ip; self.mac = mac }

    public var id: String { ip }
    public var responded: Bool { latency != nil }
    public var kind: LANDeviceKind {
        if isSelf { return .thisMac }
        if isGateway { return .router }
        let kind = LANDeviceKind.infer(services: services, model: model, name: bonjourName)
        if kind != .unknown { return kind }
        if let description = snmpDescription?.lowercased() {
            if ["switch", "swos", "routeros", "router", "firewall", "access point", "unifi", "edgeos"].contains(where: description.contains) { return .router }
            if ["printer", "laserjet", "jetdirect"].contains(where: description.contains) { return .printer }
            return .computer
        }
        return netbiosName != nil ? .computer : kind
    }
    public var displayName: String? { bonjourName ?? netbiosName ?? snmpName ?? hostName.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 } }
    public var sortKey: UInt32 { IPv4.parse(ip) ?? .max }
}

/// Devices the user has seen before, keyed by MAC address, with optional names they gave them.
public struct LANKnownDevices: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var firstSeen: Date
        public var lastSeen: Date
        public var customName: String?
    }

    public var records: [String: Record] = [:]
    public init(records: [String: Record] = [:]) { self.records = records }

    /// Records the devices of a scan and returns the MAC addresses seen for the first time. The very first
    /// scan marks nothing as new: everything on the network then is the baseline.
    @discardableResult
    public mutating func update(with devices: [LANDevice], at date: Date = Date()) -> Set<String> {
        let baseline = records.isEmpty
        var fresh = Set<String>()
        for mac in devices.compactMap(\.mac) {
            if records[mac] == nil {
                records[mac] = Record(firstSeen: date, lastSeen: date)
                if !baseline { fresh.insert(mac) }
            } else {
                records[mac]?.lastSeen = date
            }
        }
        return fresh
    }

    public func name(for mac: String?) -> String? { mac.flatMap { records[$0]?.customName } }

    public mutating func rename(_ mac: String, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        records[mac]?.customName = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    public mutating func forget(_ mac: String) { records.removeValue(forKey: mac) }
}

// MARK: - Scanner

public struct LANNetworkInfo: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case wifi, ethernet, bridge, other, custom }

    /// BSD name ("en1"); empty for a custom range reached through the router.
    public let interface: String
    /// This Mac's address on the network; for a custom range, the address used to reach it.
    public let address: String
    public let subnet: LANSubnet
    public let gateway: String?
    public var name: String = ""
    public var kind: Kind = .other
    /// Directly attached: hardware addresses and Bonjour are only visible on such networks.
    public var isLocal = true
    /// Carries the default route.
    public var isPrimary = false
    /// The interface used to reach a routed range (for the on-link probe).
    public var viaInterface = ""

    public init(interface: String, address: String, subnet: LANSubnet, gateway: String?, name: String = "", kind: Kind = .other,
                isLocal: Bool = true, isPrimary: Bool = false) {
        self.interface = interface
        self.address = address
        self.subnet = subnet
        self.gateway = gateway
        self.name = name
        self.kind = kind
        self.isLocal = isLocal
        self.isPrimary = isPrimary
    }

    public var id: String { "\(interface)|\(subnet.description)" }
    public var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .bridge: "bolt.horizontal"
        case .other: "network"
        case .custom: "point.3.connected.trianglepath.dotted"
        }
    }

    public func contains(_ ip: String) -> Bool {
        IPv4.parse(ip).map { $0 & subnet.mask == subnet.network } ?? false
    }
}

extension LANSubnet: Hashable {}

extension LANSubnet {
    /// "10.0.20.0/24" or "10.0.20.7/24". Ranges larger than /22 are refused rather than silently narrowed.
    public static func parse(cidr text: String) -> LANSubnet? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2, let address = IPv4.parse(String(parts[0])), let prefix = Int(parts[1]), (22...30).contains(prefix) else { return nil }
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        return LANSubnet(address: address & mask, mask: mask)
    }
}

public enum LANScanError: Error, LocalizedError, Equatable {
    case noNetwork
    public var errorDescription: String? { String(localized: "Etkin bir yerel ağ bağlantısı bulunamadı.") }
}

public struct LANScanResult: Sendable, Identifiable {
    public var id: String { network.id }

    public init(network: LANNetworkInfo, devices: [LANDevice], date: Date) {
        self.network = network
        self.devices = devices
        self.date = date
    }
    public let network: LANNetworkInfo
    public let devices: [LANDevice]
    public let date: Date

    /// ARP may discover hosts that ignore ICMP, so merge it as discovery rather than only filling existing
    /// rows.
    public func mergingARP(_ entries: [ARPEntry]) -> LANScanResult {
        var byIP = Dictionary(devices.map { ($0.ip, $0) }, uniquingKeysWith: { first, _ in first })
        let interface = network.isLocal ? network.interface : network.viaInterface
        for entry in entries where entry.interface == interface && network.contains(entry.ip) {
            guard let mac = MACAddress.normalize(entry.mac), !MACAddress.isMulticastOrBroadcast(mac) else { continue }
            var device = byIP[entry.ip] ?? LANDevice(ip: entry.ip)
            device.mac = mac
            device.macSource = .arp
            byIP[entry.ip] = device
        }
        return LANScanResult(network: network, devices: byIP.values.sorted { $0.sortKey < $1.sortKey }, date: Date())
    }
}

/// Finds devices on the local network: a ping sweep for liveness and latency, the ARP table for hardware
/// addresses, Bonjour for names and device types, reverse DNS for the rest. Nothing leaves the local network.
public enum LANScanner {
    static let bonjourTypes = ["_companion-link._tcp", "_airplay._tcp", "_raop._tcp", "_googlecast._tcp", "_ipp._tcp",
                               "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp", "_hap._tcp", "_matter._tcp",
                               "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_rfb._tcp",
                               "_spotify-connect._tcp", "_sonos._tcp", "_apple-mobdev2._tcp", "_device-info._tcp", "_http._tcp"]

    public static func currentNetwork() async -> LANNetworkInfo? {
        let route = try? await BoundedProcess.run("/sbin/route", ["-n", "get", "default"], timeout: 3)
        var interface: String?, gateway: String?
        for line in route?.output.split(separator: "\n") ?? [] {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "interface" { interface = parts[1] }
            if parts[0] == "gateway", IPv4.parse(parts[1]) != nil { gateway = parts[1] }
        }
        guard let interface, let (address, mask) = ipv4(of: interface) else { return nil }
        return LANNetworkInfo(interface: interface, address: IPv4.text(address), subnet: LANSubnet(address: address, mask: mask),
                              gateway: gateway)
    }

    /// Every attached IPv4 network: Wi-Fi, Ethernet, Thunderbolt bridge, adapters. Loopback and tunnels are
    /// left out; the network with the default route comes first.
    public static func availableNetworks() async -> [LANNetworkInfo] {
        let primary = await currentNetwork()
        let names = interfaceNames()
        var networks: [LANNetworkInfo] = []
        for (interface, address, mask) in ipv4Interfaces() {
            let excluded = ["lo", "utun", "awdl", "llw", "gif", "stf", "ipsec", "ppp", "anpi", "ap"]
            guard !excluded.contains(where: { interface.hasPrefix($0) }) else { continue }
            let subnet = LANSubnet(address: address, mask: mask)
            let isPrimary = primary?.interface == interface
            var gateway = isPrimary ? primary?.gateway : nil
            if gateway == nil, let router = try? await BoundedProcess.run("/usr/sbin/ipconfig", ["getoption", interface, "router"], timeout: 2),
               IPv4.parse(router.output.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                gateway = router.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let info = names[interface]
            networks.append(LANNetworkInfo(interface: interface, address: IPv4.text(address), subnet: subnet, gateway: gateway,
                                           name: info?.name ?? interface, kind: info?.kind ?? .other, isLocal: true, isPrimary: isPrimary))
        }
        return networks.sorted { ($0.isPrimary ? 0 : 1, $0.interface) < ($1.isPrimary ? 0 : 1, $1.interface) }
    }

    /// A range reached through the router (another VLAN or office subnet).
    public static func customNetwork(_ subnet: LANSubnet, name: String, attached: [LANNetworkInfo]) -> LANNetworkInfo {
        // A range that is really one of the attached networks behaves like it.
        if let local = attached.first(where: { $0.subnet.network == subnet.network && $0.subnet.mask == subnet.mask }) { return local }
        var network = LANNetworkInfo(interface: "", address: attached.first(where: \.isPrimary)?.address ?? "", subnet: subnet, gateway: nil,
                                     name: name.isEmpty ? subnet.description : name, kind: .custom, isLocal: false)
        network.viaInterface = attached.first(where: \.isPrimary)?.interface ?? ""
        return network
    }

    static func ipv4Interfaces() -> [(String, UInt32, UInt32)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [(String, UInt32, UInt32)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_addr, let netmask = entry.ifa_netmask, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            result.append((String(cString: entry.ifa_name), ip, mask))
        }
        return result
    }

    /// Localized names macOS shows in Network settings ("Wi-Fi", "Ethernet", "Thunderbolt Bridge").
    static func interfaceNames() -> [String: (name: String, kind: LANNetworkInfo.Kind)] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var names: [String: (String, LANNetworkInfo.Kind)] = [:]
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsd
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String? ?? ""
            let kind: LANNetworkInfo.Kind = type == (kSCNetworkInterfaceTypeIEEE80211 as String) ? .wifi
                : bsd.hasPrefix("bridge") ? .bridge
                : type == (kSCNetworkInterfaceTypeEthernet as String) ? .ethernet : .other
            names[bsd] = (name, kind)
        }
        return names
    }

    static func ipv4(of interface: String) -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name) == interface, let address = entry.ifa_addr, let netmask = entry.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            return (ip, mask)
        }
        return nil
    }

    /// The network with the default route only.
    public static func scan(progress: (@Sendable (Double) async -> Void)? = nil) async throws -> LANScanResult {
        var network = await availableNetworks().first(where: \.isPrimary)
        if network == nil { network = await currentNetwork() }
        guard let network else { throw LANScanError.noNetwork }
        guard let result = try await scan(networks: [network], progress: progress).first else { throw LANScanError.noNetwork }
        return result
    }

    /// Scans several networks at once. Bonjour and the ARP table are read once and shared; each network gets
    /// its own ping sweep. Routed (custom) ranges get pings and reverse DNS only.
    public static func scan(networks: [LANNetworkInfo], progress: (@Sendable (Double) async -> Void)? = nil) async throws -> [LANScanResult] {
        guard !networks.isEmpty else { throw LANScanError.noNetwork }
        async let bonjour = browse(seconds: 4)
        await progress?(0.1)
        let sweeps = await withTaskGroup(of: (String, [String: TimeInterval]).self) { group in
            for network in networks {
                group.addTask { (network.id, await pingSweep(network.subnet.hosts, timeout: network.isLocal ? 2.5 : 3.5)) }
            }
            var all: [String: [String: TimeInterval]] = [:]
            for await (id, latencies) in group { all[id] = latencies }
            return all
        }
        await progress?(0.6)
        let (services, models) = await bonjour
        // Bonjour connections can populate ARP even for devices that ignore ICMP. Read it after discovery
        // finishes.
        let arp = (try? await BoundedProcess.run("/usr/sbin/arp", ["-an"], timeout: 5)).map { ARPTable.parse($0.output) } ?? []
        await progress?(0.75)
        var results: [LANScanResult] = []
        for network in networks {
            var devices: [String: LANDevice] = [:]
            if network.isLocal {
                for entry in arp where entry.interface == network.interface && network.contains(entry.ip) {
                    devices[entry.ip] = LANDevice(ip: entry.ip, mac: entry.mac)
                }
            }
            for (ip, latency) in sweeps[network.id] ?? [:] {
                devices[ip, default: LANDevice(ip: ip)].latency = latency
            }

            if network.isLocal, network.contains(network.address) {
                var me = LANDevice(ip: network.address)
                me.isSelf = true
                me.hostName = ProcessInfo.processInfo.hostName
                devices[network.address] = me
            }
            if let gateway = network.gateway, network.contains(gateway) { devices[gateway, default: LANDevice(ip: gateway)].isGateway = true }
            mergeBonjour(services, models: models, network: network, into: &devices)
            // NetBIOS answers carry a computer name and, across routers too, the hardware address.
            let netbios = await NetBIOS.status(of: devices.values.filter { !$0.isSelf && ($0.responded || $0.mac != nil) }.map(\.ip))
            for (ip, status) in netbios {
                if devices[ip]?.mac == nil, let mac = status.mac, !MACAddress.isMulticastOrBroadcast(mac) {
                    devices[ip]?.mac = mac
                    devices[ip]?.macSource = .netbios
                }
                devices[ip]?.netbiosName = status.name
                devices[ip]?.workgroup = status.workgroup
            }
            // SNMP (switches, access points, printers, NAS): name, model and, across routers too, the
            // hardware address.
            let snmp = await SNMP.query(devices.values.filter { !$0.isSelf && $0.responded }.map(\.ip))
            for (ip, info) in snmp {
                if devices[ip]?.mac == nil, let mac = info.mac, !MACAddress.isMulticastOrBroadcast(mac) {
                    devices[ip]?.mac = mac
                    devices[ip]?.macSource = info.macMatchesIP ? .snmp : .snmpInterface
                }
                devices[ip]?.snmpName = info.name
                devices[ip]?.snmpDescription = info.description
            }
            let names = await reverseNames(devices.values.filter { $0.bonjourName == nil && $0.netbiosName == nil && $0.snmpName == nil && !$0.isSelf }.map(\.ip))
            for (ip, name) in names { devices[ip]?.hostName = name }
            results.append(LANScanResult(network: network, devices: devices.values.sorted { $0.sortKey < $1.sortKey }, date: Date()))
        }
        await progress?(1)
        return results
    }

    /// Bonjour is an independent discovery source, including when ICMP is blocked and ARP has no entry yet.
    static func mergeBonjour(_ services: [BonjourService], models: [String: String], network: LANNetworkInfo,
                             into devices: inout [String: LANDevice]) {
        guard network.isLocal else { return }
        for found in services where network.contains(found.ip) {
            var device = devices[found.ip] ?? LANDevice(ip: found.ip)
            device.services.insert(found.type)
            if device.bonjourName == nil || found.type == "_companion-link._tcp" { device.bonjourName = found.name }
            if let model = models[found.name] ?? found.model { device.model = model }
            devices[found.ip] = device
        }
    }

    /// One datagram ICMP socket (no privileges needed), one echo per host, replies collected until `timeout`.
    static func pingSweep(_ hosts: [UInt32], timeout: TimeInterval) async -> [String: TimeInterval] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: pingSweepBlocking(hosts, timeout: timeout))
            }
        }
    }

    private static func pingSweepBlocking(_ hosts: [UInt32], timeout: TimeInterval) -> [String: TimeInterval] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { return [:] }
        defer { close(descriptor) }
        // A random identifier per sweep, and the reply's source address checked below, keep parallel sweeps
        // apart.
        let identifier = UInt16.random(in: 1...UInt16.max)
        // Requests go out on a second thread while this one reads replies, so a reply is timed when it
        // arrives rather than after the whole sweep has been sent (which inflated early hosts' round trips).
        let sent = SentLog()
        let sender = DispatchGroup()
        sender.enter()
        Thread.detachNewThread {
            defer { sender.leave() }
            for (index, host) in hosts.enumerated() {
                let sequence = UInt16(truncatingIfNeeded: index)
                var packet = ICMPEcho.request(identifier: identifier, sequence: sequence)
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_addr.s_addr = host.bigEndian
                sent.record(sequence, host: host)
                _ = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, &packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if index % 32 == 31 { usleep(2_000) }  // Don't flood the router's ARP queue.
            }
        }
        var results: [String: TimeInterval] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 1500)
        while Date() < deadline, results.count < hosts.count {
            var poll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(1, deadline.timeIntervalSinceNow * 1000))
            guard Darwin.poll(&poll, 1, remaining) > 0 else { break }
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(descriptor, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count > 0, let reply = ICMPEcho.reply(Array(buffer.prefix(count))), reply.identifier == identifier,
                  let request = sent.entry(reply.sequence), UInt32(bigEndian: source.sin_addr.s_addr) == request.host else { continue }
            results[IPv4.text(request.host)] = Date().timeIntervalSince(request.at)
        }
        sender.wait()
        return results
    }

    struct BonjourService: Sendable {
        let name: String
        let type: String
        let ip: String
        let model: String?
    }

    /// Browses the common service types and resolves each result to an IPv4 address by opening (and
    /// immediately dropping) a connection to it.
    static func browse(seconds: TimeInterval) async -> (services: [BonjourService], models: [String: String]) {
        let collector = BonjourCollector()
        let queue = DispatchQueue(label: "MacPocket.bonjour")
        var browsers: [NWBrowser] = []
        for type in bonjourTypes {
            let descriptor: NWBrowser.Descriptor = type == "_device-info._tcp"
                ? .bonjourWithTXTRecord(type: type, domain: "local.") : .bonjour(type: type, domain: "local.")
            let browser = NWBrowser(for: descriptor, using: .tcp)
            browser.browseResultsChangedHandler = { results, _ in
                for result in results { collector.resolve(result, type: type, queue: queue) }
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
        try? await Task.sleep(for: .seconds(seconds))
        browsers.forEach { $0.cancel() }
        return (collector.finish(), collector.models())
    }

    static func reverseNames(_ ips: [String]) async -> [String: String] {
        await withTaskGroup(of: (String, String?).self) { group in
            for ip in ips {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async { continuation.resume(returning: (ip, reverseName(ip))) }
                    }
                }
            }
            var names: [String: String] = [:]
            for await (ip, name) in group { if let name { names[ip] = name } }
            return names
        }
    }

    private static func reverseName(_ ip: String) -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard status == 0 else { return nil }
        let name = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name == ip ? nil : name
    }
}

/// Send times of a ping sweep, written by the sending thread and read by the receiving one.
private final class SentLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [UInt16: (host: UInt32, at: Date)] = [:]
    func record(_ sequence: UInt16, host: UInt32) { lock.withLock { entries[sequence] = (host, Date()) } }
    func entry(_ sequence: UInt16) -> (host: UInt32, at: Date)? { lock.withLock { entries[sequence] } }
}

/// Collects resolved Bonjour services from the browser callbacks (which run on one serial queue).
private final class BonjourCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var services: [LANScanner.BonjourService] = []
    private var pending: [NWConnection] = []
    private var seen = Set<String>()
    private var modelsByName: [String: String] = [:]

    func models() -> [String: String] { lock.withLock { modelsByName } }

    func resolve(_ result: NWBrowser.Result, type: String, queue: DispatchQueue) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }
        let key = "\(type)|\(name)"
        guard lock.withLock({ seen.insert(key).inserted }) else { return }
        let model: String? = if case let .bonjour(record) = result.metadata { record["model"] } else { nil }
        // Device info carries a model in its TXT record and has no listening port: match it by instance name.
        if type == "_device-info._tcp" {
            if let model { lock.withLock { modelsByName[name] = model } }
            return
        }
        // The scan keys devices by IPv4 address, so resolve services over IPv4 only.
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: result.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint, case let .ipv4(address) = host {
                    let ip = "\(address)".split(separator: "%").first.map(String.init) ?? "\(address)"
                    self.lock.withLock { self.services.append(.init(name: name, type: type, ip: ip, model: model)) }
                }
                connection.cancel()
            case .failed, .waiting:
                connection.cancel()
            default:
                break
            }
        }
        lock.withLock { pending.append(connection) }
        connection.start(queue: queue)
    }

    func finish() -> [LANScanner.BonjourService] {
        lock.withLock {
            pending.forEach { $0.cancel() }
            pending.removeAll()
            return services
        }
    }
}

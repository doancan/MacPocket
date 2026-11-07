import Foundation

/// An observation in IOService, not a promise that macOS exposes every physical cable.
public struct CableRegistryNode: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case service, usb, thunderbolt, media, network, audio, display }
    public let id: UInt64
    public let parents: Set<UInt64>
    public let name: String
    public let kind: Kind
    public let containerID: String?
    public let builtIn: Bool
    public let bsdName: String?
    public let audioUID: String?
    public let displayIdentity: CableDisplayIdentity?
    public init(id: UInt64, parents: Set<UInt64> = [], name: String, kind: Kind = .service,
                containerID: String? = nil, builtIn: Bool = false, bsdName: String? = nil,
                audioUID: String? = nil, displayIdentity: CableDisplayIdentity? = nil) {
        self.id = id; self.parents = parents; self.name = name; self.kind = kind
        self.containerID = containerID; self.builtIn = builtIn; self.bsdName = bsdName
        self.audioUID = audioUID; self.displayIdentity = displayIdentity
    }
}

public struct CableDisplayIdentity: Hashable, Sendable {
    public let vendor: UInt32
    public let product: UInt32
    public let serial: UInt32
    public init(vendor: UInt32, product: UInt32, serial: UInt32) {
        self.vendor = vendor; self.product = product; self.serial = serial
    }
}

public struct CableConnection: Identifiable, Equatable, Sendable {
    /// Registry IDs expire on reconnect; manual associations must not silently follow a replacement device.
    public var id: String { roots.sorted().map(String.init).joined(separator: ",") }
    public let name: String
    public let roots: Set<UInt64>
    public let isThunderbolt: Bool
    public let groupedByContainer: Bool
    public init(name: String, roots: Set<UInt64>, isThunderbolt: Bool = false, groupedByContainer: Bool = false) {
        self.name = name; self.roots = roots; self.isThunderbolt = isThunderbolt; self.groupedByContainer = groupedByContainer
    }
}

public struct CableEndpoint: Identifiable, Equatable, Sendable {
    public enum Kind: CaseIterable, Sendable {
        case storage, network, display, audio, usb
        public var localizedTitle: String {
            switch self {
            case .storage: String(localized: "Disk")
            case .network: String(localized: "Ağ")
            case .display: String(localized: "Ekran")
            case .audio: String(localized: "Ses")
            case .usb: String(localized: "USB / Thunderbolt")
            }
        }
        public var symbol: String {
            switch self {
            case .storage: "externaldrive"
            case .network: "network"
            case .display: "display"
            case .audio: "speaker.wave.2"
            case .usb: "cable.connector"
            }
        }
    }
    public let id: String
    public let name: String
    public let kind: Kind
    public let registryIDs: Set<UInt64>
    public let detail: String
    public let active: Bool
    public let isDefault: Bool
    public let interfaceName: String?
    public let addresses: Set<String>
    public init(id: String, name: String, kind: Kind, registryIDs: Set<UInt64> = [], detail: String = "",
                active: Bool = false, isDefault: Bool = false, interfaceName: String? = nil, addresses: Set<String> = []) {
        self.id = id; self.name = name; self.kind = kind; self.registryIDs = registryIDs; self.detail = detail
        self.active = active; self.isDefault = isDefault; self.interfaceName = interfaceName; self.addresses = addresses
    }
}

public struct CableInventory: Sendable {
    public let capturedAt: Date
    public let nodes: [CableRegistryNode]
    public let connections: [CableConnection]
    public let endpoints: [CableEndpoint]
    public let drives: [String: EjectDrive]
    public let issues: [String]
    public let networkAddressInterfaces: [String: Set<String>]
    public init(capturedAt: Date = .now, nodes: [CableRegistryNode], connections: [CableConnection],
                endpoints: [CableEndpoint], drives: [String: EjectDrive] = [:], issues: [String] = [],
                networkAddressInterfaces: [String: Set<String>] = [:]) {
        self.capturedAt = capturedAt; self.nodes = nodes; self.connections = connections
        self.endpoints = endpoints; self.drives = drives; self.issues = issues
        self.networkAddressInterfaces = networkAddressInterfaces
    }
}

public struct CableAffectedEndpoint: Identifiable, Equatable, Sendable {
    public enum Evidence: Sendable {
        case registry, manual
        public var localizedTitle: String {
            switch self {
            case .registry: String(localized: "Donanım ağacında bağlı")
            case .manual: String(localized: "Senin eşleştirmen")
            }
        }
    }
    public var id: String { endpoint.id }
    public let endpoint: CableEndpoint
    public let evidence: Evidence
}

public enum CableTopology {
    public static func connections(in nodes: [CableRegistryNode]) -> [CableConnection] {
        let candidates = nodes.filter { !$0.builtIn && ($0.kind == .usb || $0.kind == .thunderbolt) }
        // A device-provided USB ContainerID joins its USB 2 and USB 3 functions. Names and location prefixes do not.
        let grouped = Dictionary(grouping: candidates) { node in
            if node.kind == .usb, let text = node.containerID, let uuid = UUID(uuidString: text),
               uuid != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) {
                return "container:" + uuid.uuidString
            }
            return "entry:" + String(node.id)
        }
        return grouped.values.map { entries in
            let ordered = entries.sorted { $0.id < $1.id }
            return CableConnection(name: ordered.map(\.name).joined(separator: " + "), roots: Set(entries.map(\.id)),
                                   isThunderbolt: entries.contains { $0.kind == .thunderbolt }, groupedByContainer: entries.count > 1)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.id < $1.id) }
    }

    public static func descendants(of roots: Set<UInt64>, in nodes: [CableRegistryNode]) -> Set<UInt64> {
        var children: [UInt64: [UInt64]] = [:]
        for node in nodes { for parent in node.parents { children[parent, default: []].append(node.id) } }
        var seen = roots, queue = Array(roots), index = 0
        while index < queue.count {
            let parent = queue[index]; index += 1
            for child in children[parent] ?? [] where seen.insert(child).inserted { queue.append(child) }
        }
        return seen
    }

    public static func affected(connection: CableConnection, inventory: CableInventory,
                                additionalConnections: Set<String> = [], manualEndpoints: Set<String> = []) -> [CableAffectedEndpoint] {
        let direct = descendants(of: connection.roots, in: inventory.nodes)
        let extraRoots = inventory.connections.filter { additionalConnections.contains($0.id) }.reduce(into: Set<UInt64>()) { $0.formUnion($1.roots) }
        let declared = descendants(of: extraRoots, in: inventory.nodes)
        return inventory.endpoints.compactMap { endpoint in
            // The selected functions themselves appear in the heading, rather than duplicating the cable as an effect.
            if endpoint.kind == .usb, !endpoint.registryIDs.isDisjoint(with: connection.roots) { return nil }
            if !endpoint.registryIDs.isDisjoint(with: direct) { return .init(endpoint: endpoint, evidence: .registry) }
            if manualEndpoints.contains(endpoint.id) || !endpoint.registryIDs.isDisjoint(with: declared) {
                return .init(endpoint: endpoint, evidence: .manual)
            }
            return nil
        }.sorted { lhs, rhs in
            let order = CableEndpoint.Kind.allCases
            if lhs.endpoint.kind != rhs.endpoint.kind {
                return order.firstIndex(of: lhs.endpoint.kind)! < order.firstIndex(of: rhs.endpoint.kind)!
            }
            return lhs.endpoint.name.localizedStandardCompare(rhs.endpoint.name) == .orderedAscending
        }
    }
}

public struct CableNetworkSession: Identifiable, Equatable, Sendable {
    public var id: String { "\(pid):\(local):\(remote)" }
    public let pid: Int32
    public let command: String
    public let local: String
    public let remote: String
    public let localAddress: String
    public var isSSH: Bool { command == "ssh" || command == "sshd" }
}

public struct CableImpactReport: Sendable {
    public let connectionID: String
    public let capturedAt: Date
    public let affected: [CableAffectedEndpoint]
    public let diskUsers: [String: [DiskUser]]
    public let sessions: [String: [CableNetworkSession]]
    public let issues: [String]
    public var needsAttention: Bool {
        !diskUsers.values.flatMap { $0 }.isEmpty || affected.contains { $0.endpoint.active || $0.endpoint.isDefault }
    }
}

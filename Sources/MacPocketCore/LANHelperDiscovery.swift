import Darwin
import Foundation

/// Validated again inside the root helper, independently of the application's input checks.
public struct LANHelperScanRequest: Sendable {
    public let subnet: LANSubnet
    public let interface: String

    public init(cidr: String, interface: String) throws {
        guard let subnet = LANSubnet.parse(cidr: cidr), !interface.isEmpty, interface.utf8.count <= 15,
              interface.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw LANHelperError.invalidRequest
        }
        self.subnet = subnet
        self.interface = interface
    }

    public func run() async throws -> [String: String] {
        guard geteuid() == 0 else { throw LANHelperError.notPrivileged }
        let attached = await LANScanner.availableNetworks()
        guard attached.contains(where: { $0.interface == interface }) else { throw LANHelperError.invalidRequest }
        let hosts = subnet.hosts.map(IPv4.text)
        guard let command = LANOnLinkProbe.command(subnet: subnet, interface: interface, hosts: hosts) else {
            throw LANHelperError.invalidRequest
        }
        let result = try await BoundedProcess.run("/bin/sh", ["-c", command], timeout: 120)
        guard result.status == 0 else { throw LANHelperError.scanFailed }
        let entries = LANOnLinkProbe.entries(in: result.output, subnet: subnet, interface: interface, hosts: hosts)
        return Dictionary(entries.map { ($0.ip, $0.mac) }, uniquingKeysWith: { first, _ in first })
    }
}

public enum LANHelperError: Error, LocalizedError, Equatable {
    case invalidRequest, notPrivileged, scanFailed
    public var errorDescription: String? {
        switch self {
        case .invalidRequest: String(localized: "MAC taraması için ağ aralığı veya arayüz geçersiz.")
        case .notPrivileged: String(localized: "MAC taraması yardımcı servisin yönetici yetkisiyle çalışmasını gerektirir.")
        case .scanFailed: String(localized: "Yardımcı servis doğrudan MAC taramasını tamamlayamadı.")
        }
    }
}

public enum LANHelperDiscovery {
    public typealias Discover = @Sendable (LANNetworkInfo) async throws -> [String: String]

    /// Every ordinary scan completes routed ranges through the helper, including hosts silent to routed ICMP.
    public static func complete(_ results: [LANScanResult], discover: Discover) async throws -> [LANScanResult] {
        var completed: [LANScanResult] = []
        for result in results {
            guard !result.network.isLocal else { completed.append(result); continue }
            let addresses = try await discover(result.network)
            let entries = addresses.map { ARPEntry(ip: $0.key, mac: $0.value, interface: result.network.viaInterface) }
            completed.append(result.mergingARP(entries))
        }
        return completed
    }
}

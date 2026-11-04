import CFNetwork
import CoreWLAN
import Foundation
import Network

/// Link and internet state for the network module. Everything except the ping is read locally; the ping sends one
/// ICMP echo to a public resolver and runs only while the user shows latency in the menu bar.
public struct ConnectivitySnapshot: Codable, Sendable, Equatable {
    public enum Link: String, Codable, Sendable { case wifi, ethernet, other, none }

    /// Whether macOS has a usable path to the internet; nil before the first path update.
    public var online: Bool?
    public var link: Link
    /// A VPN or tunnel interface carries traffic (Tailscale, WireGuard, IPsec, corporate VPNs).
    public var vpnActive: Bool
    /// Signal of the connected Wi-Fi network in dBm; nil when not on Wi-Fi.
    public var wifiRSSI: Int?
    /// Round trip of the last ping, nil when it hasn't run or failed.
    public var pingMilliseconds: Double?
    /// The last ping got no reply.
    public var pingFailed: Bool

    public init(online: Bool? = nil, link: Link = .none, vpnActive: Bool = false, wifiRSSI: Int? = nil,
                pingMilliseconds: Double? = nil, pingFailed: Bool = false) {
        self.online = online; self.link = link; self.vpnActive = vpnActive; self.wifiRSSI = wifiRSSI
        self.pingMilliseconds = pingMilliseconds; self.pingFailed = pingFailed
    }
}

public enum PingParser {
    /// "64 bytes from 1.1.1.1: icmp_seq=0 ttl=56 time=15.650 ms" → 15.65
    public static func milliseconds(_ output: String) -> Double? {
        guard let range = output.range(of: #"time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms"#, options: .regularExpression) else { return nil }
        let match = output[range]
        let digits = match.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

public enum VPNDetector {
    /// Interface names of tunnels. `utun` alone is not enough: macOS keeps idle utun interfaces for iCloud and
    /// Continuity, so only interfaces that carry a network service (listed by the proxy settings) count.
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tap", "tun", "wg"]

    public static func isActive(scopedInterfaces: [String]) -> Bool {
        scopedInterfaces.contains { name in tunnelPrefixes.contains { name.hasPrefix($0) } }
    }

    static func scopedInterfaces() -> [String] {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any] else { return [] }
        return Array(scoped.keys)
    }
}

/// Keeps the latest connectivity state. Path changes arrive from `NWPathMonitor`; the ping runs in the background
/// at most every `pingInterval` and only while enabled, so `sample` never blocks.
final class ConnectivityMonitor: @unchecked Sendable {
    static let pingHost = "1.1.1.1"
    private let pingInterval: TimeInterval = 10
    private let lock = NSLock()
    private let pathMonitor = NWPathMonitor()
    private var path: (online: Bool, link: ConnectivitySnapshot.Link)?
    private var ping: (milliseconds: Double?, failed: Bool, at: Date)?
    private var pinging = false

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let link: ConnectivitySnapshot.Link = path.status != .satisfied ? .none
                : path.usesInterfaceType(.wifi) ? .wifi : path.usesInterfaceType(.wiredEthernet) ? .ethernet : .other
            self?.lock.withLock { self?.path = (path.status == .satisfied, link) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "MacPocket.connectivity", qos: .utility))
    }

    deinit { pathMonitor.cancel() }

    func sample(pingEnabled: Bool) -> ConnectivitySnapshot {
        let (path, ping, startPing) = lock.withLock { () -> ((online: Bool, link: ConnectivitySnapshot.Link)?, (milliseconds: Double?, failed: Bool, at: Date)?, Bool) in
            let due = pingEnabled && !pinging && (self.ping.map { Date().timeIntervalSince($0.at) >= pingInterval } ?? true)
            if due { pinging = true }
            if !pingEnabled { self.ping = nil }
            return (self.path, self.ping, due)
        }
        if startPing { runPing() }
        let link = path?.link ?? .none
        var rssi: Int?
        if link == .wifi, let value = CWWiFiClient.shared().interface()?.rssiValue(), value != 0 { rssi = value }
        return ConnectivitySnapshot(online: path?.online, link: link,
                                    vpnActive: VPNDetector.isActive(scopedInterfaces: VPNDetector.scopedInterfaces()),
                                    wifiRSSI: rssi, pingMilliseconds: ping?.milliseconds, pingFailed: ping?.failed ?? false)
    }

    private func runPing() {
        Task.detached(priority: .utility) { [weak self] in
            let result = try? await BoundedProcess.run("/sbin/ping", ["-c", "1", "-t", "2", "-q", Self.pingHost], timeout: 4)
            let milliseconds = result.flatMap { $0.status == 0 ? Self.roundTrip($0.output) : nil }
            self?.lock.withLock {
                self?.ping = (milliseconds, milliseconds == nil, Date())
                self?.pinging = false
            }
        }
    }

    /// `-q` prints only the summary: "round-trip min/avg/max/stddev = 15.650/15.650/15.650/0.000 ms".
    static func roundTrip(_ output: String) -> Double? {
        if let line = output.split(separator: "\n").first(where: { $0.contains("round-trip") || $0.contains("rtt") }),
           let values = line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces).split(separator: "/"),
           values.count >= 2, let average = Double(values[1]) { return average }
        return PingParser.milliseconds(output)
    }
}

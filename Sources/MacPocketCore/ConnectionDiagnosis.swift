import Darwin
import Foundation

/// One measured hop: round trip and packet loss. Unreachable when nothing came back.
public struct ConnectionProbe: Sendable, Equatable {
    /// Average round trip; nil when no reply arrived.
    public var milliseconds: Double?
    /// 0…1.
    public var loss: Double

    public var reachable: Bool { milliseconds != nil }

    public init(milliseconds: Double?, loss: Double) {
        self.milliseconds = milliseconds
        self.loss = min(1, max(0, loss))
    }

    public static let unreachable = ConnectionProbe(milliseconds: nil, loss: 1)

    /// Reads `ping -q` statistics: "3 packets transmitted, 2 packets received, 33.3% packet loss" and
    /// "round-trip min/avg/max/stddev = 14.1/15.6/17.1/1.5 ms".
    public static func parsePing(_ output: String) -> ConnectionProbe {
        var loss = 1.0
        if let range = output.range(of: #"([0-9]+(?:\.[0-9]+)?)% packet loss"#, options: .regularExpression) {
            let percent = output[range].prefix { $0.isNumber || $0 == "." }
            loss = (Double(percent) ?? 100) / 100
        }
        let values: [Double] = output.split(separator: "\n")
            .first { $0.contains("round-trip") || $0.contains("rtt") }
            .flatMap { $0.split(separator: "=").last?.trimmingCharacters(in: .whitespaces).split(separator: "/") }
            .map { $0.prefix(3).compactMap { Double($0.trimmingCharacters(in: .letters.union(.whitespaces))) } } ?? []
        guard values.count == 3, loss < 1 else { return .unreachable }
        let (minimum, average, maximum) = (values[0], values[1], values[2])
        // ping prints min/avg/max, not the median. With exactly three replies the median is what remains of
        // the sum after the extremes, which keeps one delayed echo from turning a fast link "slow".
        let received = output.range(of: #"([0-9]+) packets received"#, options: .regularExpression)
            .flatMap { Int(output[$0].prefix { $0.isNumber }) }
        let typical = received == 3 ? max(minimum, min(maximum, 3 * average - minimum - maximum)) : average
        return ConnectionProbe(milliseconds: typical, loss: loss)
    }
}

/// Everything the diagnosis looks at, measured in one pass.
public struct ConnectionMeasurement: Sendable, Equatable {
    /// macOS has an active network interface (Wi-Fi joined or a cable with a link).
    public var hasLink: Bool
    public var gateway: String?
    /// The router; nil when no default gateway is known.
    public var router: ConnectionProbe?
    /// A public resolver by IP address, so name resolution plays no part.
    public var internet: ConnectionProbe
    /// The system resolver answering a lookup.
    public var dns: ConnectionProbe
    public var wifiRSSI: Int?

    public init(hasLink: Bool, gateway: String?, router: ConnectionProbe?, internet: ConnectionProbe,
                dns: ConnectionProbe, wifiRSSI: Int?) {
        self.hasLink = hasLink
        self.gateway = gateway
        self.router = router
        self.internet = internet
        self.dns = dns
        self.wifiRSSI = wifiRSSI
    }
}

/// Where the problem is, from the user's point of view.
public enum ConnectionVerdict: String, Sendable, CaseIterable {
    case healthy, noLink, routerUnreachable, noInternet, dnsFailing, weakWiFi, slow
}

public enum ConnectionDiagnosis {
    /// A Wi-Fi signal at or below this is weak enough to explain a slow or lossy first hop.
    static let weakSignal = -75
    static let slowRouterMilliseconds = 30.0
    static let slowInternetMilliseconds = 150.0
    static let slowDNSMilliseconds = 500.0
    static let lossyThreshold = 0.25

    /// Walks the path outwards (link → router → internet → names) and stops at the first broken hop, so the
    /// verdict names the place to fix rather than every symptom downstream of it.
    public static func verdict(_ measurement: ConnectionMeasurement) -> ConnectionVerdict {
        guard measurement.hasLink else { return .noLink }
        let internetUp = measurement.internet.reachable
        let namesUp = measurement.dns.reachable
        if !internetUp && !namesUp {
            // Many routers ignore ping, so the router is blamed only when nothing beyond it answers either.
            if let router = measurement.router, !router.reachable { return .routerUnreachable }
            return .noInternet
        }
        // A network that blocks ICMP still resolves names; that is not an outage.
        if internetUp && !namesUp { return .dnsFailing }
        if let rssi = measurement.wifiRSSI, rssi <= weakSignal, let router = measurement.router,
           (router.milliseconds ?? .infinity) > slowRouterMilliseconds || router.loss >= lossyThreshold || !router.reachable {
            return .weakWiFi
        }
        let slowInternet = internetUp
            && ((measurement.internet.milliseconds ?? 0) > slowInternetMilliseconds || measurement.internet.loss >= lossyThreshold)
        if slowInternet || (measurement.dns.milliseconds ?? 0) > slowDNSMilliseconds {
            return .slow
        }
        return .healthy
    }
}

/// Runs the measurements. Router and internet pings run side by side; the whole pass takes about three
/// seconds.
public enum ConnectionDiagnostics {
    public static let internetHost = "1.1.1.1"

    public static func measure(hasLink: Bool, wifiRSSI: Int?) async -> ConnectionMeasurement {
        guard hasLink else {
            return ConnectionMeasurement(hasLink: false, gateway: nil, router: nil, internet: .unreachable, dns: .unreachable,
                                         wifiRSSI: wifiRSSI)
        }
        let gateway = await LANScanner.currentNetwork()?.gateway
        async let router = routerProbe(gateway)
        async let internet = ping(internetHost)
        async let dns = resolveTwice()
        return await ConnectionMeasurement(hasLink: true, gateway: gateway, router: router, internet: internet, dns: dns,
                                           wifiRSSI: wifiRSSI)
    }

    /// The first lookup can include waking the resolver; the faster of two is the resolver's real speed.
    private static func resolveTwice() async -> ConnectionProbe {
        let first = await resolve()
        guard first.reachable else { return first }
        let second = await resolve()
        return (second.milliseconds ?? .infinity) < (first.milliseconds ?? .infinity) ? second : first
    }

    private static func routerProbe(_ gateway: String?) async -> ConnectionProbe? {
        guard let gateway else { return nil }
        return await ping(gateway)
    }

    private static func ping(_ host: String) async -> ConnectionProbe {
        // Three echoes, one second apart (shorter intervals need root); `-t` caps the whole run.
        guard let result = try? await BoundedProcess.run("/sbin/ping", ["-c", "3", "-t", "5", "-q", host], timeout: 7) else {
            return .unreachable
        }
        return ConnectionProbe.parsePing(result.output)
    }

    /// Times one lookup of a name that cannot exist. Any answer, "no such name" included, proves the resolver
    /// is reachable, and a never-seen name cannot come from a cache, so the time is a real round trip.
    static func resolve(timeout: TimeInterval = 4) async -> ConnectionProbe {
        let name = "macpocket-\(UInt32.random(in: .min ... .max)).invalid-check.apple.com"
        let start = ContinuousClock.now
        // getaddrinfo cannot be cancelled, so the lookup and the deadline race and whichever finishes first
        // answers.
        let answered = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(name, nil, &hints, &result)
                if let result { freeaddrinfo(result) }
                once.resume(status == 0 || status == EAI_NONAME)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { once.resume(false) }
        }
        guard answered else { return .unreachable }
        let elapsed = ContinuousClock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return ConnectionProbe(milliseconds: milliseconds, loss: 0)
    }
}

/// Resumes a continuation exactly once, from whichever of several racing callbacks gets there first.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }

    func resume(_ value: Value) {
        let pending = lock.withLock { () -> CheckedContinuation<Value, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}

// MARK: - Outages

public struct ConnectionOutage: Codable, Sendable, Equatable, Identifiable {
    public var start: Date
    public var end: Date
    public var id: Date { start }
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

/// Turns a stream of online/offline readings into outages. Pure, so the rules (baseline, flap filter, cap)
/// are tested without a network; the app feeds it from `NWPathMonitor` and persists it.
public struct ConnectionOutageLog: Codable, Sendable, Equatable {
    public enum Change: Equatable, Sendable {
        case wentOffline
        case cameBack(duration: TimeInterval)
    }

    /// Shorter drops (Wi-Fi roaming between access points, a sleep/wake handover) are not kept as outages.
    public static let minimumDuration: TimeInterval = 5
    public static let limit = 50

    /// Newest first.
    public private(set) var outages: [ConnectionOutage] = []
    public private(set) var ongoingSince: Date?
    private var online: Bool?

    public init() {}

    /// Returns what changed, or nil when the reading repeats the known state.
    public mutating func update(online isOnline: Bool, at date: Date) -> Change? {
        defer { online = isOnline }
        guard online != isOnline else { return nil }
        if !isOnline {
            ongoingSince = date
            return .wentOffline
        }
        // The first reading is only the baseline.
        guard let start = ongoingSince else { return nil }
        ongoingSince = nil
        let outage = ConnectionOutage(start: start, end: max(start, date))
        if outage.duration >= Self.minimumDuration {
            outages.insert(outage, at: 0)
            if outages.count > Self.limit { outages.removeLast(outages.count - Self.limit) }
        }
        return .cameBack(duration: outage.duration)
    }

    public mutating func clear() { outages = [] }
}

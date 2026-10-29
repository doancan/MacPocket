import Foundation
import Darwin
import IOKit
import SystemConfiguration

/// Network throughput computed from interface byte counters. No network calls are made:
/// only local `getifaddrs` counters and the System Configuration primary-interface key are read.
public struct NetworkSnapshot: Codable, Sendable, Equatable {
    /// Download rate over the last sampling interval; nil until two samples exist.
    public let receivedBytesPerSecond: Double?
    /// Upload rate over the last sampling interval; nil until two samples exist.
    public let sentBytesPerSecond: Double?
    /// BSD name of the interface carrying the default route (e.g. "en0").
    public let primaryInterface: String?
    /// IPv4 address of the primary interface (local network address only).
    public let localIPv4: String?
    /// Cumulative bytes since this monitor started (wrap- and reset-safe).
    public let totalReceivedBytes: UInt64
    public let totalSentBytes: UInt64

    public init(receivedBytesPerSecond: Double?, sentBytesPerSecond: Double?, primaryInterface: String?,
                localIPv4: String?, totalReceivedBytes: UInt64 = 0, totalSentBytes: UInt64 = 0) {
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
        self.primaryInterface = primaryInterface
        self.localIPv4 = localIPv4
        self.totalReceivedBytes = totalReceivedBytes
        self.totalSentBytes = totalSentBytes
    }

    public var combinedBytesPerSecond: Double? {
        guard let received = receivedBytesPerSecond, let sent = sentBytesPerSecond else { return nil }
        return received + sent
    }
}

/// Cumulative counters for one interface at one moment.
public struct InterfaceCounters: Equatable, Sendable {
    public let name: String
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(name: String, receivedBytes: UInt64, sentBytes: UInt64) {
        self.name = name; self.receivedBytes = receivedBytes; self.sentBytes = sentBytes
    }
}

/// Pure delta arithmetic, kept separate from the system reads so it can be unit tested.
public enum CounterDelta {
    /// Bytes transferred between two readings of a cumulative counter that is `bitWidth` bits wide.
    ///
    /// - A counter that decreased from near the top of its range to near the bottom is treated as one
    ///   wrap-around (`if_data` byte counters are 32-bit and wrap after 4 GiB).
    /// - Any other decrease means the interface was reset (detached, re-attached, driver reload):
    ///   the interval contributes 0 rather than a bogus spike.
    public static func bytes(previous: UInt64, current: UInt64, bitWidth: Int = 64) -> UInt64 {
        if current >= previous { return current - previous }
        guard bitWidth < 64 else { return 0 }
        let range = UInt64(1) << UInt64(bitWidth)
        let wrapped = (range - previous) + current
        // A genuine wrap means the counter travelled less than half its range in one interval.
        return wrapped < range / 2 ? wrapped : 0
    }

    /// Received/sent byte rates between two counter sets. Interfaces that appear in only one set are
    /// ignored (newly attached or removed), so attaching an adapter never produces a spike.
    public static func rates(previous: [InterfaceCounters], current: [InterfaceCounters], interval: TimeInterval,
                             bitWidth: Int = 32) -> (received: Double, sent: Double, receivedBytes: UInt64, sentBytes: UInt64)? {
        guard interval > 0 else { return nil }
        let old = Dictionary(previous.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for counters in current {
            guard let before = old[counters.name] else { continue }
            received &+= bytes(previous: before.receivedBytes, current: counters.receivedBytes, bitWidth: bitWidth)
            sent &+= bytes(previous: before.sentBytes, current: counters.sentBytes, bitWidth: bitWidth)
        }
        return (Double(received) / interval, Double(sent) / interval, received, sent)
    }

    /// Interfaces counted toward throughput: physical Ethernet/Wi-Fi (`en*`) and cellular (`pdp_ip*`).
    /// Tunnels, bridges and peer-to-peer links are skipped because they re-carry `en*` traffic.
    public static func countsTowardThroughput(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }
}

/// Samples interface counters on each call. Not thread-safe by itself; owned by `SystemMonitor`.
struct NetworkSampler {
    private var previous: [InterfaceCounters]?
    private var previousAt: Date?
    private var totalReceived: UInt64 = 0
    private var totalSent: UInt64 = 0
    private var primaryCache: (name: String?, measuredAt: Date)?
    private static let primaryRefreshInterval: TimeInterval = 10

    mutating func sample(now: Date = Date()) -> NetworkSnapshot {
        let reading = Self.readInterfaces()
        let counters = reading.counters.filter { CounterDelta.countsTowardThroughput($0.name) }
        var receivedRate: Double?
        var sentRate: Double?
        if let previous, let previousAt,
           let rates = CounterDelta.rates(previous: previous, current: counters, interval: now.timeIntervalSince(previousAt)) {
            receivedRate = rates.received
            sentRate = rates.sent
            totalReceived &+= rates.receivedBytes
            totalSent &+= rates.sentBytes
        }
        previous = counters
        previousAt = now
        if primaryCache == nil || now.timeIntervalSince(primaryCache!.measuredAt) >= Self.primaryRefreshInterval {
            primaryCache = (Self.primaryInterfaceName(), now)
        }
        let primary = primaryCache?.name ?? counters.max(by: { $0.receivedBytes < $1.receivedBytes })?.name
        return NetworkSnapshot(receivedBytesPerSecond: receivedRate, sentBytesPerSecond: sentRate,
                               primaryInterface: primary, localIPv4: primary.flatMap { reading.ipv4[$0] },
                               totalReceivedBytes: totalReceived, totalSentBytes: totalSent)
    }

    /// One `getifaddrs` pass: AF_LINK entries carry `if_data` counters, AF_INET entries the addresses.
    static func readInterfaces() -> (counters: [InterfaceCounters], ipv4: [String: String]) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return ([], [:]) }
        defer { freeifaddrs(head) }
        var counters: [InterfaceCounters] = []
        var ipv4: [String: String] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                counters.append(InterfaceCounters(name: name, receivedBytes: UInt64(data.pointee.ifi_ibytes),
                                                  sentBytes: UInt64(data.pointee.ifi_obytes)))
            case AF_INET where ipv4[name] == nil:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    ipv4[name] = String(decoding: host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
            default: break
            }
        }
        return (counters, ipv4)
    }

    /// Reads the default-route interface from the local System Configuration store (no network I/O).
    static func primaryInterfaceName() -> String? {
        let key = "State:/Network/Global/IPv4" as CFString
        guard let value = SCDynamicStoreCopyValue(nil, key) as? [String: Any] else { return nil }
        return value["PrimaryInterface"] as? String
    }
}

/// Aggregate disk throughput from IOKit block storage driver statistics.
public struct DiskIOSnapshot: Codable, Sendable, Equatable {
    public let readBytesPerSecond: Double?
    public let writeBytesPerSecond: Double?

    public init(readBytesPerSecond: Double?, writeBytesPerSecond: Double?) {
        self.readBytesPerSecond = readBytesPerSecond; self.writeBytesPerSecond = writeBytesPerSecond
    }
}

struct DiskIOSampler {
    private var previous: [InterfaceCounters]?
    private var previousAt: Date?

    mutating func sample(now: Date = Date()) -> DiskIOSnapshot {
        let current = Self.readDrivers()
        defer { previous = current; previousAt = now }
        guard let previous, let previousAt,
              let rates = CounterDelta.rates(previous: previous, current: current,
                                             interval: now.timeIntervalSince(previousAt), bitWidth: 64) else {
            return DiskIOSnapshot(readBytesPerSecond: nil, writeBytesPerSecond: nil)
        }
        return DiskIOSnapshot(readBytesPerSecond: rates.received, writeBytesPerSecond: rates.sent)
    }

    /// Each IOBlockStorageDriver publishes cumulative "Bytes (Read)" / "Bytes (Write)" counters.
    /// Reusing `InterfaceCounters`: received = read, sent = written, keyed by registry entry ID.
    static func readDrivers() -> [InterfaceCounters] {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [InterfaceCounters] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            guard let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { continue }
            let read = (property["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let written = (property["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            result.append(InterfaceCounters(name: String(entryID), receivedBytes: read, sentBytes: written))
        }
        return result
    }
}

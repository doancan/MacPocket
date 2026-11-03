import Foundation

public enum WiFiBand: Int, Sendable, CaseIterable, Comparable {
    case ghz2_4 = 1, ghz5, ghz6

    public var title: String {
        switch self {
        case .ghz2_4: String(localized: "2,4 GHz")
        case .ghz5: String(localized: "5 GHz")
        case .ghz6: String(localized: "6 GHz")
        }
    }

    public static func < (lhs: WiFiBand, rhs: WiFiBand) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A nearby network as a scan sees it. The name and BSSID need Location access, so they may be missing.
public struct WiFiNetworkObservation: Equatable, Sendable {
    public let ssid: String?
    public let bssid: String?
    public let rssi: Int
    public let channel: Int
    public let band: WiFiBand
    public let widthMHz: Int

    public init(ssid: String?, bssid: String?, rssi: Int, channel: Int, band: WiFiBand, widthMHz: Int) {
        self.ssid = ssid; self.bssid = bssid; self.rssi = rssi; self.channel = channel; self.band = band; self.widthMHz = widthMHz
    }
}

public enum WiFiSignalQuality: Int, Sendable, Comparable {
    case weak, fair, good, excellent

    public init(rssi: Int) {
        self = switch rssi {
        case (-55)...: .excellent
        case -65 ..< -55: .good
        case -75 ..< -65: .fair
        default: .weak
        }
    }

    public var title: String {
        switch self {
        case .excellent: String(localized: "Mükemmel")
        case .good: String(localized: "İyi")
        case .fair: String(localized: "Orta")
        case .weak: String(localized: "Zayıf")
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct WiFiChannelLoad: Identifiable, Equatable, Sendable {
    public let channel: Int
    /// Relative interference: the sum of how loudly each overlapping network is heard.
    public let load: Double
    public let networks: Int
    public var id: Int { channel }
}

public struct WiFiChannelAdvice: Equatable, Sendable {
    public let band: WiFiBand
    public let current: Int
    public let recommended: Int
    /// True when switching is worth it; otherwise the current channel is already among the quietest.
    public let shouldSwitch: Bool
}

public enum WiFiAnalysis {
    /// Channels worth suggesting: non-overlapping 2.4 GHz ones, and 5 GHz ones without radar (DFS) waits.
    public static func candidates(for band: WiFiBand) -> [Int] {
        switch band {
        case .ghz2_4: [1, 6, 11]
        case .ghz5: [36, 40, 44, 48, 149, 153, 157, 161]
        case .ghz6: [5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229]
        }
    }

    /// Louder neighbours interfere more; anything below −95 dBm is noise.
    static func weight(_ rssi: Int) -> Double { Double(max(0, rssi + 95)) }

    /// 20 MHz channels a network occupies. 2.4 GHz channels are 5 MHz apart, so a 20 MHz signal spills
    /// into its neighbours; on 5/6 GHz a wide channel covers its whole aligned block.
    static func occupied(_ network: WiFiNetworkObservation) -> [(channel: Int, share: Double)] {
        switch network.band {
        case .ghz2_4:
            let spread = network.widthMHz >= 40 ? 6 : 4
            return (max(1, network.channel - spread)...min(14, network.channel + spread)).map { channel in
                (channel, 1 - Double(abs(channel - network.channel)) / Double(spread + 1))
            }
        case .ghz5, .ghz6:
            let blockChannels = max(1, network.widthMHz / 20)
            guard blockChannels > 1 else { return [(network.channel, 1)] }
            // 5 GHz blocks start at 36 (and 149 for the upper band); 6 GHz blocks start at 1.
            let base = network.band == .ghz6 ? 1 : (network.channel >= 149 ? 149 : 36)
            let size = blockChannels * 4
            let start = base + ((network.channel - base) / size) * size
            return stride(from: start, to: start + size, by: 4).map { ($0, 1) }
        }
    }

    /// One radio broadcasting several SSIDs transmits once: keep only its loudest network. Needs BSSIDs.
    public static func radios(_ networks: [WiFiNetworkObservation]) -> [WiFiNetworkObservation] {
        var kept: [WiFiNetworkObservation] = []
        for network in networks.sorted(by: { $0.rssi > $1.rssi }) {
            let duplicate = network.bssid.map { bssid in
                kept.contains { $0.band == network.band && $0.channel == network.channel
                    && $0.bssid.map { sameRadio($0, bssid) } == true }
            } ?? false
            if !duplicate { kept.append(network) }
        }
        return kept
    }

    public static func channelLoads(_ networks: [WiFiNetworkObservation], band: WiFiBand) -> [WiFiChannelLoad] {
        var load: [Int: Double] = [:], count: [Int: Int] = [:]
        for network in radios(networks) where network.band == band {
            for (channel, share) in occupied(network) {
                load[channel, default: 0] += weight(network.rssi) * share
                if share >= 0.5 { count[channel, default: 0] += 1 }
            }
        }
        return candidates(for: band).map { WiFiChannelLoad(channel: $0, load: load[$0] ?? 0, networks: count[$0] ?? 0) }
    }

    /// The quietest candidate channel. `own` is the joined network, left out so it doesn't count against itself;
    /// without its BSSID (no Location access) the network on our channel heard closest to our RSSI stands in.
    public static func advice(networks: [WiFiNetworkObservation], current: WiFiNetworkObservation) -> WiFiChannelAdvice? {
        let others = excludingOwn(networks, current: current)
        let loads = channelLoads(others, band: current.band)
        guard let best = loads.min(by: { $0.load < $1.load || ($0.load == $1.load && $0.channel < $1.channel) }) else { return nil }
        let currentScore = loadAt(current.channel, others, band: current.band)
        // Switching costs a reconnect; only suggest it when the channel is genuinely busy (about one neighbour at
        // −55 dBm or two at −75) and another is clearly quieter.
        let shouldSwitch = best.channel != current.channel && currentScore >= 40
            && currentScore - best.load >= max(20, currentScore * 0.5)
        return WiFiChannelAdvice(band: current.band, current: current.channel,
                                 recommended: shouldSwitch ? best.channel : current.channel, shouldSwitch: shouldSwitch)
    }

    static func loadAt(_ channel: Int, _ networks: [WiFiNetworkObservation], band: WiFiBand) -> Double {
        radios(networks).filter { $0.band == band }.reduce(0) { sum, network in
            sum + (occupied(network).first { $0.channel == channel }.map { weight(network.rssi) * $0.share } ?? 0)
        }
    }

    /// Drops the joined network, and extra SSIDs the same radio broadcasts (a guest network, say): those share our
    /// airtime rather than compete for it. Only a BSSID proves that; a separate access point on the channel stays in,
    /// however close its signal.
    static func excludingOwn(_ networks: [WiFiNetworkObservation], current: WiFiNetworkObservation) -> [WiFiNetworkObservation] {
        let sameChannel = networks.indices.filter { networks[$0].channel == current.channel && networks[$0].band == current.band }
        if let bssid = current.bssid, sameChannel.contains(where: { networks[$0].bssid == bssid }) {
            let siblings = Set(sameChannel.filter { networks[$0].bssid.map { sameRadio($0, bssid) } ?? false })
            return networks.indices.filter { !siblings.contains($0) }.map { networks[$0] }
        }
        // Without a BSSID (no Location access), the network on our channel heard closest to our RSSI stands in.
        guard let own = sameChannel.min(by: { abs(networks[$0].rssi - current.rssi) < abs(networks[$1].rssi - current.rssi) }),
              abs(networks[own].rssi - current.rssi) <= 8 else { return networks }
        var result = networks
        result.remove(at: own)
        return result
    }

    /// Routers derive each SSID's BSSID from one base MAC: the middle four octets match, the first differs only in
    /// the bits routers set for extra SSIDs (e.g. 16:… vs 1a:…/1e:…, never the multicast bit) and the last by a small offset.
    public static func sameRadio(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        let y = b.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard x.count == 6, y.count == 6 else { return a.lowercased() == b.lowercased() }
        return x[1...4] == y[1...4] && (x[0] ^ y[0]) & 0xC1 == 0 && abs(Int(x[5]) - Int(y[5])) <= 15
    }
}

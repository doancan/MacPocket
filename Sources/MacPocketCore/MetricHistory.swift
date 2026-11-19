import Foundation

/// One averaged moment of the metrics the menu bar charts over long ranges. Values the Mac did not report stay nil.
public struct MetricPoint: Codable, Sendable, Equatable {
    public var date: Date
    /// Total CPU use, 0…100.
    public var cpu: Double?
    /// Used memory, 0…1.
    public var memory: Double?
    /// Bytes per second.
    public var networkDown: Double?
    public var networkUp: Double?
    /// Hottest sensor, °C.
    public var temperature: Double?
    /// Free bytes on the startup disk.
    public var diskFree: Double?
    /// Raw samples averaged into this point.
    public var samples: Int

    public init(date: Date, cpu: Double? = nil, memory: Double? = nil, networkDown: Double? = nil, networkUp: Double? = nil,
                temperature: Double? = nil, diskFree: Double? = nil, samples: Int = 1) {
        self.date = date; self.cpu = cpu; self.memory = memory; self.networkDown = networkDown; self.networkUp = networkUp
        self.temperature = temperature; self.diskFree = diskFree; self.samples = samples
    }

    /// The point a snapshot contributes.
    public init(_ snapshot: SystemSnapshot) {
        let startup = snapshot.startupVolume
        self.init(date: snapshot.capturedAt, cpu: snapshot.cpuTotalPercent,
                  memory: snapshot.usedMemoryBytes.map { Double($0) / Double(max(1, snapshot.physicalMemoryBytes)) },
                  networkDown: snapshot.network?.receivedBytesPerSecond, networkUp: snapshot.network?.sentBytesPerSecond,
                  temperature: snapshot.temperatures.flatMap(TemperatureSummary.hottest)?.celsius,
                  diskFree: startup.map { Double($0.availableBytes) })
    }

    /// The running average of this point and `other`; a value missing on one side keeps the other's.
    func merged(with other: MetricPoint) -> MetricPoint {
        let total = samples + other.samples
        func mean(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case let (a?, b?): (a * Double(samples) + b * Double(other.samples)) / Double(total)
            case let (a?, nil): a
            case let (nil, b?): b
            case (nil, nil): nil
            }
        }
        return MetricPoint(date: date, cpu: mean(cpu, other.cpu), memory: mean(memory, other.memory),
                           networkDown: mean(networkDown, other.networkDown), networkUp: mean(networkUp, other.networkUp),
                           temperature: mean(temperature, other.temperature),
                           // Free space is a level, not a rate: the latest reading is the truth.
                           diskFree: other.diskFree ?? diskFree, samples: total)
    }
}

/// How far back a long-range chart looks, and how coarse its points are.
public enum MetricRange: String, Codable, Sendable, CaseIterable, Identifiable {
    case hour, day, week
    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .hour: 3_600
        case .day: 86_400
        case .week: 604_800
        }
    }

    /// Width of one averaged point: 360, 720 and 672 points per range.
    public var bucket: TimeInterval {
        switch self {
        case .hour: 10
        case .day: 120
        case .week: 900
        }
    }

}

/// Long-range metric history at three resolutions. Every recorded sample is averaged into the current bucket
/// of each range; points older than the range fall off, so the history stays a bounded, fixed size
/// (about 1,750 points in all) however long the Mac runs.
public struct MetricHistory: Codable, Sendable, Equatable {
    private var tiers: [MetricRange: [MetricPoint]] = [:]

    public init() {}

    public func points(_ range: MetricRange) -> [MetricPoint] { tiers[range] ?? [] }

    public mutating func record(_ point: MetricPoint) {
        for range in MetricRange.allCases {
            var points = tiers[range] ?? []
            let bucketStart = Date(timeIntervalSinceReferenceDate:
                (point.date.timeIntervalSinceReferenceDate / range.bucket).rounded(.down) * range.bucket)
            // A sample up to one bucket behind the newest (an NTP correction after wake) joins the newest
            // bucket; only a larger jump back discards the range.
            if let last = points.last, bucketStart <= last.date, last.date.timeIntervalSince(bucketStart) <= range.bucket {
                points[points.count - 1] = last.merged(with: point)
            } else if points.last.map({ $0.date < bucketStart }) ?? true {
                var opened = point
                opened.date = bucketStart
                points.append(opened)
            } else {
                // The clock went back: start over rather than keep a history that runs backwards.
                var opened = point
                opened.date = bucketStart
                points = [opened]
            }
            let oldest = point.date.addingTimeInterval(-range.duration)
            if let firstKept = points.firstIndex(where: { $0.date >= oldest }), firstKept > 0 {
                points.removeFirst(firstKept)
            }
            tiers[range] = points
        }
    }
}

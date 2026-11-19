import Foundation

/// Free space on the startup disk at one moment, the latest reading of a 15-minute bucket.
public struct MetricPoint: Codable, Sendable, Equatable {
    public var date: Date
    /// Free bytes on the startup disk.
    public var diskFree: Double?

    public init(date: Date, diskFree: Double? = nil) {
        self.date = date; self.diskFree = diskFree
    }

    /// The point a snapshot contributes.
    public init(_ snapshot: SystemSnapshot) {
        self.init(date: snapshot.capturedAt, diskFree: snapshot.startupVolume.map { Double($0.availableBytes) })
    }
}

/// A week of startup-disk free space, the trend the disk forecast is drawn from. One point per 15 minutes
/// (672 in all), so it stays a small, fixed size however long the Mac runs.
public struct MetricHistory: Codable, Sendable, Equatable {
    public static let duration: TimeInterval = 7 * 86_400
    public static let bucket: TimeInterval = 900

    public private(set) var points: [MetricPoint] = []

    public init() {}

    public mutating func record(_ point: MetricPoint) {
        guard point.diskFree != nil else { return }
        let bucketStart = Date(timeIntervalSinceReferenceDate:
            (point.date.timeIntervalSinceReferenceDate / Self.bucket).rounded(.down) * Self.bucket)
        var opened = point
        opened.date = bucketStart
        // A sample up to one bucket behind the newest (an NTP correction after wake) updates the newest
        // bucket; only a larger jump back discards the history, which would otherwise run backwards.
        if let last = points.last, bucketStart <= last.date, last.date.timeIntervalSince(bucketStart) <= Self.bucket {
            opened.date = last.date
            points[points.count - 1] = opened
        } else if points.last.map({ $0.date < bucketStart }) ?? true {
            points.append(opened)
        } else {
            points = [opened]
        }
        let oldest = point.date.addingTimeInterval(-Self.duration)
        if let firstKept = points.firstIndex(where: { $0.date >= oldest }), firstKept > 0 {
            points.removeFirst(firstKept)
        }
    }
}

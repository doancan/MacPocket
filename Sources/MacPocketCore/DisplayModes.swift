import Foundation

/// One display mode as CoreGraphics reports it (points, backing pixels, refresh rate).
public struct DisplayModeInfo: Equatable, Hashable, Sendable {
    public let id: Int32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Hz; 0 for displays that don't report one.
    public let refreshRate: Double
    public let usableForDesktop: Bool

    public init(id: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double, usableForDesktop: Bool = true) {
        self.id = id
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.usableForDesktop = usableForDesktop
    }

    /// Rendered at 2× (or more): sharp text.
    public var isHiDPI: Bool { pixelWidth >= width * 2 - 1 }
    public var roundedRefresh: Int { Int(refreshRate.rounded()) }
}

/// A resolution choice (points) with the refresh rates it comes in.
public struct DisplayResolution: Equatable, Hashable, Identifiable, Sendable {
    public let width: Int
    public let height: Int
    public let isHiDPI: Bool
    /// Modes of this resolution, highest refresh first.
    public let modes: [DisplayModeInfo]

    public var id: String { "\(width)x\(height)\(isHiDPI ? "@2x" : "")" }
    public var refreshRates: [Int] { Array(Set(modes.map(\.roundedRefresh))).sorted(by: >) }

    public func mode(refresh: Int?) -> DisplayModeInfo? {
        guard let refresh else { return modes.first }
        return modes.first { $0.roundedRefresh == refresh } ?? modes.first
    }
}

public enum DisplayModeCatalog {
    /// Desktop-usable resolutions, smallest (largest text) first. HiDPI and low-resolution variants of the
    /// same size are separate choices; low-resolution ones are left out unless asked for, or when the display
    /// has no HiDPI modes. Near-duplicates one point apart (1024×682 and 1024×683) collapse into the one with
    /// more pixels.
    public static func resolutions(_ modes: [DisplayModeInfo], includeLowResolution: Bool) -> [DisplayResolution] {
        let usable = modes.filter(\.usableForDesktop)
        let hasHiDPI = usable.contains(where: \.isHiDPI)
        let wanted = usable.filter { $0.isHiDPI || includeLowResolution || !hasHiDPI }
        let grouped = Dictionary(grouping: wanted) { "\($0.width)x\($0.height)x\($0.isHiDPI)" }
        var result = grouped.values.compactMap { group -> DisplayResolution? in
            guard let first = group.first else { return nil }
            let sorted = group.sorted { $0.refreshRate != $1.refreshRate ? $0.refreshRate > $1.refreshRate : $0.pixelWidth > $1.pixelWidth }
            return DisplayResolution(width: first.width, height: first.height, isHiDPI: first.isHiDPI, modes: sorted)
        }
        result.sort { ($0.width, $0.height, $0.isHiDPI ? 1 : 0) < ($1.width, $1.height, $1.isHiDPI ? 1 : 0) }
        // Collapse near-duplicates of the same kind (within 1 pt in both directions).
        var collapsed: [DisplayResolution] = []
        for resolution in result {
            if let last = collapsed.last, last.isHiDPI == resolution.isHiDPI,
               abs(last.width - resolution.width) <= 1, abs(last.height - resolution.height) <= 1 {
                if resolution.modes[0].pixelWidth * resolution.modes[0].pixelHeight > last.modes[0].pixelWidth * last.modes[0].pixelHeight {
                    collapsed[collapsed.count - 1] = resolution
                }
                continue
            }
            collapsed.append(resolution)
        }
        return collapsed
    }

    /// The panel's native size: the mode with the most backing pixels that isn't larger than the panel draws.
    public static func nativePixels(_ modes: [DisplayModeInfo]) -> (width: Int, height: Int)? {
        modes.filter { !$0.isHiDPI && $0.usableForDesktop }.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
            .map { ($0.pixelWidth, $0.pixelHeight) }
    }

    /// The HiDPI resolution that looks like the native panel at 2× ("Varsayılan").
    public static func recommended(_ resolutions: [DisplayResolution], native: (width: Int, height: Int)?) -> DisplayResolution? {
        guard let native else { return resolutions.last(where: \.isHiDPI) }
        return resolutions.filter(\.isHiDPI).min {
            abs($0.width * 2 - native.width) + abs($0.height * 2 - native.height) < abs($1.width * 2 - native.width) + abs($1.height * 2 - native.height)
        }
    }
}

/// Moving the main display: CoreGraphics' main display is the one at origin (0, 0), so every origin shifts by
/// the new main display's current origin.
public enum DisplayArrangement {
    public static func originsMakingMain(_ newMain: UInt32, origins: [UInt32: (x: Int32, y: Int32)]) -> [UInt32: (x: Int32, y: Int32)] {
        guard let shift = origins[newMain] else { return origins }
        return origins.mapValues { (x: $0.x - shift.x, y: $0.y - shift.y) }
    }
}

/// "Keep this setting?" countdown after a mode change: reverts unless confirmed in time.
public struct DisplayChangeConfirmation: Equatable, Sendable {
    public static let seconds = 15
    public let deadline: Date

    public init(startedAt: Date = Date()) { deadline = startedAt.addingTimeInterval(TimeInterval(Self.seconds)) }

    public func remaining(at now: Date) -> Int { max(0, Int(deadline.timeIntervalSince(now).rounded(.up))) }
    public func expired(at now: Date) -> Bool { now >= deadline }
}

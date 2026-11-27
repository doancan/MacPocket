import Foundation

public struct CurvePoint: Codable, Equatable, Sendable {
    public var celsius: Double
    public var percent: Double

    public init(celsius: Double, percent: Double) { self.celsius = celsius; self.percent = percent }
}

/// How the user wants a fan driven: by the system, at a fixed share of its range, or by temperature.
public enum FanProfile: Codable, Equatable, Sendable {
    case system
    case fixed(percent: Double)
    case curve([CurvePoint])
}

/// Turns a profile and the current temperature into a target speed. A falling temperature only lowers the
/// speed once it is `hysteresis` degrees below the temperature that set the current speed, so the fans don't
/// hunt up and down around a curve point.
public struct FanCurveState: Sendable {
    public static let hysteresis = 3.0
    private var anchorTemperature: Double?

    public init() {}

    /// Nil means "leave the fan to the system".
    public mutating func targetRPM(profile: FanProfile, temperature: Double, range: ClosedRange<Double>) -> Double? {
        switch profile {
        case .system:
            anchorTemperature = nil
            return nil
        case let .fixed(percent):
            anchorTemperature = nil
            return Self.rpm(percent: percent, range: range)
        case let .curve(points):
            let sorted = points.sorted { $0.celsius < $1.celsius }
            guard !sorted.isEmpty else { anchorTemperature = nil; return nil }
            if let anchor = anchorTemperature, temperature < anchor, anchor - temperature < Self.hysteresis {
                return Self.rpm(percent: Self.percent(sorted, at: anchor), range: range)
            }
            anchorTemperature = temperature
            return Self.rpm(percent: Self.percent(sorted, at: temperature), range: range)
        }
    }

    static func rpm(percent: Double, range: ClosedRange<Double>) -> Double {
        let share = min(max(percent, 0), 100) / 100
        return range.lowerBound + (range.upperBound - range.lowerBound) * share
    }

    static func percent(_ sorted: [CurvePoint], at celsius: Double) -> Double {
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        if celsius <= first.celsius { return first.percent }
        if celsius >= last.celsius { return last.percent }
        for (lower, upper) in zip(sorted, sorted.dropFirst()) where celsius <= upper.celsius {
            let span = upper.celsius - lower.celsius
            guard span > 0 else { return upper.percent }
            return lower.percent + (upper.percent - lower.percent) * (celsius - lower.celsius) / span
        }
        return last.percent
    }
}

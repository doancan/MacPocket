import Foundation

/// A monotone cubic curve for decorative sparklines, without a view/mark per sample.
struct SparklineCurve {
    struct Segment {
        let start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint
    }
    let points: [CGPoint]
    let segments: [Segment]

    init(values: [Double], floor: Double, ceiling: Double?, size: CGSize) {
        let upper = max(floor + 1, ceiling ?? max(1, values.filter(\.isFinite).max() ?? 1))
        let span = upper - floor
        guard floor.isFinite, upper.isFinite, span.isFinite, span > 0,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            points = []
            segments = []
            return
        }
        points = values.enumerated().compactMap { index, value in
            guard value.isFinite else { return nil }
            return CGPoint(x: Double(index) / Double(max(1, values.count - 1)) * size.width,
                           y: (1 - min(1, max(0, (value - floor) / span))) * size.height)
        }
        guard points.count > 1 else { segments = []; return }
        let slopes = zip(points, points.dropFirst()).map { ($1.y - $0.y) / ($1.x - $0.x) }
        var tangents = [slopes[0]]
        for index in 1..<points.count - 1 {
            let before = slopes[index - 1], after = slopes[index]
            // Harmonic-mean tangents keep the Bezier controls within each segment's range.
            tangents.append((before > 0 && after > 0) || (before < 0 && after < 0)
                ? 2 / (1 / before + 1 / after) : 0)
        }
        tangents.append(slopes[slopes.count - 1])
        var result: [Segment] = []
        result.reserveCapacity(points.count - 1)
        for index in 0..<points.count - 1 {
            let a = points[index], b = points[index + 1], third = (b.x - a.x) / 3
            result.append(Segment(start: a, control1: CGPoint(x: a.x + third, y: a.y + tangents[index] * third),
                           control2: CGPoint(x: b.x - third, y: b.y - tangents[index + 1] * third), end: b))
        }
        segments = result
    }
}

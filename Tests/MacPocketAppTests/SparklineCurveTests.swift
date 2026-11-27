import XCTest
@testable import MacPocketApp

final class SparklineCurveTests: XCTestCase {
    private func curve(_ values: [Double], floor: Double = 0, ceiling: Double? = 100) -> SparklineCurve {
        SparklineCurve(values: values, floor: floor, ceiling: ceiling, size: CGSize(width: 240, height: 40))
    }
    func testEndpointsUseCompleteDomainAndWidth() {
        let value = curve([0, 50, 100])
        XCTAssertEqual(value.points, [CGPoint(x: 0, y: 40), CGPoint(x: 120, y: 20), CGPoint(x: 240, y: 0)])
        XCTAssertEqual(value.segments.count, 2)
    }
    func testNegativeRSSIDomainAndAutomaticCeiling() {
        XCTAssertEqual(curve([-100, -60, -20], floor: -100, ceiling: -20).points.map(\.y), [40, 20, 0])
        XCTAssertEqual(curve([0, 20, 40], ceiling: nil).points.map(\.y), [40, 20, 0])
    }
    func testFlatPeaksAndUnevenGapsNeverOvershootSamples() {
        for values in [[0, 20, 21, 95, 100], [100, 40, 39, 1, 0], [0, 100, 0, 100], [50, 50, 50], [0, .nan, 20, 100]] {
            for segment in curve(values).segments {
                let range = min(segment.start.y, segment.end.y)...max(segment.start.y, segment.end.y)
                XCTAssertTrue(range.contains(segment.control1.y))
                XCTAssertTrue(range.contains(segment.control2.y))
                for step in 0...20 {
                    let t = Double(step) / 20, s = 1 - t
                    let y = s*s*s*segment.start.y + 3*s*s*t*segment.control1.y + 3*s*t*t*segment.control2.y + t*t*t*segment.end.y
                    XCTAssertGreaterThanOrEqual(y, range.lowerBound - 0.000001)
                    XCTAssertLessThanOrEqual(y, range.upperBound + 0.000001)
                }
            }
        }
    }
    func testInvalidSamplesKeepTheirOriginalTimePositions() {
        let value = curve([0, .nan, .infinity, 100])
        XCTAssertEqual(value.points, [CGPoint(x: 0, y: 40), CGPoint(x: 240, y: 0)])
        XCTAssertEqual(value.segments.count, 1)
    }
    func testEmptySingleAndOutOfRangeValues() {
        XCTAssertTrue(curve([]).points.isEmpty)
        XCTAssertTrue(curve([30]).segments.isEmpty)
        XCTAssertEqual(curve([-10, 110]).points.map(\.y), [40, 0])
    }
    func testInvalidGeometryProducesNoPath() {
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 40), CGSize(width: 40, height: -CGFloat.infinity)] {
            XCTAssertTrue(SparklineCurve(values: [0, 100], floor: 0, ceiling: 100, size: size).points.isEmpty)
        }
        XCTAssertTrue(curve([1, 2], floor: .nan).points.isEmpty)
    }
}

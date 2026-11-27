import XCTest
@testable import MacPocketCore

final class FanProfileTests: XCTestCase {
    private let range = 1100.0...3500.0

    func testSystemProfileLeavesFansToMacOS() {
        var state = FanCurveState()
        XCTAssertNil(state.targetRPM(profile: .system, temperature: 70, range: range))
    }

    func testFixedPercentMapsOntoTheFanRange() {
        var state = FanCurveState()
        XCTAssertEqual(state.targetRPM(profile: .fixed(percent: 50), temperature: 40, range: range), 2300)
        XCTAssertEqual(state.targetRPM(profile: .fixed(percent: 0), temperature: 40, range: range), 1100)
        XCTAssertEqual(state.targetRPM(profile: .fixed(percent: 250), temperature: 40, range: range), 3500)
    }

    func testCurveInterpolatesAndClampsAtTheEnds() {
        var state = FanCurveState()
        let curve = FanProfile.curve([CurvePoint(celsius: 40, percent: 0), CurvePoint(celsius: 80, percent: 100)])
        XCTAssertEqual(state.targetRPM(profile: curve, temperature: 20, range: range), 1100)
        XCTAssertEqual(state.targetRPM(profile: curve, temperature: 60, range: range), 2300)
        XCTAssertEqual(state.targetRPM(profile: curve, temperature: 95, range: range), 3500)
    }

    func testCurveRisesImmediatelyButFallsOnlyAfterTheHysteresis() {
        var state = FanCurveState()
        let curve = FanProfile.curve([CurvePoint(celsius: 40, percent: 0), CurvePoint(celsius: 80, percent: 100)])
        let high = state.targetRPM(profile: curve, temperature: 70, range: range)
        XCTAssertEqual(state.targetRPM(profile: curve, temperature: 68, range: range), high)
        let lower = state.targetRPM(profile: curve, temperature: 66, range: range)
        XCTAssertLessThan(lower ?? 0, high ?? 0)
    }

    func testEmptyCurveFallsBackToSystem() {
        var state = FanCurveState()
        XCTAssertNil(state.targetRPM(profile: .curve([]), temperature: 70, range: range))
    }
}

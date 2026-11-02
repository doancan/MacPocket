import XCTest
@testable import MacPocketCore

final class FanRequestValidatorTests: XCTestCase {
    private let validator = FanRequestValidator(fans: [1100...3500, 1100...3500])

    func testAcceptsTheRangeBoundaries() {
        XCTAssertNoThrow(try validator.validate(fan: 0, rpm: 1100))
        XCTAssertNoThrow(try validator.validate(fan: 1, rpm: 3500))
    }

    func testRejectsAnUnknownFan() {
        XCTAssertThrowsError(try validator.validate(fan: 2, rpm: 2000)) { XCTAssertEqual($0 as? FanControlError, .noSuchFan) }
        XCTAssertThrowsError(try validator.validate(fan: -1, rpm: 2000))
    }

    func testRejectsOutOfRangeAndNonFiniteSpeeds() {
        for rpm in [0, 1099.9, 3500.1, 99_999, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try validator.validate(fan: 0, rpm: rpm), "\(rpm)")
        }
    }

    func testThermalGuardTripsAt90AndClearsBelow80() {
        var guardrail = ThermalGuard()
        XCTAssertTrue(guardrail.allowsManual(hottestCelsius: 89))
        XCTAssertFalse(guardrail.allowsManual(hottestCelsius: 90))
        XCTAssertFalse(guardrail.allowsManual(hottestCelsius: 85))
        XCTAssertFalse(guardrail.allowsManual(hottestCelsius: 80))
        XCTAssertTrue(guardrail.allowsManual(hottestCelsius: 79))
    }
}

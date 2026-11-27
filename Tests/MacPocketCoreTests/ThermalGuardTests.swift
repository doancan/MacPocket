import XCTest
@testable import MacPocketCore

final class ThermalGuardTests: XCTestCase {
    func testAShortSensorDropoutKeepsManualModeAllowed() {
        var guardrail = ThermalGuard()
        for _ in 0..<(ThermalGuard.unreadableLimit - 1) { XCTAssertTrue(guardrail.allowsManual(reading: nil)) }
        XCTAssertTrue(guardrail.allowsManual(reading: 60))
    }

    func testASensorThatStaysUnreadableTripsTheGuard() {
        var guardrail = ThermalGuard()
        var allowed = true
        for _ in 0..<ThermalGuard.unreadableLimit { allowed = guardrail.allowsManual(reading: nil) }
        XCTAssertFalse(allowed)
    }

    func testAReadingResetsTheDropoutCount() {
        var guardrail = ThermalGuard()
        for _ in 0..<(ThermalGuard.unreadableLimit - 1) { _ = guardrail.allowsManual(reading: nil) }
        XCTAssertTrue(guardrail.allowsManual(reading: 50))
        for _ in 0..<(ThermalGuard.unreadableLimit - 1) { XCTAssertTrue(guardrail.allowsManual(reading: nil)) }
    }

    func testHeatStillTripsAndResumesWithHysteresis() {
        var guardrail = ThermalGuard()
        XCTAssertFalse(guardrail.allowsManual(reading: ThermalGuard.tripCelsius))
        XCTAssertFalse(guardrail.allowsManual(reading: ThermalGuard.resumeCelsius + 1))
        XCTAssertTrue(guardrail.allowsManual(reading: ThermalGuard.resumeCelsius - 1))
    }
}

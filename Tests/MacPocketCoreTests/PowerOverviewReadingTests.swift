import Foundation
import XCTest
@testable import MacPocketCore

final class PowerOverviewReadingTests: XCTestCase {
    private func overview(at seconds: TimeInterval, source: String = "AC Power", lowPower: Bool = false,
                          thermal: String = "nominal", charge: Int? = nil) -> PowerOverview {
        let sources = charge.map { [PowerSourceInfo(description: ["Type": "InternalBattery", "Current Capacity": $0, "Max Capacity": 100])] } ?? []
        return PowerOverview(capturedAt: Date(timeIntervalSinceReferenceDate: seconds), providingSource: source, sources: sources,
                             adapter: nil, battery: nil, lowPowerMode: lowPower, thermalState: thermal)
    }

    func testTimestampAloneIsTheSameReading() {
        XCTAssertTrue(overview(at: 0).hasSameReading(as: overview(at: 2)))
        XCTAssertNotEqual(overview(at: 0), overview(at: 2))
    }

    func testEveryShownFieldBreaksTheMatch() {
        let base = overview(at: 0, charge: 80)
        XCTAssertFalse(base.hasSameReading(as: overview(at: 2, source: "Battery Power", charge: 80)))
        XCTAssertFalse(base.hasSameReading(as: overview(at: 2, lowPower: true, charge: 80)))
        XCTAssertFalse(base.hasSameReading(as: overview(at: 2, thermal: "serious", charge: 80)))
        XCTAssertFalse(base.hasSameReading(as: overview(at: 2, charge: 79)))
    }
}

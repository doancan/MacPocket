import XCTest
@testable import MacPocketCore

final class PowerInspectorAccumulatorTests: XCTestCase {
    private func registry(total: Int, count: Int, instantaneous: Int = 0) -> BatteryRegistryInfo {
        BatteryRegistryInfo(properties: ["PowerTelemetryData": ["SystemPowerIn": instantaneous,
                                                                "AccumulatedSystemPowerIn": total,
                                                                "SystemPowerInAccumulatorCount": count]])
    }

    func testAverageDrawFromAccumulatorDeltaWhenInstantaneousIsZero() {
        let earlier = registry(total: 129_492_637, count: 6_465)
        let later = registry(total: 129_492_637 + 3 * 24_000, count: 6_468)
        XCTAssertNil(later.systemPowerInMilliwatts, "A zero instantaneous reading is treated as missing")
        XCTAssertEqual(later.averageSystemWatts(since: earlier) ?? 0, 24, accuracy: 0.001)
    }

    func testNoAverageWithoutNewSamplesOrAfterReset() {
        let earlier = registry(total: 1_000, count: 10)
        XCTAssertNil(registry(total: 1_000, count: 10).averageSystemWatts(since: earlier))
        XCTAssertNil(registry(total: 500, count: 12).averageSystemWatts(since: earlier), "Counter reset must not yield a negative draw")
    }
}

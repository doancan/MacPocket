import XCTest
@testable import MacPocketCore

final class TemperatureSensorTests: XCTestCase {
    func testClassifiesAppleSiliconSensorNames() {
        XCTAssertEqual(TemperatureGroup.classify("PMU tdie10"), .soc)
        XCTAssertEqual(TemperatureGroup.classify("PMU tdev3"), .pmu)
        XCTAssertEqual(TemperatureGroup.classify("PMU TP1g"), .pmu)
        XCTAssertEqual(TemperatureGroup.classify("NAND CH0 temp"), .storage)
        XCTAssertEqual(TemperatureGroup.classify("gas gauge battery"), .battery)
        XCTAssertEqual(TemperatureGroup.classify("Some Future Sensor"), .other)
        XCTAssertNil(TemperatureGroup.classify("PMU tcal"), "calibration is a constant, not a temperature")
    }

    func testReadingsDropCalibrationAndImplausibleValues() {
        let readings = TemperatureSensor.readings(from: [
            ("PMU tcal", 51.9), ("PMU tdie1", 35.4), ("NAND CH0 temp", 0), ("PMU tdev1", -12), ("PMU tdev2", 400), ("", 30),
        ])
        XCTAssertEqual(readings, [TemperatureReading(name: "PMU tdie1", celsius: 35.4)])
    }

    func testRepeatedNamesAreNumberedAndSortedNaturally() {
        let readings = TemperatureSensor.readings(from: [
            ("PMU tdie10", 36), ("PMU tdie2", 35), ("PMU tdie2", 37), ("PMU tdie1", 34),
        ])
        XCTAssertEqual(readings.map(\.name), ["PMU tdie1", "PMU tdie2", "PMU tdie2 2", "PMU tdie10"])
    }

    func testSummaryGivesMaximumAndAveragePerGroupInGroupOrder() throws {
        let summary = TemperatureSummary.groups([
            TemperatureReading(name: "NAND CH0 temp", celsius: 31),
            TemperatureReading(name: "PMU tdie1", celsius: 40),
            TemperatureReading(name: "PMU tdie2", celsius: 50),
            TemperatureReading(name: "PMU tdev1", celsius: 33),
        ])
        XCTAssertEqual(summary.map(\.group), [.soc, .pmu, .storage])
        let soc = try XCTUnwrap(summary.first)
        XCTAssertEqual(soc.maximum, 50)
        XCTAssertEqual(soc.average, 45)
        XCTAssertEqual(soc.count, 2)
    }

    func testSummaryOfNoReadingsIsEmpty() {
        XCTAssertTrue(TemperatureSummary.groups([]).isEmpty)
    }

    func testLiveSensorReadingsAreUniqueAndPlausibleWhenAvailable() {
        // Apple silicon publishes HID temperature sensors; other Macs may not, which is a valid nil.
        guard let readings = TemperatureSensor().sample() else { return }
        XCTAssertEqual(Set(readings.map(\.name)).count, readings.count)
        XCTAssertTrue(readings.allSatisfy { TemperatureSensor.plausibleRange.contains($0.celsius) })
    }
}

import XCTest
@testable import MacPocketCore

final class SMCValueTests: XCTestCase {
    func testDecodesAppleSiliconLittleEndianFloat() throws {
        // Bytes read from a Mac Studio's F0Ac key.
        let rpm = try XCTUnwrap(SMCValue.decode(type: "flt ", bytes: [171, 170, 166, 68]))
        XCTAssertEqual(rpm, 1333.333, accuracy: 0.001)
    }

    func testDecodesIntelFixedPointFpe2() {
        // 0x1A0A = 6666, two fractional bits → 1666.5 rpm.
        XCTAssertEqual(SMCValue.decode(type: "fpe2", bytes: [0x1A, 0x0A]), 1666.5)
    }

    func testDecodesBigEndianUnsignedIntegers() {
        XCTAssertEqual(SMCValue.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCValue.decode(type: "ui16", bytes: [0x01, 0x00]), 256)
        XCTAssertEqual(SMCValue.decode(type: "ui32", bytes: [0, 0, 0x0D, 0xAC]), 3500)
    }

    func testRejectsUnknownTypesAndWrongLengths() {
        XCTAssertNil(SMCValue.decode(type: "sp78", bytes: [0x20, 0x00]))
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [1, 2]))
        XCTAssertNil(SMCValue.decode(type: "fpe2", bytes: [1]))
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [0, 0, 0xC0, 0x7F]), "NaN is not a speed")
    }

    func testFourCharCodeRoundTrips() {
        XCTAssertEqual(SMCValue.fourCharCode("FNum"), 0x464E_756D)
        XCTAssertEqual(SMCValue.string(SMCValue.fourCharCode("flt ")), "flt ")
    }
}

final class FanSnapshotTests: XCTestCase {
    func testFractionIsShareOfMaximumSpeed() {
        XCTAssertEqual(FanSnapshot(rpm: 1750, minimumRPM: 1100, maximumRPM: 3500).fraction, 0.5)
    }

    func testFractionIsClampedAndNeedsAMaximum() {
        XCTAssertEqual(FanSnapshot(rpm: 4000, minimumRPM: nil, maximumRPM: 3500).fraction, 1)
        XCTAssertNil(FanSnapshot(rpm: 1200, minimumRPM: 1100, maximumRPM: nil).fraction)
        XCTAssertNil(FanSnapshot(rpm: 1200, minimumRPM: nil, maximumRPM: 0).fraction)
    }

    func testSnapshotsWithoutFansStillDecode() throws {
        // Snapshots written before fans existed (e.g. probe JSON) have no "fans" key.
        let json = #"{"rpm":1200,"maximumRPM":3500}"#
        let fan = try JSONDecoder().decode(FanSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(fan.minimumRPM)
        XCTAssertEqual(fan.maximumRPM, 3500)
    }
}

final class FanAndThermalReadingTests: XCTestCase {
    private func snapshot(fans: [FanSnapshot]?, thermal: String = "nominal", diskFree: Int64 = 125 << 30,
                          pressureLevel: Int? = 1) -> SystemSnapshot {
        var snapshot = SystemSnapshot(
            capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 2,
            cpuUserPercent: 8, cpuSystemPercent: 4, cpuIdlePercent: 88,
            physicalMemoryBytes: 16 << 30, freeMemoryBytes: 1 << 30, wiredMemoryBytes: 2 << 30,
            compressedMemoryBytes: 1 << 30, appMemoryBytes: 5 << 30, swapUsedBytes: 0, uptimeSeconds: 100,
            thermalState: thermal,
            volumes: [VolumeSnapshot(name: "Macintosh HD", path: "/", totalBytes: 500 << 30, availableBytes: diskFree)],
            power: PowerSnapshot(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil, lowPowerMode: false))
        snapshot.fans = fans
        snapshot.memoryPressureLevel = pressureLevel
        return snapshot
    }

    private let macStudioFans = [FanSnapshot(rpm: 1333.33, minimumRPM: 1100, maximumRPM: 3500),
                                 FanSnapshot(rpm: 1327.4, minimumRPM: 1100, maximumRPM: 3500)]

    private func reading(_ value: MenuBarValue, _ snapshot: SystemSnapshot?) -> MenuBarReading {
        MenuBarFormatter.reading(.power, settings: MenuBarModuleSettings(value: value), snapshot: snapshot)
    }

    func testPowerModuleOffersFanAndHeatValues() {
        XCTAssertTrue(MenuBarModule.power.valueOptions.contains(.powerFanSpeed))
        XCTAssertTrue(MenuBarModule.power.valueOptions.contains(.powerFanPercent))
        XCTAssertTrue(MenuBarModule.power.valueOptions.contains(.powerThermal))
        XCTAssertEqual(MenuBarModule.power.valueOptions.first, .powerBattery, "battery stays the default")
    }

    func testFanSpeedShowsTheFastestFan() {
        let result = reading(.powerFanSpeed, snapshot(fans: macStudioFans))
        XCTAssertEqual(result.lines, ["1333 rpm"])
        XCTAssertEqual(result.reserve, ["9999 rpm"])
        XCTAssertEqual(try XCTUnwrap(result.fraction), 1333.33 / 3500, accuracy: 0.0001)
        XCTAssertEqual(result.accessibility, "En hızlı fan: 1333 rpm")
    }

    func testFanPercentIsShareOfMaximum() {
        // 1333.33 / 3500 = 38.1 %
        XCTAssertEqual(reading(.powerFanPercent, snapshot(fans: macStudioFans)).lines, ["%38"])
        let single = reading(.powerFanPercent, snapshot(fans: [FanSnapshot(rpm: 1750, minimumRPM: nil, maximumRPM: 3500)]))
        XCTAssertEqual(single.lines, ["%50"])
        XCTAssertEqual(single.accessibility, "Fan: 1750 rpm")
    }

    func testFanPercentFallsBackToSpeedWithoutAMaximum() {
        let result = reading(.powerFanPercent, snapshot(fans: [FanSnapshot(rpm: 1200, minimumRPM: nil, maximumRPM: nil)]))
        XCTAssertEqual(result.lines, ["1200 rpm"])
        XCTAssertNil(result.fraction)
    }

    func testFanlessAndUnreadableMacsShowADash() {
        let fanless = reading(.powerFanSpeed, snapshot(fans: []))
        XCTAssertEqual(fanless.lines, ["—"])
        XCTAssertEqual(fanless.accessibility, "Bu Mac’te fan yok")
        let unreadable = reading(.powerFanSpeed, snapshot(fans: nil))
        XCTAssertEqual(unreadable.lines, ["—"])
        XCTAssertEqual(reading(.powerFanSpeed, nil).lines, ["—"])
    }

    func testThermalStateIsNamedAndScaled() {
        let fair = reading(.powerThermal, snapshot(fans: nil, thermal: "fair"))
        XCTAssertEqual(fair.lines, ["Hafif yüksek"])
        XCTAssertEqual(fair.fraction, 0.5)
        XCTAssertEqual(reading(.powerThermal, snapshot(fans: nil)).reserve, ["Normal"], "sized to the current state, no gap")
        XCTAssertEqual(reading(.powerThermal, snapshot(fans: nil, thermal: "critical")).fraction, 1)
        XCTAssertNil(reading(.powerThermal, snapshot(fans: nil, thermal: "weird")).fraction)
    }

    func testShortLabelAndSymbolFollowTheShownValue() {
        XCTAssertEqual(MenuBarModule.power.shortLabel(for: .powerFanSpeed), "FAN")
        XCTAssertEqual(MenuBarModule.power.shortLabel(for: .powerThermal), "ISI")
        XCTAssertEqual(MenuBarModule.power.shortLabel(for: .powerBattery), "GÜÇ")
        XCTAssertEqual(MenuBarValue.powerFanPercent.symbol, "fan")
        XCTAssertNil(MenuBarValue.cpuTotal.symbol)
    }

    // MARK: Attention dot

    func testCalmMacNeedsNoAttention() {
        let calm = snapshot(fans: macStudioFans)
        XCTAssertFalse(MenuBarAttention.isNeeded(calm, diskFreeThreshold: 10))
        XCTAssertEqual(MenuBarAttention.reasons(calm, diskFreeThreshold: 10), [])
        XCTAssertFalse(MenuBarAttention.isNeeded(nil, diskFreeThreshold: 10))
    }

    func testEachConditionRaisesAttentionWithItsReason() {
        // 20 GB free of 500 GB = 4 %, below the 10 % threshold.
        XCTAssertEqual(MenuBarAttention.reasons(snapshot(fans: nil, diskFree: 20 << 30), diskFreeThreshold: 10), ["Disk alanı azaldı"])
        XCTAssertEqual(MenuBarAttention.reasons(snapshot(fans: nil, thermal: "serious"), diskFreeThreshold: 10), ["Isı yüksek"])
        XCTAssertEqual(MenuBarAttention.reasons(snapshot(fans: nil, pressureLevel: 4), diskFreeThreshold: 10), ["Bellek baskısı kritik"])
    }

    func testDiskThresholdComesFromTheCaller() {
        // 25 % free: fine at a 10 % threshold, low at 30 %.
        let quarterFree = snapshot(fans: nil, diskFree: 125 << 30)
        XCTAssertFalse(MenuBarAttention.isNeeded(quarterFree, diskFreeThreshold: 10))
        XCTAssertTrue(MenuBarAttention.isNeeded(quarterFree, diskFreeThreshold: 30))
    }

    func testMultipleReasonsKeepAStableOrder() {
        let troubled = snapshot(fans: nil, thermal: "critical", diskFree: 1 << 30, pressureLevel: 4)
        XCTAssertEqual(MenuBarAttention.reasons(troubled, diskFreeThreshold: 10),
                       ["Disk alanı azaldı", "Isı yüksek", "Bellek baskısı kritik"])
    }
}

final class HottestSensorTests: XCTestCase {
    func testHottestIgnoresCalibrationSensors() {
        let readings = [TemperatureReading(name: "PMU tdie1", celsius: 48.2),
                        TemperatureReading(name: "PMU tcal", celsius: 51.5),
                        TemperatureReading(name: "NAND CH0 temp", celsius: 39)]
        XCTAssertEqual(TemperatureSummary.hottest(readings)?.name, "PMU tdie1")
        XCTAssertNil(TemperatureSummary.hottest([TemperatureReading(name: "PMU tcal", celsius: 51.5)]))
    }

    func testMenuBarShowsHottestInCelsius() {
        var snapshot = SystemSnapshot(
            capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 2,
            cpuUserPercent: 8, cpuSystemPercent: 4, cpuIdlePercent: 88,
            physicalMemoryBytes: 16 << 30, freeMemoryBytes: 1 << 30, wiredMemoryBytes: 2 << 30,
            compressedMemoryBytes: 1 << 30, appMemoryBytes: 5 << 30, swapUsedBytes: 0, uptimeSeconds: 100,
            thermalState: "nominal", volumes: [],
            power: PowerSnapshot(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil, lowPowerMode: false))
        let settings = MenuBarModuleSettings(value: .powerTemperature)
        XCTAssertTrue(MenuBarModule.power.valueOptions.contains(.powerTemperature))
        snapshot.temperatures = [TemperatureReading(name: "PMU tdie3", celsius: 61.6), TemperatureReading(name: "PMU tdev1", celsius: 44)]
        let reading = MenuBarFormatter.reading(.power, settings: settings, snapshot: snapshot)
        XCTAssertEqual(reading.lines, ["62°"])
        XCTAssertEqual(reading.fraction ?? 0, 0.616, accuracy: 0.001)
        snapshot.temperatures = []
        XCTAssertEqual(MenuBarFormatter.reading(.power, settings: settings, snapshot: snapshot).lines, ["—"])
        XCTAssertEqual(MenuBarModule.power.shortLabel(for: .powerTemperature), "°C")
    }
}

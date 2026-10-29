import Darwin
import XCTest
@testable import MacPocketCore

final class PowerInspectorTests: XCTestCase {
    // MARK: energy math

    private func counters(pid: Int32 = 10, start: UInt64 = 1, energy: UInt64, cpu: UInt64, wakeups: UInt64 = 0) -> ProcessEnergyCounters {
        ProcessEnergyCounters(pid: pid, startAbsoluteTime: start, energyNanojoules: energy, billedEnergy: 0,
                              cpuNanoseconds: cpu, wakeups: wakeups)
    }

    func testEnergyDeltaMath() throws {
        // 3 J over 2 s = 1.5 W; 1 s CPU over 2 s = 50 %; 40 wakeups over 2 s = 20/s.
        let usage = try XCTUnwrap(ProcessEnergyMath.usage(
            previous: counters(energy: 1_000_000_000, cpu: 500_000_000, wakeups: 10),
            current: counters(energy: 4_000_000_000, cpu: 1_500_000_000, wakeups: 50),
            interval: 2, name: "Safari", path: "/Applications/Safari.app"))
        XCTAssertEqual(usage.milliwatts, 1500, accuracy: 0.001)
        XCTAssertEqual(usage.cpuPercent, 50, accuracy: 0.001)
        XCTAssertEqual(usage.wakeupsPerSecond, 20, accuracy: 0.001)
        XCTAssertEqual(usage.joules, 3, accuracy: 0.0001)
        XCTAssertEqual(usage.name, "Safari")
    }

    func testEnergyDeltaRejectsInvalidSamples() {
        let base = counters(energy: 100, cpu: 100)
        XCTAssertNil(ProcessEnergyMath.usage(previous: base, current: counters(energy: 200, cpu: 200), interval: 0, name: "", path: ""))
        XCTAssertNil(ProcessEnergyMath.usage(previous: base, current: counters(start: 2, energy: 200, cpu: 200), interval: 1, name: "", path: ""))
        XCTAssertNil(ProcessEnergyMath.usage(previous: base, current: counters(pid: 11, energy: 200, cpu: 200), interval: 1, name: "", path: ""))
        XCTAssertNil(ProcessEnergyMath.usage(previous: base, current: counters(energy: 50, cpu: 200), interval: 1, name: "", path: ""))
        XCTAssertNil(ProcessEnergyMath.usage(previous: base, current: counters(energy: 200, cpu: 50), interval: 1, name: "", path: ""))
    }

    func testTimebaseConversion() {
        XCTAssertEqual(ProcessEnergyMath.nanoseconds(fromAbsolute: 24, numer: 125, denom: 3), 1000)
        XCTAssertEqual(ProcessEnergyMath.nanoseconds(fromAbsolute: 777, numer: 1, denom: 1), 777)
        XCTAssertEqual(ProcessEnergyMath.nanoseconds(fromAbsolute: UInt64.max, numer: 125, denom: 3), UInt64.max)
        XCTAssertEqual(ProcessEnergyMath.nanoseconds(fromAbsolute: 5, numer: 1, denom: 0), 5)
    }

    // MARK: IOKit dictionaries

    func testBatteryRegistryAppleSiliconLaptop() throws {
        let properties: [String: Any] = [
            "BatteryInstalled": true, "CycleCount": NSNumber(value: 212), "DesignCapacity": NSNumber(value: 4382),
            "AppleRawMaxCapacity": NSNumber(value: 3900), "MaxCapacity": NSNumber(value: 100),
            "AppleRawCurrentCapacity": NSNumber(value: 3120), "CurrentCapacity": NSNumber(value: 80),
            "Temperature": NSNumber(value: 3050), "Voltage": NSNumber(value: 12_400),
            "InstantAmperage": NSNumber(value: UInt64(bitPattern: -1500)), "IsCharging": false,
            "ExternalConnected": false, "FullyCharged": false, "TimeRemaining": NSNumber(value: 245),
            "Serial": "F8Y123", "DeviceName": "bq40z651", "DesignCycleCount9C": NSNumber(value: 1000),
            "PermanentFailureStatus": NSNumber(value: 0), "ChargerData": ["NotChargingReason": NSNumber(value: 0)],
            "PowerTelemetryData": ["SystemPowerIn": NSNumber(value: 0), "BatteryPower": NSNumber(value: 18_600)],
        ]
        let battery = BatteryRegistryInfo(properties: properties)
        XCTAssertTrue(battery.installed)
        XCTAssertEqual(battery.cycleCount, 212)
        XCTAssertEqual(battery.maxCapacity, 3900)
        XCTAssertEqual(battery.currentCapacity, 3120)
        XCTAssertEqual(try XCTUnwrap(battery.healthPercent), 89.0, accuracy: 0.1)
        XCTAssertEqual(battery.temperatureCelsius, 30.5)
        XCTAssertEqual(battery.amperageMilliamps, -1500)
        XCTAssertEqual(try XCTUnwrap(battery.batteryWatts), -18.6, accuracy: 0.01)
        XCTAssertEqual(battery.timeRemainingMinutes, 245)
        XCTAssertEqual(battery.designCycleCount, 1000)
        XCTAssertEqual(battery.permanentFailure, false)
        XCTAssertNil(battery.systemPowerInMilliwatts)
    }

    func testBatteryRegistryDesktopWithoutBattery() {
        // Captured from a Mac Studio: the service exists but reports no battery.
        let properties: [String: Any] = [
            "BatteryInstalled": false, "CycleCount": NSNumber(value: 0), "MaxCapacity": NSNumber(value: 0),
            "ExternalConnected": true, "AdapterDetails": ["FamilyCode": NSNumber(value: 0)],
            "PowerTelemetryData": ["SystemPowerIn": NSNumber(value: 29_512), "SystemVoltageIn": NSNumber(value: 12_092),
                                   "SystemCurrentIn": NSNumber(value: 2440), "BatteryPower": NSNumber(value: 0)],
        ]
        let battery = BatteryRegistryInfo(properties: properties)
        XCTAssertFalse(battery.installed)
        XCTAssertNil(battery.cycleCount)
        XCTAssertNil(battery.healthPercent)
        XCTAssertNil(battery.batteryWatts)
        XCTAssertEqual(battery.externalConnected, true)
        XCTAssertEqual(battery.systemPowerInMilliwatts, 29_512)
        XCTAssertEqual(battery.systemVoltageInMillivolts, 12_092)
    }

    func testPowerSourceDescriptions() throws {
        let battery = PowerSourceInfo(description: [
            "Name": "InternalBattery-0", "Type": "InternalBattery", "Transport Type": "Internal",
            "Power Source State": "Battery Power", "Current Capacity": NSNumber(value: 64),
            "Max Capacity": NSNumber(value: 100), "Is Charging": false, "Time to Empty": NSNumber(value: 312),
            "Time to Full Charge": NSNumber(value: -1), "BatteryHealth": "Good",
            "Optimized Battery Charging Engaged": NSNumber(value: 1),
        ])
        XCTAssertTrue(battery.isInternalBattery)
        XCTAssertEqual(try XCTUnwrap(battery.chargePercent), 64, accuracy: 0.01)
        XCTAssertEqual(battery.timeToEmptyMinutes, 312)
        XCTAssertNil(battery.timeToFullMinutes)
        XCTAssertEqual(battery.health, "Good")
        XCTAssertEqual(battery.optimizedChargingEngaged, true)

        let ups = PowerSourceInfo(description: ["Name": "Back-UPS 700", "Type": "UPS", "Transport Type": "USB",
                                                "Power Source State": "AC Power", "Current Capacity": NSNumber(value: 100),
                                                "Max Capacity": NSNumber(value: 100)])
        XCTAssertTrue(ups.isUPS)
        XCTAssertEqual(ups.transport, "USB")
    }

    func testAdapterDetails() {
        let laptop = PowerAdapterInfo(dictionary: ["Watts": NSNumber(value: 96), "Name": "96W USB-C Power Adapter",
                                                   "Manufacturer": "Apple Inc.", "SerialString": "C4H123",
                                                   "AdapterVoltage": NSNumber(value: 20_000), "Current": NSNumber(value: 4700),
                                                   "IsWireless": false, "FamilyCode": NSNumber(value: -536_854_528)])
        XCTAssertTrue(laptop.hasDetails)
        XCTAssertEqual(laptop.watts, 96)
        XCTAssertEqual(laptop.serial, "C4H123")
        XCTAssertEqual(laptop.voltageMillivolts, 20_000)
        let desktop = PowerAdapterInfo(dictionary: ["FamilyCode": NSNumber(value: 0)])
        XCTAssertFalse(desktop.hasDetails)
        XCTAssertNil(desktop.watts)
    }
}

/// Read-only checks against the real machine. No privileged command is run.
final class PowerLiveSystemTests: XCTestCase {
    func testOverviewReadsThisMac() {
        let overview = PowerInspector.overview()
        XCTAssertTrue(["AC Power", "Battery Power", "UPS Power"].contains(overview.providingSource), overview.providingSource)
        XCTAssertTrue(["nominal", "fair", "serious", "critical"].contains(overview.thermalState))
        if overview.hasBattery {
            XCTAssertNotNil(overview.internalBattery?.chargePercent)
        }
    }

    func testPmsetReadersReturnSensibleData() async throws {
        let settings = try await PowerCommandReader.settings()
        XCTAssertFalse(settings.profiles.isEmpty, "pmset -g custom produced no profile")
        XCTAssertNotNil(settings.profiles.first?.value(.sleep) ?? settings.profiles.first?.value(.displaysleep))
        XCTAssertFalse(settings.live.values.isEmpty)
        XCTAssertNotNil(settings.live.value(.sleep))

        let assertions = try await PowerCommandReader.assertions()
        XCTAssertFalse(assertions.systemWide.isEmpty)
        XCTAssertTrue(assertions.systemWide.keys.contains("PreventUserIdleSystemSleep"))
        // powerd holds an assertion while the display is on on every Mac.
        XCTAssertTrue(assertions.assertions.contains { $0.process == "powerd" }, "\(assertions.assertions.map(\.process))")

        let thermal = try await PowerCommandReader.thermal()
        XCTAssertFalse(thermal.notes.isEmpty && thermal.values.isEmpty)
        _ = try await PowerCommandReader.schedule() // may be legitimately empty
    }

    func testStreamingLogReaderFindsEventsWithBoundedOutput() async throws {
        let events = try await PowerCommandReader.recentLogEvents(limit: 20)
        XCTAssertFalse(events.isEmpty, "pmset -g log should contain at least the powerd start event")
        XCTAssertLessThanOrEqual(events.count, 20)
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted())
    }

    func testLogReaderCancellation() async {
        let task = Task { try await PowerCommandReader.recentLogEvents(limit: 5) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let start = Date()
        let result = await task.result
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        if case let .failure(error) = result { XCTAssertTrue(error is CancellationError, "\(error)") }
    }

    func testEnergySamplerReadsOwnProcesses() async throws {
        let sampler = ProcessEnergySampler()
        let primed = await sampler.sample()
        XCTAssertTrue(primed.processes.isEmpty)
        XCTAssertGreaterThan(primed.readableCount, 0)
        // Burn some CPU so this test process shows up.
        var accumulator = 0.0
        let end = Date().addingTimeInterval(0.4)
        while Date() < end { accumulator += sin(accumulator + 1) }
        XCTAssertFalse(accumulator.isNaN)
        let sample = await sampler.sample(limit: 500)
        XCTAssertGreaterThan(sample.interval, 0.3)
        XCTAssertGreaterThan(sample.unreadableCount, 0, "root processes should be unreadable without privileges")
        let me = try XCTUnwrap(sample.processes.first { $0.pid == getpid() })
        XCTAssertGreaterThan(me.cpuPercent, 20)
        XCTAssertGreaterThan(me.milliwatts, 0)
        XCTAssertEqual(sample.processes.map(\.milliwatts), sample.processes.map(\.milliwatts).sorted(by: >))
    }
}

import XCTest
@testable import MacPocketCore

/// GPU module, network status values, new display styles and the temperature sensor choice.
final class MenuBarExtrasTests: XCTestCase {
    private func snapshot() -> SystemSnapshot {
        var snapshot = SystemSnapshot(
            capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 4,
            cpuUserPercent: 10, cpuSystemPercent: 5, cpuIdlePercent: 85,
            physicalMemoryBytes: 16 << 30, freeMemoryBytes: 1 << 30, wiredMemoryBytes: 2 << 30,
            compressedMemoryBytes: 1 << 30, appMemoryBytes: 5 << 30, swapUsedBytes: 0, uptimeSeconds: 100,
            thermalState: "nominal", volumes: [],
            power: PowerSnapshot(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil, lowPowerMode: false))
        snapshot.gpu = GPUSnapshot(utilizationPercent: 28, rendererPercent: 30, tilerPercent: 14, memoryInUseBytes: 4 << 30,
                                   model: "Apple M4 Pro", coreCount: 20)
        snapshot.connectivity = ConnectivitySnapshot(online: true, link: .wifi, vpnActive: false, wifiRSSI: -58, pingMilliseconds: 15.65)
        snapshot.diskIO = DiskIOSnapshot(readBytesPerSecond: 2_097_152, writeBytesPerSecond: 0)
        snapshot.temperatures = [TemperatureReading(name: "PMU tdie1", celsius: 48), TemperatureReading(name: "PMU tdie2", celsius: 61.4)]
        return snapshot
    }

    private func reading(_ module: MenuBarModule, _ value: MenuBarValue, sensor: String = "", decimals: Bool = false,
                         _ snapshot: SystemSnapshot? = nil) -> MenuBarReading {
        MenuBarFormatter.reading(module, settings: MenuBarModuleSettings(decimals: decimals, value: value, sensorName: sensor),
                                 snapshot: snapshot ?? self.snapshot())
    }

    func testGPUStatisticsParseFromTheRegistry() {
        let parsed = GPUSnapshot(properties: [
            "model": "Apple M4 Pro", "gpu-core-count": 20,
            "PerformanceStatistics": ["Device Utilization %": 28, "Renderer Utilization %": 27, "Tiler Utilization %": 14,
                                      "In use system memory": 2_630_041_600] as [String: Any],
        ])
        XCTAssertEqual(parsed, GPUSnapshot(utilizationPercent: 28, rendererPercent: 27, tilerPercent: 14,
                                           memoryInUseBytes: 2_630_041_600, model: "Apple M4 Pro", coreCount: 20))
        XCTAssertNil(GPUSnapshot(properties: ["model": "Display only"]), "Accelerators without statistics are skipped")
    }

    func testGPUModuleReadsUtilizationRendererAndMemory() {
        XCTAssertEqual(MenuBarModule.gpu.valueOptions, [.gpuUtilization, .gpuRenderer, .gpuMemory])
        XCTAssertFalse(MenuBarModule.gpu.enabledByDefault)
        let usage = reading(.gpu, .gpuUtilization)
        XCTAssertEqual(usage.fraction, 0.28)
        XCTAssertEqual(reading(.gpu, .gpuRenderer).fraction, 0.30)
        let memory = reading(.gpu, .gpuMemory)
        XCTAssertEqual(memory.lines, ["4,0 GB"])
        XCTAssertEqual(memory.fraction, 0.25)
        var noGPU = snapshot(); noGPU.gpu = nil
        XCTAssertEqual(reading(.gpu, .gpuUtilization, noGPU).lines, ["—"])
    }

    func testPingParsingAndLatencyReading() {
        XCTAssertEqual(PingParser.milliseconds("64 bytes from 1.1.1.1: icmp_seq=0 ttl=56 time=15.650 ms"), 15.65)
        XCTAssertEqual(ConnectivityMonitor.roundTrip("round-trip min/avg/max/stddev = 15.650/16.100/17.000/0.000 ms"), 16.1)
        XCTAssertNil(PingParser.milliseconds("Request timeout for icmp_seq 0"))
        XCTAssertEqual(reading(.network, .networkPing).lines, ["16 ms"])
        var failed = snapshot(); failed.connectivity?.pingMilliseconds = nil; failed.connectivity?.pingFailed = true
        XCTAssertEqual(reading(.network, .networkPing, failed).lines, ["—"])
    }

    func testWifiSignalAndOfflineState() {
        let signal = reading(.network, .networkWifiSignal)
        XCTAssertEqual(signal.lines, ["-58 dBm"])
        XCTAssertEqual(signal.fraction!, 32.0 / 60, accuracy: 0.001)
        var wired = snapshot(); wired.connectivity?.wifiRSSI = nil
        XCTAssertEqual(reading(.network, .networkWifiSignal, wired).lines, ["—"])
        var offline = snapshot(); offline.connectivity?.online = false
        for value in MenuBarModule.network.valueOptions {
            XCTAssertEqual(reading(.network, value, offline).lines, ["Çevrimdışı"], "\(value) says offline")
        }
        var unknown = snapshot(); unknown.connectivity?.online = nil
        XCTAssertNotEqual(reading(.network, .networkCombined, unknown).lines, ["Çevrimdışı"], "No path update yet is not offline")
    }

    func testVPNNeedsATunnelWithANetworkService() {
        XCTAssertTrue(VPNDetector.isActive(scopedInterfaces: ["en0", "utun4"]))
        XCTAssertTrue(VPNDetector.isActive(scopedInterfaces: ["ipsec0"]))
        XCTAssertFalse(VPNDetector.isActive(scopedInterfaces: ["en0", "en1"]))
        XCTAssertFalse(VPNDetector.isActive(scopedInterfaces: []))
    }

    func testDiskReadWriteShowsTwoLines() {
        let rw = reading(.disk, .diskReadWrite)
        XCTAssertEqual(rw.lines, ["O 2,0 MB/s", "Y 0 KB/s"])
        XCTAssertEqual(rw.reserve.count, 2)
    }

    func testTemperatureFollowsTheChosenSensorAndFallsBackToTheHottest() {
        XCTAssertEqual(reading(.power, .powerTemperature).lines, ["61°"])
        XCTAssertEqual(reading(.power, .powerTemperature, sensor: "PMU tdie1").lines, ["48°"])
        XCTAssertEqual(reading(.power, .powerTemperature, sensor: "PMU tdie2", decimals: true).lines, ["61,4°"])
        XCTAssertEqual(reading(.power, .powerTemperature, sensor: "gone").lines, ["61°"], "A missing sensor falls back")
    }

    func testCoresStyleIsCPUOnlyAndOldSettingsStillDecode() throws {
        XCTAssertTrue(MenuBarModule.cpu.styleOptions.contains(.cores))
        XCTAssertFalse(MenuBarModule.memory.styleOptions.contains(.cores))
        XCTAssertTrue(MenuBarModule.memory.styleOptions.contains(.pie))
        var preferences = MenuBarPreferences()
        preferences.modules[.memory] = MenuBarModuleSettings(style: .cores, value: .memoryUsedPercent)
        XCTAssertEqual(preferences.settings(for: .memory).style, .value, "An impossible style falls back")

        let legacy = Data(#"{"style":"gauge","showLabel":true,"showIcon":false,"showValue":true,"decimals":false,"value":"networkUpDown","volumePath":""}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuBarModuleSettings.self, from: legacy)
        XCTAssertEqual(decoded.sensorName, "")
        XCTAssertTrue(decoded.showVPN)
        XCTAssertEqual(MenuBarPreferences.completeOrder([.network, .cpu]).last, .display)
        XCTAssertTrue(MenuBarPreferences.completeOrder([.network, .cpu]).contains(.gpu), "Existing orders gain the GPU module")
    }

    func testThresholdColoringFollowsUnitsAndDirection() {
        var cpu = MenuBarModuleSettings(value: .cpuTotal)
        let busy = MenuBarFormatter.reading(.cpu, settings: cpu, snapshot: snapshot())
        XCTAssertEqual(busy.thresholdValue, 15)
        XCTAssertEqual(MenuBarThresholds.level(busy, settings: cpu), .normal, "Coloring is off by default")
        cpu.colorMode = .thresholds
        cpu.warningThreshold = 10
        XCTAssertEqual(MenuBarThresholds.level(busy, settings: cpu), .warning)
        cpu.criticalThreshold = 14
        XCTAssertEqual(MenuBarThresholds.level(busy, settings: cpu), .critical)

        var temperature = MenuBarModuleSettings(value: .powerTemperature, colorMode: .thresholds)
        let hot = MenuBarFormatter.reading(.power, settings: temperature, snapshot: snapshot())
        XCTAssertEqual(hot.thresholdValue, 61.4)
        XCTAssertEqual(MenuBarThresholds.level(hot, settings: temperature), .normal, "Default 80 °C warning")
        temperature.warningThreshold = 60
        XCTAssertEqual(MenuBarThresholds.level(hot, settings: temperature), .warning)

        let ping = MenuBarModuleSettings(value: .networkPing, colorMode: .thresholds, warningThreshold: 10)
        XCTAssertEqual(MenuBarThresholds.level(MenuBarFormatter.reading(.network, settings: ping, snapshot: snapshot()), settings: ping), .warning)

        var signal = MenuBarModuleSettings(value: .networkWifiSignal, colorMode: .thresholds)
        let wifi = MenuBarFormatter.reading(.network, settings: signal, snapshot: snapshot())
        XCTAssertEqual(wifi.thresholdValue, -58)
        XCTAssertEqual(MenuBarThresholds.level(wifi, settings: signal), .normal, "−58 dBm is above the −70 warning")
        signal.warningThreshold = -55
        XCTAssertEqual(MenuBarThresholds.level(wifi, settings: signal), .warning, "Lower is worse for signal")

        let rates = MenuBarModuleSettings(value: .networkCombined, colorMode: .thresholds)
        XCTAssertNil(MenuBarValue.networkCombined.thresholdUnit)
        XCTAssertEqual(MenuBarThresholds.level(MenuBarFormatter.reading(.network, settings: rates, snapshot: snapshot()), settings: rates), .normal)

        var pending = snapshot(); pending.gpu = nil
        let gpu = MenuBarModuleSettings(value: .gpuUtilization, colorMode: .thresholds, warningThreshold: 0)
        XCTAssertEqual(MenuBarThresholds.level(MenuBarFormatter.reading(.gpu, settings: gpu, snapshot: pending), settings: gpu), .normal,
                       "A missing reading is never colored")
    }

    func testThresholdSettingsRoundTripAndDefaults() throws {
        let settings = MenuBarModuleSettings(value: .powerBattery, colorMode: .thresholds, warningThreshold: 30)
        let decoded = try JSONDecoder().decode(MenuBarModuleSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.thresholds?.warning, 30)
        XCTAssertEqual(decoded.thresholds?.critical, 10, "Unset critical keeps the default")
        XCTAssertTrue(MenuBarValue.powerBattery.lowerIsWorse)
        XCTAssertTrue(MenuBarValue.allCases.allSatisfy { ($0.thresholdUnit == nil) == ($0.defaultThresholds == nil) },
                      "Every value with a unit has defaults and vice versa")
    }
}


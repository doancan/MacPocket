import XCTest
@testable import MacPocketCore

final class BluetoothBatteryTests: XCTestCase {
    private let profiler = """
    {"SPBluetoothDataType":[{"controller_properties":{},
      "device_connected":[
        {"Alex’s Magic Keyboard":{"device_address":"88:4D:7C:EE:50:D6","device_minorType":"Keyboard"}},
        {"Alex's Magic Trackpad 2":{"device_address":"64:A5:C3:F1:7B:96","device_minorType":"Magic Trackpad"}},
        {"MX Master":{"device_address":"C7:79:29:95:8A:D6","device_minorType":"Mouse"}},
        {"Alex’s AirPods Pro":{"device_address":"2C:32:6A:F3:BA:1B","device_minorType":"Headphones",
           "device_batteryLevelLeft":"80%","device_batteryLevelRight":"75%","device_batteryLevelCase":"40%"}}
      ],
      "device_not_connected":[{"Office":{"device_address":"34:FD:6A:38:09:F9"}}]}]}
    """.data(using: .utf8)!

    func testParsesConnectedDevicesKindsAndAirPodsLevels() {
        let devices = BluetoothBatteryParser.connectedDevices(fromSystemProfiler: profiler)
        XCTAssertEqual(devices.map(\.name), ["Alex’s AirPods Pro", "Alex’s Magic Keyboard", "Alex's Magic Trackpad 2", "MX Master"])
        XCTAssertEqual(devices.map(\.kind), [.headphones, .keyboard, .trackpad, .mouse])
        let airPods = devices[0]
        XCTAssertEqual(airPods.levels, .init(left: 80, right: 75, batteryCase: 40))
        XCTAssertEqual(airPods.levels.lowest, 75, "The case doesn't count while the buds report")
        XCTAssertTrue(devices[3].levels.isEmpty)
        XCTAssertTrue(BluetoothBatteryParser.connectedDevices(fromSystemProfiler: Data("{}".utf8)).isEmpty)
    }

    func testRegistryLevelsAreMatchedByNormalizedAddress() {
        XCTAssertEqual(BluetoothBatteryParser.normalize("64-a5-c3-f1-7b-96"), "64:A5:C3:F1:7B:96")
        let merged = BluetoothBatteryParser.merge(BluetoothBatteryParser.connectedDevices(fromSystemProfiler: profiler), registry: [
            BluetoothBatteryParser.normalize("64-a5-c3-f1-7b-96"): RegistryBattery(level: 4, productID: 0x0265, wired: false),
            "88:4D:7C:EE:50:D6": RegistryBattery(level: 65, productID: 0x029F, wired: false),
        ])
        XCTAssertEqual(merged.first { $0.kind == .trackpad }?.levels.main, 4)
        XCTAssertEqual(merged.first { $0.kind == .keyboard }?.levels.lowest, 65)
        XCTAssertNil(merged.first { $0.kind == .mouse }?.levels.lowest)
    }

    /// Charging over its cable, the trackpad is a USB device that the Bluetooth list doesn't show as
    /// connected.
    func testCabledAccessoryStaysListedAsCharging() {
        let keyboardOnly = BluetoothBatteryParser.connectedDevices(fromSystemProfiler: profiler).filter { $0.kind == .keyboard }
        let merged = BluetoothBatteryParser.merge(keyboardOnly, registry: [
            "64:A5:C3:F1:7B:96": RegistryBattery(level: 13, productID: 0x0265, wired: true),
            "88:4D:7C:EE:50:D6": RegistryBattery(level: 65, productID: 0x029F, wired: false),
        ])
        let trackpad = merged.first { $0.address == "64:A5:C3:F1:7B:96" }
        XCTAssertEqual(trackpad?.name, "Magic Trackpad")
        XCTAssertEqual(trackpad?.kind, .trackpad)
        XCTAssertEqual(trackpad?.levels.main, 13)
        XCTAssertEqual(trackpad?.charging, true)
        XCTAssertEqual(merged.count, 2)
    }

    func testLogitechLevelsAreMatchedByName() {
        let devices = BluetoothBatteryParser.connectedDevices(fromSystemProfiler: profiler)
        let merged = BluetoothBatteryParser.merge(devices, logitech: [
            (name: "MX Master", kind: .mouse, reading: .init(percent: 50, charging: false)),
            (name: "MX Keys", kind: .keyboard, reading: .init(percent: 80, charging: true)),
        ])
        XCTAssertEqual(merged.first { $0.name == "MX Master" }?.levels.main, 50)
        let keys = merged.first { $0.name == "MX Keys" }
        XCTAssertEqual(keys?.levels.main, 80)
        XCTAssertEqual(keys?.charging, true)
        XCTAssertEqual(merged.count, devices.count + 1)
    }

    func testLowBatteryNotifiesOnceUntilCharged() {
        var alerts = LowBatteryAlerts(threshold: 20, rearm: 30)
        func device(_ level: Int) -> BluetoothBatteryDevice {
            BluetoothBatteryDevice(address: "A", name: "Trackpad", kind: .trackpad, levels: .init(main: level))
        }
        XCTAssertTrue(alerts.evaluate([device(50)]).isEmpty)
        XCTAssertEqual(alerts.evaluate([device(19)]).map(\.name), ["Trackpad"])
        XCTAssertTrue(alerts.evaluate([device(10)]).isEmpty, "Already told")
        XCTAssertTrue(alerts.evaluate([device(25)]).isEmpty, "Not charged enough to re-arm")
        XCTAssertTrue(alerts.evaluate([device(18)]).isEmpty)
        XCTAssertTrue(alerts.evaluate([device(35)]).isEmpty)
        XCTAssertEqual(alerts.evaluate([device(20)]).count, 1, "Charged, then low again")
    }
}

final class HIDPPBatteryTests: XCTestCase {
    func testRequestsAreTwentyByteLongReportsToTheDirectDevice() {
        let request = HIDPPBattery.featureRequest(.batteryStatus)
        XCTAssertEqual(request.count, 20)
        XCTAssertEqual(Array(request.prefix(6)), [0x11, 0xFF, 0x00, 0x01, 0x10, 0x00])
        XCTAssertEqual(Array(HIDPPBattery.levelRequest(.unifiedBattery, index: 8).prefix(4)), [0x11, 0xFF, 0x08, 0x11])
        XCTAssertEqual(Array(HIDPPBattery.levelRequest(.batteryStatus, index: 6).prefix(4)), [0x11, 0xFF, 0x06, 0x01])
    }

    /// Replies captured from an MX Master (BLE) on this Mac: 0x1000 at index 6, level 50 %, discharging.
    func testParsesRealMXMasterReplies() {
        let supported: [UInt8] = [0x11, 0xFF, 0x00, 0x01, 0x06, 0, 0] + [UInt8](repeating: 0, count: 13)
        let unsupported: [UInt8] = [0x11, 0xFF, 0x00, 0x01, 0x00, 0, 0] + [UInt8](repeating: 0, count: 13)
        XCTAssertEqual(HIDPPBattery.featureIndex(from: supported), 6)
        XCTAssertNil(HIDPPBattery.featureIndex(from: unsupported))
        let level: [UInt8] = [0x11, 0xFF, 0x06, 0x01, 0x32, 0x14, 0x00] + [UInt8](repeating: 0, count: 13)
        XCTAssertEqual(HIDPPBattery.reading(from: level, feature: .batteryStatus, index: 6), .init(percent: 50, charging: false))
        XCTAssertNil(HIDPPBattery.reading(from: level, feature: .batteryStatus, index: 7), "Another feature's reply")
        let mouseReport: [UInt8] = [0x02, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00]
        XCTAssertNil(HIDPPBattery.featureIndex(from: mouseReport))
    }

    func testUnifiedBatteryAndVoltage() {
        let unified: [UInt8] = [0x11, 0xFF, 0x08, 0x11, 87, 0x08, 0x01] + [UInt8](repeating: 0, count: 13)
        XCTAssertEqual(HIDPPBattery.reading(from: unified, feature: .unifiedBattery, index: 8), .init(percent: 87, charging: true))
        let voltage: [UInt8] = [0x11, 0xFF, 0x05, 0x01, 0x0E, 0xE3, 0x00] + [UInt8](repeating: 0, count: 13) // 3811 mV
        XCTAssertEqual(HIDPPBattery.reading(from: voltage, feature: .batteryVoltage, index: 5)?.percent, 50)
        XCTAssertEqual(HIDPPBattery.percent(millivolts: 4300), 100)
        XCTAssertEqual(HIDPPBattery.percent(millivolts: 3400), 0)
    }
}

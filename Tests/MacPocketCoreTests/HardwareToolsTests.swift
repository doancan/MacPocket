import XCTest
@testable import MacPocketCore

final class USBDeviceTests: XCTestCase {
    func testPropertiesAndSpeed() {
        let device = USBDevice(id: 5, parentID: 1, properties: [
            "USB Product Name": "Magic Trackpad", "USB Vendor Name": "Apple Inc.", "idVendor": 1452, "idProduct": 613,
            "UsbLinkSpeed": 12_000_000, "UsbPowerSinkAllocation": 1300, "bDeviceClass": 0,
        ], interfaceClasses: [3])
        XCTAssertEqual(device.name, "Magic Trackpad")
        XCTAssertEqual(device.vendor, "Apple Inc.")
        XCTAssertEqual(device.powerMilliamps, 1300)
        XCTAssertEqual(device.speedTitle, "USB 1 · 12 Mb/s")
        XCTAssertFalse(device.isSlowStorage)
    }

    func testFallsBackToSpeedCodeAndIDs() {
        let device = USBDevice(id: 1, parentID: nil, properties: ["idVendor": 0x2109, "idProduct": 0x0103, "Device Speed": 3],
                               interfaceClasses: [8])
        XCTAssertEqual(device.linkSpeed, 5_000_000_000)
        XCTAssertEqual(device.speedTitle, "USB 3 · 5 Gb/s")
        XCTAssertTrue(device.name.contains("2109:0103"))
        XCTAssertNil(device.powerMilliamps)
    }

    func testStorageOnUSB2IsFlagged() {
        let disk = USBDevice(id: 1, parentID: nil, properties: ["UsbLinkSpeed": 480_000_000], interfaceClasses: [8])
        XCTAssertTrue(disk.isSlowStorage)
        XCTAssertEqual(disk.speedTitle, "USB 2 · 480 Mb/s")
    }

    func testTreeOrdersChildrenUnderParents() {
        func device(_ id: UInt64, _ parent: UInt64?, _ name: String) -> USBDevice {
            USBDevice(id: id, parentID: parent, name: name, vendor: nil, vendorID: 0, productID: 0, linkSpeed: nil,
                      powerMilliamps: nil, deviceClass: 0, interfaceClasses: [])
        }
        let rows = USBTree.rows([device(3, 1, "Mouse"), device(1, nil, "Hub"), device(2, 1, "Keyboard"),
                                 device(4, 99, "Orphan")])
        XCTAssertEqual(rows.map(\.device.name), ["Hub", "Keyboard", "Mouse", "Orphan"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 0])
    }

    func testHidingHubsLiftsTheirChildren() {
        func device(_ id: UInt64, _ parent: UInt64?, _ name: String, hub: Bool = false) -> USBDevice {
            USBDevice(id: id, parentID: parent, name: name, vendor: nil, vendorID: 0, productID: 0, linkSpeed: nil,
                      powerMilliamps: nil, deviceClass: hub ? 9 : 0, interfaceClasses: [])
        }
        let devices = [device(1, nil, "Hub", hub: true), device(2, 1, "Inner Hub", hub: true), device(3, 2, "Disk"),
                       device(4, 1, "Mouse")]
        let rows = USBTree.rows(devices, includeHubs: false)
        XCTAssertEqual(rows.map(\.device.name), ["Disk", "Mouse"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }
}

final class ThunderboltReportTests: XCTestCase {
    func testParsesPortsAndChainedDevices() throws {
        let json = """
        {"SPThunderboltDataType":[
          {"_name":"bus_1","switch_uid_key":"B","receptacle_1_tag":{"current_speed_key":"Up to 120 Gb/s","receptacle_id_key":"2"}},
          {"_name":"bus_0","switch_uid_key":"A","receptacle_1_tag":{"current_speed_key":"Up to 40 Gb/s","receptacle_id_key":"1"},
           "_items":[{"device_name_key":"Dock","vendor_name_key":"CalDigit","switch_uid_key":"D",
                      "receptacle_upstream_tag":{"current_speed_key":"40 Gb/s"},
                      "_items":[{"device_name_key":"Display","switch_uid_key":"E"}]}]}
        ]}
        """
        let ports = ThunderboltReport.parse(Data(json.utf8))
        XCTAssertEqual(ports.map(\.receptacle), ["1", "2"])
        XCTAssertEqual(ports[0].speedGbps, 40)
        XCTAssertEqual(ports[0].devices.map(\.name), ["Dock", "Display"])
        XCTAssertEqual(ports[0].devices.map(\.depth), [0, 1])
        XCTAssertEqual(ports[0].devices[0].speedGbps, 40)
        XCTAssertFalse(ports[1].isConnected)
        XCTAssertTrue(ThunderboltReport.parse(Data("nope".utf8)).isEmpty)
    }
}

final class NVMeHealthTests: XCTestCase {
    private func log(warning: UInt8 = 0, kelvin: Int = 314, spare: UInt8 = 100, threshold: UInt8 = 99, used: UInt8 = 3,
                     written: UInt64 = 92_144_477, hours: UInt64 = 2744, media: UInt64 = 0) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 512)
        bytes[0] = warning
        bytes[1] = UInt8(kelvin & 0xFF); bytes[2] = UInt8(kelvin >> 8)
        bytes[3] = spare; bytes[4] = threshold; bytes[5] = used
        func put(_ value: UInt64, at offset: Int) { for i in 0..<8 { bytes[offset + i] = UInt8((value >> (8 * UInt64(i))) & 0xFF) } }
        put(written, at: 48); put(hours, at: 128); put(media, at: 160)
        return bytes
    }

    func testDecodesTheAppleSSDSample() throws {
        let health = try XCTUnwrap(NVMeHealth(log: log()))
        XCTAssertEqual(health.temperatureCelsius ?? 0, 40.85, accuracy: 0.01)
        XCTAssertEqual(health.percentageUsed, 3)
        XCTAssertEqual(health.lifeRemaining, 97)
        XCTAssertEqual(health.bytesWritten / 1e12, 47.18, accuracy: 0.01)
        XCTAssertEqual(health.powerOnHours, 2744)
        XCTAssertEqual(health.assessment.level, .good)
        XCTAssertTrue(health.assessment.findings.isEmpty)
        XCTAssertNil(NVMeHealth(log: [1, 2, 3]))
    }

    func testAssessmentLevels() throws {
        XCTAssertEqual(try XCTUnwrap(NVMeHealth(log: log(used: 85))).assessment.level, .attention)
        XCTAssertEqual(try XCTUnwrap(NVMeHealth(log: log(media: 2))).assessment.level, .attention)
        XCTAssertEqual(try XCTUnwrap(NVMeHealth(log: log(used: 104))).assessment.level, .critical)
        XCTAssertEqual(try XCTUnwrap(NVMeHealth(log: log(used: 104))).lifeRemaining, 0)
        XCTAssertEqual(try XCTUnwrap(NVMeHealth(log: log(spare: 5, threshold: 10))).assessment.level, .critical)
        let readOnly = try XCTUnwrap(NVMeHealth(log: log(warning: 0x08, used: 85)))
        XCTAssertEqual(readOnly.assessment.level, .critical)
        XCTAssertEqual(readOnly.assessment.findings.count, 2)
    }
}

final class WiFiAnalysisTests: XCTestCase {
    private func net(_ channel: Int, _ rssi: Int, band: WiFiBand = .ghz2_4, width: Int = 20, bssid: String? = nil) -> WiFiNetworkObservation {
        WiFiNetworkObservation(ssid: nil, bssid: bssid, rssi: rssi, channel: channel, band: band, widthMHz: width)
    }

    func testSignalQuality() {
        XCTAssertEqual(WiFiSignalQuality(rssi: -41), .excellent)
        XCTAssertEqual(WiFiSignalQuality(rssi: -60), .good)
        XCTAssertEqual(WiFiSignalQuality(rssi: -70), .fair)
        XCTAssertEqual(WiFiSignalQuality(rssi: -82), .weak)
    }

    func testOverlapOn24GHz() {
        let loads = WiFiAnalysis.channelLoads([net(6, -50), net(7, -60)], band: .ghz2_4)
        let byChannel = Dictionary(uniqueKeysWithValues: loads.map { ($0.channel, $0.load) })
        XCTAssertEqual(byChannel[1], 0)
        XCTAssertGreaterThan(byChannel[6]!, byChannel[11]!, "Channel 7 spills into 11 less than 6 itself")
        XCTAssertEqual(loads.first { $0.channel == 6 }?.networks, 2)
    }

    func testWideChannelsCoverTheirBlock() {
        let blocks = WiFiAnalysis.occupied(net(48, -60, band: .ghz5, width: 80)).map(\.channel)
        XCTAssertEqual(blocks, [36, 40, 44, 48])
        XCTAssertEqual(WiFiAnalysis.occupied(net(157, -60, band: .ghz5, width: 40)).map(\.channel), [157, 161])
    }

    func testAdviceSkipsOwnNetworkAndPrefersQuietChannel() throws {
        let own = net(6, -45, bssid: "aa")
        let scan = [own, net(6, -48), net(6, -55), net(1, -85)]
        let advice = try XCTUnwrap(WiFiAnalysis.advice(networks: scan, current: own))
        XCTAssertTrue(advice.shouldSwitch)
        XCTAssertEqual(advice.recommended, 11)
    }

    func testOnlySameRadioSSIDsAreLeftOut() throws {
        let own = net(48, -41, band: .ghz5, width: 80, bssid: "16:27:f5:db:d0:31")
        let scan = [net(48, -38, band: .ghz5, width: 80, bssid: "16:27:f5:db:d0:31"),
                    net(48, -38, band: .ghz5, width: 80, bssid: "12:27:f5:db:d0:32"),   // guest SSID, same router
                    net(48, -39, band: .ghz5, width: 80, bssid: "a4:91:b1:00:11:22"),   // separate access point
                    net(149, -80, band: .ghz5)]
        XCTAssertEqual(WiFiAnalysis.excludingOwn(scan, current: own).map(\.bssid), ["a4:91:b1:00:11:22", nil])
        XCTAssertTrue(WiFiAnalysis.sameRadio("16:27:f5:db:d0:31", "12:27:f5:db:d0:3a"))
        XCTAssertTrue(WiFiAnalysis.sameRadio("16:27:f5:db:d0:31", "1e:27:f5:db:d0:31"), "Seen live: KM Office on the same router")
        XCTAssertTrue(WiFiAnalysis.sameRadio("16:27:f5:db:d0:31", "1a:27:f5:db:d0:30"))
        XCTAssertFalse(WiFiAnalysis.sameRadio("16:27:f5:db:d0:31", "17:27:f5:db:d0:31"), "Multicast bit differs")
        XCTAssertFalse(WiFiAnalysis.sameRadio("16:27:f5:db:d0:31", "0a:a6:f7:97:91:bb"))
        XCTAssertFalse(WiFiAnalysis.sameRadio("16:27:f5:db:d0:31", "16:27:f5:aa:d0:31"))
    }

    func testOneForeignRouterCountsOnce() {
        let scan = ["0a:a6:f7:98:91:ba", "0a:a6:f7:98:91:bb", "0a:a6:f7:98:91:bc"].map {
            net(48, -67, band: .ghz5, width: 80, bssid: $0)
        }
        XCTAssertEqual(WiFiAnalysis.radios(scan).count, 1)
        let load = WiFiAnalysis.channelLoads(scan, band: .ghz5).first { $0.channel == 48 }
        XCTAssertEqual(load?.load, 28)
        XCTAssertEqual(load?.networks, 1)
        XCTAssertEqual(WiFiAnalysis.radios([net(6, -50), net(6, -50)]).count, 2, "Without BSSIDs nothing is merged")
    }

    func testAdviceStaysWhenAlreadyQuiet() throws {
        let own = net(36, -41, band: .ghz5, width: 80)
        // Without a BSSID, the network on our channel closest to our RSSI is taken as our own.
        let scan = [net(36, -38, band: .ghz5, width: 80), net(149, -80, band: .ghz5)]
        let advice = try XCTUnwrap(WiFiAnalysis.advice(networks: scan, current: own))
        XCTAssertFalse(advice.shouldSwitch)
        XCTAssertEqual(advice.recommended, 36)
    }
}

final class HostsFileTests: XCTestCase {
    private let sample = """
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    ##
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    ::1             localhost
    10.0.0.28 erp.internal
    #0.0.0.0 ads.example.com # blocked

    ## Local - Start ##
    ::1 site.local #Local Site
    127.0.0.1 site.local www.site.local #Local Site
    ## Local - End ##
    """

    func testParsesEntriesGroupsAndRoundTrips() {
        let file = HostsFile(parsing: sample)
        XCTAssertEqual(file.text, sample + "\n", "Untouched files are written back byte for byte")
        XCTAssertEqual(file.entries.count, 7)
        let disabled = file.entries.first { $0.hostnames == ["ads.example.com"] }
        XCTAssertEqual(disabled?.isEnabled, false)
        XCTAssertEqual(disabled?.comment, "blocked")
        XCTAssertEqual(file.groups.map(\.name), [nil, "Local"])
        XCTAssertEqual(file.groups[1].entries.count, 2)
        XCTAssertEqual(file.groups[1].entries[1].hostnames, ["site.local", "www.site.local"])
        XCTAssertFalse(file.entries.contains { $0.hostnames.contains("Host") }, "Heading comments aren't entries")
        XCTAssertEqual(file.entries.filter(\.isBlock).map(\.hostnames), [["ads.example.com"]], "Loopback dev sites aren't blocks")
    }

    func testToggleKeepsSystemEntries() throws {
        var file = HostsFile(parsing: sample)
        file.setGroupEnabled(nil, false)
        XCTAssertTrue(file.entries.filter(\.isSystem).allSatisfy(\.isEnabled))
        XCTAssertTrue(file.text.contains("# 10.0.0.28\terp.internal"))
        file.setGroupEnabled("Local", false)
        XCTAssertFalse(file.groups[1].anyEnabled)
        let reparsed = HostsFile(parsing: file.text)
        XCTAssertEqual(reparsed.entries.filter(\.isEnabled).count, 3, "Only the three system lines stay on")
        let localhost = try XCTUnwrap(file.entries.first(where: \.isSystem))
        file.remove(localhost.id)
        XCTAssertEqual(file.entries.filter(\.isSystem).count, 3)
    }

    func testAddValidatesAndPlacesEntries() throws {
        var file = HostsFile(parsing: sample)
        XCTAssertThrowsError(try file.add(address: "999.1.1.1", hostnames: "x.com"))
        XCTAssertThrowsError(try file.add(address: "0.0.0.0", hostnames: "bad host!"))
        XCTAssertThrowsError(try file.add(address: "0.0.0.0", hostnames: "  "))
        XCTAssertThrowsError(try file.add(address: "0.0.0.0", hostnames: "x.com", group: "a\"; rm"))

        try file.add(address: "0.0.0.0", hostnames: "tracker.example, ads2.example", comment: "no # hash")
        try file.add(address: "192.168.1.5", hostnames: "nas.local", group: "Local")
        try file.add(address: "fe80::1%lo0", hostnames: "link.local", group: "Work")
        let reparsed = HostsFile(parsing: file.text)
        XCTAssertEqual(reparsed.groups.map(\.name), [nil, "Local", "Work"])
        XCTAssertEqual(reparsed.groups[0].entries.last?.hostnames, ["tracker.example", "ads2.example"])
        XCTAssertEqual(reparsed.groups[0].entries.last?.comment, "no hash")
        XCTAssertEqual(reparsed.groups[1].entries.last?.address, "192.168.1.5")
        XCTAssertTrue(file.text.hasSuffix("\n\n## Work - Start ##\nfe80::1%lo0\tlink.local\n## Work - End ##\n"))
    }

    func testWriterCommandRejectsUnsafePaths() throws {
        XCTAssertThrowsError(try HostsWriter.command(source: "/tmp/a b"))
        XCTAssertThrowsError(try HostsWriter.command(source: "/tmp/a;rm"))
        XCTAssertTrue(try HostsWriter.command(source: "/var/folders/x/T/macpocket-hosts-1.txt").contains("> /etc/hosts"))
    }
}

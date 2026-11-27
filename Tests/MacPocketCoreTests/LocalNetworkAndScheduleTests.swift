import XCTest
@testable import MacPocketCore

final class LocalNetworkTests: XCTestCase {
    func testBonjourDiscoversDevicesWithoutPingOrARPAndKeepsExistingDetails() {
        let network = LANNetworkInfo(interface: "en1", address: "192.168.0.45",
                                     subnet: LANSubnet.parse(cidr: "192.168.0.0/24")!, gateway: nil)
        var existing = LANDevice(ip: "192.168.0.10", mac: "00:1B:21:BC:4C:D3")
        existing.latency = 0.012
        existing.isGateway = true
        var devices = [existing.ip: existing]
        let services: [LANScanner.BonjourService] = [
            .init(name: "Printer", type: "_ipp._tcp", ip: "192.168.0.20", model: "Printer Model"),
            .init(name: "Music", type: "_raop._tcp", ip: existing.ip, model: nil),
            .init(name: "My Mac", type: "_companion-link._tcp", ip: existing.ip, model: nil),
            .init(name: "Other Network", type: "_http._tcp", ip: "10.0.0.20", model: nil),
        ]
        LANScanner.mergeBonjour(services, models: ["My Mac": "Mac16,9"], network: network, into: &devices)

        XCTAssertEqual(devices.count, 2, "Services outside this subnet must not leak into its results")
        XCTAssertEqual(devices["192.168.0.20"]?.displayName, "Printer")
        XCTAssertEqual(devices["192.168.0.20"]?.kind, .printer)
        XCTAssertEqual(devices["192.168.0.20"]?.model, "Printer Model")
        XCTAssertNil(devices["192.168.0.20"]?.latency, "Bonjour discovery must not invent an ICMP response")
        XCTAssertEqual(devices[existing.ip]?.mac, existing.mac)
        XCTAssertEqual(devices[existing.ip]?.latency, existing.latency)
        XCTAssertEqual(devices[existing.ip]?.isGateway, true)
        XCTAssertEqual(devices[existing.ip]?.displayName, "My Mac")
        XCTAssertEqual(devices[existing.ip]?.model, "Mac16,9")
        XCTAssertEqual(devices[existing.ip]?.services, ["_raop._tcp", "_companion-link._tcp"])

        var routedDevices: [String: LANDevice] = [:]
        var routed = network
        routed.isLocal = false
        LANScanner.mergeBonjour(services, models: [:], network: routed, into: &routedDevices)
        XCTAssertTrue(routedDevices.isEmpty, "Local Bonjour results must not populate routed ranges")
    }

    func testSubnetHostsSkipNetworkBroadcastAndSelf() {
        let subnet = LANSubnet(address: IPv4.parse("192.168.0.45")!, mask: IPv4.parse("255.255.255.0")!)
        XCTAssertEqual(subnet.description, "192.168.0.0/24")
        XCTAssertEqual(subnet.hosts.count, 253, "254 usable minus this Mac")
        XCTAssertFalse(subnet.hosts.contains(IPv4.parse("192.168.0.45")!))
        XCTAssertEqual(IPv4.text(subnet.hosts.first!), "192.168.0.1")
        XCTAssertEqual(IPv4.text(subnet.hosts.last!), "192.168.0.254")
        let huge = LANSubnet(address: IPv4.parse("10.20.30.40")!, mask: IPv4.parse("255.0.0.0")!)
        XCTAssertEqual(huge.description, "10.20.30.0/24", "Huge networks are narrowed to the local /24")
        let medium = LANSubnet(address: IPv4.parse("10.0.1.5")!, mask: IPv4.parse("255.255.252.0")!)
        XCTAssertEqual(medium.hosts.count, 1021)
        XCTAssertNil(IPv4.parse("300.1.1.1"))
    }

    func testMACNormalizationAndPrivateAddresses() {
        XCTAssertEqual(MACAddress.normalize("0:1b:21:bc:4c:d3"), "00:1B:21:BC:4C:D3")
        XCTAssertNil(MACAddress.normalize("(incomplete)"))
        XCTAssertTrue(MACAddress.isPrivate("B2:74:93:D3:F3:53"))
        XCTAssertFalse(MACAddress.isPrivate("00:1B:21:BC:4C:D3"))
        XCTAssertTrue(MACAddress.isMulticastOrBroadcast("FF:FF:FF:FF:FF:FF"))
        XCTAssertTrue(MACAddress.isMulticastOrBroadcast("01:00:5E:00:00:FB"))
    }

    func testARPTableParsing() {
        let output = """
        ? (192.168.0.1) at 0:1b:21:bc:4c:d3 on en1 ifscope [ethernet]
        ? (192.168.0.25) at b2:74:93:d3:f3:53 on en1 ifscope [ethernet]
        ? (192.168.0.77) at (incomplete) on en1 ifscope [ethernet]
        ? (192.168.0.255) at ff:ff:ff:ff:ff:ff on en1 ifscope [ethernet]
        ? (169.254.134.7) at 92:b0:ed:7d:d0:9 on en9 [ethernet]
        """
        let entries = ARPTable.parse(output)
        XCTAssertEqual(entries.map(\.ip), ["192.168.0.1", "192.168.0.25", "169.254.134.7"])
        XCTAssertEqual(entries.first?.mac, "00:1B:21:BC:4C:D3")
        XCTAssertEqual(entries.last?.interface, "en9")
    }

    func testICMPEchoChecksumAndReplyParsing() {
        let request = ICMPEcho.request(identifier: 0x1234, sequence: 7)
        XCTAssertEqual(request[0], 8)
        XCTAssertEqual(ICMPEcho.checksum(request), 0, "A packet with a valid checksum sums to zero")
        var reply = request
        reply[0] = 0
        let ipHeader: [UInt8] = [0x45] + [UInt8](repeating: 0, count: 19)
        XCTAssertEqual(ICMPEcho.reply(ipHeader + reply)?.identifier, 0x1234)
        XCTAssertEqual(ICMPEcho.reply(ipHeader + reply)?.sequence, 7)
        XCTAssertEqual(ICMPEcho.reply(reply)?.sequence, 7, "Also without an IP header")
        XCTAssertNil(ICMPEcho.reply(ipHeader + request), "Requests are not replies")
    }

    func testDeviceKindInference() {
        XCTAssertEqual(LANDeviceKind.infer(services: ["_ipp._tcp", "_http._tcp"], model: nil), .printer)
        XCTAssertEqual(LANDeviceKind.infer(services: ["_googlecast._tcp"], model: nil), .tv)
        XCTAssertEqual(LANDeviceKind.infer(services: ["_raop._tcp"], model: nil), .speaker)
        XCTAssertEqual(LANDeviceKind.infer(services: ["_hap._tcp"], model: nil), .smartHome)
        XCTAssertEqual(LANDeviceKind.infer(services: ["_companion-link._tcp", "_raop._tcp"], model: nil, name: "Alex’s Mac Studio"), .computer,
                       "A Mac offering AirPlay is still a computer")
        XCTAssertEqual(LANDeviceKind.infer(services: ["_companion-link._tcp"], model: nil, name: "Alex’s iPhone"), .appleDevice)
        XCTAssertEqual(LANDeviceKind.infer(services: ["_raop._tcp"], model: "AudioAccessory5,1"), .speaker)
        XCTAssertEqual(LANDeviceKind.infer(services: [], model: "Mac16,9"), .computer)
        XCTAssertEqual(LANDeviceKind.infer(services: [], model: nil), .unknown)
        var router = LANDevice(ip: "192.168.0.1")
        router.isGateway = true
        XCTAssertEqual(router.kind, .router)
    }

    func testKnownDevicesBaselineNewcomersAndNames() {
        var known = LANKnownDevices()
        let first = [LANDevice(ip: "192.168.0.2", mac: "AA:AA:AA:AA:AA:01"), LANDevice(ip: "192.168.0.3", mac: "AA:AA:AA:AA:AA:02")]
        XCTAssertTrue(known.update(with: first).isEmpty, "The first scan is the baseline")
        let second = first + [LANDevice(ip: "192.168.0.9", mac: "AA:AA:AA:AA:AA:09"), LANDevice(ip: "192.168.0.10")]
        XCTAssertEqual(known.update(with: second), ["AA:AA:AA:AA:AA:09"])
        known.rename("AA:AA:AA:AA:AA:01", to: "  Salon TV ")
        XCTAssertEqual(known.name(for: "AA:AA:AA:AA:AA:01"), "Salon TV")
        known.rename("AA:AA:AA:AA:AA:01", to: "   ")
        XCTAssertNil(known.name(for: "AA:AA:AA:AA:AA:01"))
        known.forget("AA:AA:AA:AA:AA:09")
        XCTAssertNil(known.records["AA:AA:AA:AA:AA:09"])
    }
}

final class PowerScheduleTests: XCTestCase {
    func testWeekdaysMatchIOKitBitsAndPmsetLetters() {
        XCTAssertEqual(PowerWeekdays.monday.rawValue, 1)
        XCTAssertEqual(PowerWeekdays.sunday.rawValue, 64)
        XCTAssertEqual(PowerWeekdays.weekdays.pmsetLetters, "MTWRF")
        XCTAssertEqual(PowerWeekdays.everyDay.pmsetLetters, "MTWRFSU")
        XCTAssertEqual(([.tuesday, .saturday] as PowerWeekdays).pmsetLetters, "TS")
        XCTAssertEqual(PowerWeekdays.weekend.summary, "hafta sonu")
    }

    func testSnapshotParsesIOKitAndHidesSystemTimers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = PowerScheduleSnapshot(
            repeating: ["RepeatingPowerOn": ["eventtype": "wakepoweron", "time": 480, "weekdays": 31],
                        "RepeatingPowerOff": ["eventtype": "shutdown", "time": 1410, "weekdays": 127]],
            scheduled: [["eventtype": "wake", "time": now.addingTimeInterval(3600), "scheduledby": "MacPocket"],
                        ["eventtype": "wake", "time": now.addingTimeInterval(60), "scheduledby": "com.apple.alarm.user-invisible-x", "UserVisible": false],
                        ["eventtype": "sleep", "time": now.addingTimeInterval(-60), "scheduledby": "pmset"]],
            now: now)
        XCTAssertEqual(snapshot.powerOn, RepeatingPowerEvent(kind: .wakeOrPowerOn, minutes: 480, days: .weekdays))
        XCTAssertEqual(snapshot.powerOff?.kind, .shutdown)
        XCTAssertEqual(snapshot.powerOff?.timeText, "23:30")
        XCTAssertEqual(snapshot.scheduled.map(\.owner), ["MacPocket"], "Invisible and past events are left out")
        XCTAssertEqual(PowerScheduleSnapshot(repeating: nil, scheduled: nil), PowerScheduleSnapshot())
    }

    func testCommandsAreBuiltFromFixedWords() {
        let on = RepeatingPowerEvent(kind: .wakeOrPowerOn, minutes: 8 * 60, days: .weekdays)
        let off = RepeatingPowerEvent(kind: .sleep, minutes: 23 * 60 + 5, days: .everyDay)
        XCTAssertEqual(PowerScheduleCommand.repeating(on: on, off: off),
                       "/usr/bin/pmset repeat cancel && /usr/bin/pmset repeat wakeorpoweron MTWRF 08:00:00 sleep MTWRFSU 23:05:00")
        XCTAssertEqual(PowerScheduleCommand.repeating(on: nil, off: nil), "/usr/bin/pmset repeat cancel")
        XCTAssertEqual(PowerScheduleCommand.repeating(on: RepeatingPowerEvent(kind: .wake, minutes: 0, days: []), off: nil),
                       "/usr/bin/pmset repeat cancel", "An event with no days is dropped")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 7, minute: 30))!
        let schedule = PowerScheduleCommand.schedule(.wake, at: date)
        XCTAssertEqual(schedule, "/usr/bin/pmset schedule wake '11/05/26 07:30:00' MacPocket")
        XCTAssertFalse(schedule.contains("\""))
        XCTAssertEqual(PowerScheduleCommand.cancel(ScheduledPowerEvent(kind: .wake, date: date, owner: "MacPocket")),
                       "/usr/bin/pmset schedule cancel wake '11/05/26 07:30:00' MacPocket")
        XCTAssertEqual(PowerScheduleCommand.cancel(ScheduledPowerEvent(kind: .sleep, date: date, owner: "it's; rm")),
                       "/usr/bin/pmset schedule cancel sleep '11/05/26 07:30:00'", "Unsafe owners are left out of the command")
    }
}

final class LocalNetworkDetailTests: XCTestCase {
    func testMACLookupJSONFiltersPrivateAndCIDAndMergesWithIEEE() throws {
        let json = #"""
        [
          {"macPrefix":"00:1B:21","vendorName":"New Vendor","private":false,"blockType":"MA-L"},
          {"macPrefix":"00:1B:21:A","vendorName":"Specific Vendor","private":false,"blockType":"MA-M"},
          {"macPrefix":"00:1B:21:AB:C","vendorName":"Device Vendor","private":false,"blockType":"MA-S"},
          {"macPrefix":"00:1B:21:AB:C","vendorName":"","private":true,"blockType":""},
          {"macPrefix":"00:1B:21:AB:D","vendorName":"Hidden","private":true,"blockType":"MA-S"},
          {"macPrefix":"00:1B:21","vendorName":"CID Vendor","private":false,"blockType":"CID"},
          {"macPrefix":"garbage","vendorName":"Invalid","private":false,"blockType":"MA-M"}
        ]
        """#
        let database = try OUIDatabase(macLookupJSON: Data(json.utf8))
        XCTAssertEqual(database.count, 3)
        XCTAssertEqual(database.vendor(for: "00:1b:21:ab:c0:00"), "Device Vendor")
        XCTAssertEqual(database.vendor(for: "00:1B:21:A0:00:00"), "Specific Vendor")
        XCTAssertEqual(database.vendor(for: "0:1b:21:0:0:0"), "New Vendor", "Normalize the full MAC before lookup")
        XCTAssertNil(database.vendor(for: "00:1B:21"), "A prefix is not a device MAC address")
        XCTAssertThrowsError(try OUIDatabase(macLookupJSON: Data("invalid".utf8)))
        let ieee = OUIDatabase(tsv: "001B21\tOlder Vendor\nC049EF\tEspressif Inc.\n")
        let merged = ieee.merging(database)
        XCTAssertEqual(merged.vendor(for: "00:1B:21:00:00:01"), "New Vendor")
        XCTAssertEqual(merged.vendor(for: "C0:49:EF:00:00:01"), "Espressif", "Keep IEEE prefixes absent from MACLookup")
    }

    func testBundledMACLookupSnapshotAndBundleLoading() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources")
        let data = try (Data(contentsOf: resources.appendingPathComponent("maclookup.json.lzfse")) as NSData).decompressed(using: .lzfse) as Data
        let database = try OUIDatabase(macLookupJSON: data)
        XCTAssertGreaterThan(database.count, 50_000)
        XCTAssertEqual(database.vendor(for: "00:00:0C:00:00:01"), "Cisco Systems")
        XCTAssertNil(database.vendor(for: "02:00:0C:00:00:01"), "Private MACs must not be attributed to a manufacturer")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: resources.appendingPathComponent("maclookup.json.lzfse"),
                                        to: directory.appendingPathComponent("maclookup.json.lzfse"))
        try FileManager.default.copyItem(at: resources.appendingPathComponent("oui.tsv.lzfse"),
                                        to: directory.appendingPathComponent("oui.tsv.lzfse"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        XCTAssertEqual(OUIDatabase.bundled(in: bundle)?.vendor(for: "00:00:0C:00:00:01"), "Cisco Systems")
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("maclookup.json.lzfse"))
        XCTAssertEqual(OUIDatabase.bundled(in: bundle)?.vendor(for: "00:1B:21:00:00:01"), "Intel Corporate", "Corrupt supplement must fall back to IEEE")
    }

    func testManufacturerLookupPrefersTheLongestPrefix() {
        let database = OUIDatabase(tsv: "001B21\tIntel Corporate\nC049EF\tEspressif Inc.\n70B3D5\tIEEE Registration Authority\n70B3D5700\tUniversity Of Groningen\nC85CE27\tSan Telequip (P) Ltd.,\n")
        XCTAssertEqual(database.count, 5)
        XCTAssertEqual(database.vendor(for: "00:1B:21:BC:4C:D3"), "Intel Corporate")
        XCTAssertEqual(database.vendor(for: "C0:49:EF:1E:6E:00"), "Espressif")
        XCTAssertEqual(database.vendor(for: "70:B3:D5:70:01:23"), "University Of Groningen", "36-bit block beats the 24-bit one")
        XCTAssertEqual(database.vendor(for: "70:B3:D5:12:34:56"), "IEEE Registration Authority")
        XCTAssertEqual(database.vendor(for: "C8:5C:E2:71:00:00"), "San Telequip (P)", "28-bit block")
        XCTAssertNil(database.vendor(for: "B2:74:93:D3:F3:53"), "Private addresses have no manufacturer")
        XCTAssertNil(database.vendor(for: "AA:00:00:00:00:00"))
        XCTAssertEqual(LANDeviceKind.infer(vendor: "Espressif"), .smartHome)
        XCTAssertEqual(LANDeviceKind.infer(vendor: "Seiko Epson"), .printer)
        XCTAssertNil(LANDeviceKind.infer(vendor: "Acme"))
    }

    func testBundledTableShipsWithTheRepository() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/oui.tsv.lzfse")
        let data = try (Data(contentsOf: url) as NSData).decompressed(using: .lzfse) as Data
        let database = OUIDatabase(tsv: String(decoding: data, as: UTF8.self))
        XCTAssertGreaterThan(database.count, 50_000)
        XCTAssertEqual(database.vendor(for: "00:1B:21:00:00:01"), "Intel Corporate")
    }

    func testWebTitlePingStatisticsAndMagicPacket() {
        XCTAssertEqual(LANPortScanner.title(in: "<html><head><TITLE>\n  Router &amp; Modem </title>"), "Router & Modem")
        XCTAssertNil(LANPortScanner.title(in: "<html><body>no title</body>"))

        let stats = PingStatistics(samples: [0.010, nil, 0.020, 0.030])
        XCTAssertEqual(stats.sent, 4)
        XCTAssertEqual(stats.received, 3)
        XCTAssertEqual(stats.lossPercent, 25)
        XCTAssertEqual(stats.average!, 0.020, accuracy: 0.0001)
        XCTAssertEqual(stats.jitter!, 0.010, accuracy: 0.0001)
        XCTAssertNil(PingStatistics(samples: [nil]).average)

        let packet = WakeOnLAN.magicPacket(for: "00:1B:21:BC:4C:D3")
        XCTAssertEqual(packet?.count, 102)
        XCTAssertEqual(packet?.prefix(6), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(packet![96...]), [0x00, 0x1B, 0x21, 0xBC, 0x4C, 0xD3])
        XCTAssertNil(WakeOnLAN.magicPacket(for: "nope"))
        XCTAssertTrue(LANPort.common.contains { $0.number == 23 && $0.risk != nil }, "Telnet is flagged")
        XCTAssertEqual(Set(LANPort.common.map(\.number)).count, LANPort.common.count)
    }
}

final class MultiNetworkTests: XCTestCase {
    func testCustomRangesParseAndStayBounded() {
        XCTAssertEqual(LANSubnet.parse(cidr: "10.0.20.0/24")?.description, "10.0.20.0/24")
        XCTAssertEqual(LANSubnet.parse(cidr: " 10.0.20.77/24 ")?.description, "10.0.20.0/24", "Host bits are cleared")
        XCTAssertEqual(LANSubnet.parse(cidr: "172.16.0.0/22")?.hosts.count, 1022)
        XCTAssertNil(LANSubnet.parse(cidr: "10.0.0.0/16"), "Wider than /22 is refused")
        XCTAssertNil(LANSubnet.parse(cidr: "10.0.20.0"))
        XCTAssertNil(LANSubnet.parse(cidr: "nonsense/24"))
    }

    func testCustomNetworkReusesAnAttachedNetworkAndMarksRoutedOnes() {
        let wifi = LANNetworkInfo(interface: "en1", address: "192.168.0.45",
                                  subnet: LANSubnet(address: IPv4.parse("192.168.0.45")!, mask: IPv4.parse("255.255.255.0")!),
                                  gateway: "192.168.0.1", name: "Wi-Fi", kind: .wifi, isLocal: true, isPrimary: true)
        let same = LANScanner.customNetwork(LANSubnet.parse(cidr: "192.168.0.0/24")!, name: "Ev", attached: [wifi])
        XCTAssertEqual(same, wifi, "A range that is an attached network keeps its MAC and Bonjour details")
        let routed = LANScanner.customNetwork(LANSubnet.parse(cidr: "192.168.2.0/24")!, name: "", attached: [wifi])
        XCTAssertFalse(routed.isLocal)
        XCTAssertEqual(routed.kind, .custom)
        XCTAssertEqual(routed.name, "192.168.2.0/24", "Unnamed ranges use their CIDR")
        XCTAssertTrue(routed.contains("192.168.2.51"))
        XCTAssertFalse(routed.contains("192.168.0.51"))
        XCTAssertNotEqual(routed.id, wifi.id)
    }
}

final class NetBIOSTests: XCTestCase {
    func testStatusQueryEncodesTheWildcardName() {
        let query = NetBIOS.statusQuery(transaction: 0xBEEF)
        XCTAssertEqual(query.count, 50)
        XCTAssertEqual(Array(query.prefix(2)), [0xBE, 0xEF])
        XCTAssertEqual(query[12], 0x20)
        XCTAssertEqual(Array(query[13...14]), [0x43, 0x4B], "'*' encodes as \"CK\"")
        XCTAssertEqual(Array(query.suffix(4)), [0x00, 0x21, 0x00, 0x01], "NBSTAT, class IN")
    }

    func testStatusReplyYieldsNameWorkgroupAndMAC() {
        func entry(_ name: String, suffix: UInt8, group: Bool) -> [UInt8] {
            let padded = Array((Array(name.utf8) + [UInt8](repeating: 0x20, count: 15)).prefix(15))
            return padded + [suffix, group ? 0x84 : 0x04, 0x00]
        }
        var reply: [UInt8] = [0xBE, 0xEF, 0x84, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]
        reply += [0x20] + [UInt8](repeating: 0x41, count: 32) + [0x00]
        reply += [0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0]
        let names = entry("ALEX-PC", suffix: 0x00, group: false) + entry("WORKGROUP", suffix: 0x00, group: true)
            + entry("ALEX-PC", suffix: 0x20, group: false)
        let body = [UInt8(3)] + names + [0xE4, 0xFD, 0x45, 0x23, 0xE0, 0x8D] + [UInt8](repeating: 0, count: 10)
        reply += [UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body
        let status = NetBIOS.parseStatus(reply)
        XCTAssertEqual(status?.name, "ALEX-PC")
        XCTAssertEqual(status?.workgroup, "WORKGROUP")
        XCTAssertEqual(status?.mac, "E4:FD:45:23:E0:8D")
        XCTAssertNil(NetBIOS.parseStatus(Array(reply.prefix(20))))
        var request = reply
        request[2] = 0x00
        XCTAssertNil(NetBIOS.parseStatus(request), "Queries are not replies")
    }

    func testNetBIOSNameNamesAndClassifiesTheDevice() {
        var device = LANDevice(ip: "192.168.0.219")
        device.hostName = "host.lan."
        device.netbiosName = "ALEX-PC"
        XCTAssertEqual(device.displayName, "ALEX-PC")
        XCTAssertEqual(device.kind, .computer)
    }
}

final class SNMPTests: XCTestCase {
    func testTargetIPMappingAndVerifiedMACOverrideAnUnrelatedInterface() {
        XCTAssertEqual(SNMP.interfaceIndexOIDs(for: "192.168.2.11"), [
            [1, 3, 6, 1, 2, 1, 4, 20, 1, 2, 192, 168, 2, 11],
            [1, 3, 6, 1, 2, 1, 4, 34, 1, 3, 1, 4, 192, 168, 2, 11],
        ])
        XCTAssertTrue(SNMP.interfaceIndexOIDs(for: "invalid").isEmpty)
        XCTAssertEqual(SNMP.positiveInteger([0, 128]), 128)
        XCTAssertNil(SNMP.positiveInteger([0]))
        XCTAssertNil(SNMP.positiveInteger([0xFF]))
        var info = SNMP.Info()
        SNMP.applyMAC([0x2C, 0xC8, 0x1B, 0, 0, 1], matchingIP: false, to: &info)
        XCTAssertFalse(info.macMatchesIP)
        SNMP.applyMAC([0x2C, 0xC8, 0x1B, 0, 0, 9], matchingIP: true, to: &info)
        XCTAssertEqual(info.mac, "2C:C8:1B:00:00:09")
        XCTAssertTrue(info.macMatchesIP)
        SNMP.applyMAC([0x2C, 0xC8, 0x1B, 0, 0, 2], matchingIP: false, to: &info)
        XCTAssertEqual(info.mac, "2C:C8:1B:00:00:09", "An unrelated interface must not replace an IP-matched address")
        SNMP.applyMAC([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], matchingIP: true, to: &info)
        SNMP.applyMAC([0, 0, 0, 0, 0, 0], matchingIP: true, to: &info)
        XCTAssertEqual(info.mac, "2C:C8:1B:00:00:09")
    }

    func testRequestEncodesVersionCommunityAndOIDs() {
        let packet = SNMP.request(id: 1, next: false, oids: [[1, 3, 6, 1, 2, 1, 1, 5, 0]])
        XCTAssertEqual(packet.map { String(format: "%02x", $0) }.joined(),
                       "302602010104067075626c6963a01902010102010002010030" + "0e300c06082b060102010105000500")
        XCTAssertEqual(SNMP.request(id: 2, next: true, oids: [[1, 3, 6, 1, 2, 1, 2, 2, 1, 6]])[13], 0xA1, "GetNext PDU")
        XCTAssertEqual(SNMP.oid([1, 3, 6, 1, 4, 1, 14988]), [0x06, 0x07, 0x2B, 0x06, 0x01, 0x04, 0x01, 0xF5, 0x0C],
                       "Arcs above 127 use base-128 continuation bytes")
    }

    func testResponseDecodesStringsAndHardwareAddresses() {
        func binding(_ oid: [Int], _ tag: UInt8, _ value: [UInt8]) -> [UInt8] { SNMP.tlv(0x30, SNMP.oid(oid) + SNMP.tlv(tag, value)) }
        let bindings = binding([1, 3, 6, 1, 2, 1, 1, 5, 0], 0x04, Array("MikroTik".utf8))
            + binding([1, 3, 6, 1, 2, 1, 2, 2, 1, 6, 1], 0x04, [0x2C, 0xC8, 0x1B, 0xB6, 0xFD, 0x09])
        let pdu = SNMP.tlv(0xA2, SNMP.integer(77) + SNMP.integer(0) + SNMP.integer(0) + SNMP.tlv(0x30, bindings))
        let message = SNMP.tlv(0x30, SNMP.integer(1) + SNMP.tlv(0x04, Array("public".utf8)) + pdu)
        let reply = SNMP.response(message)
        XCTAssertEqual(reply?.id, 77)
        XCTAssertEqual(reply?.bindings.count, 2)
        XCTAssertEqual(reply?.bindings.first?.0, [1, 3, 6, 1, 2, 1, 1, 5, 0])
        XCTAssertEqual(reply.map { String(decoding: $0.bindings[0].2, as: UTF8.self) }, "MikroTik")
        XCTAssertEqual(reply?.bindings.last?.2, [0x2C, 0xC8, 0x1B, 0xB6, 0xFD, 0x09])
        XCTAssertNil(SNMP.response(Array(message.prefix(10))))
        XCTAssertEqual(SNMP.length(300), [0x82, 0x01, 0x2C], "Long-form lengths")
    }

    func testSNMPDescriptionClassifiesNetworkGear() {
        var device = LANDevice(ip: "192.168.2.11")
        device.snmpName = "MikroTik"
        device.snmpDescription = "MikroTik CRS317-1G-16S+ SwOS v2.18"
        XCTAssertEqual(device.displayName, "MikroTik")
        XCTAssertEqual(device.kind, .router)
    }
}

final class OnLinkProbeTests: XCTestCase {
    func testARPAddsHostsMissingFromRoutedScanAndOverridesInterfaceHints() throws {
        let subnet = try XCTUnwrap(LANSubnet.parse(cidr: "192.168.2.0/24"))
        var network = LANNetworkInfo(interface: "", address: "192.168.0.45", subnet: subnet, gateway: nil, isLocal: false)
        network.viaInterface = "en1"
        var switchDevice = LANDevice(ip: "192.168.2.11", mac: "00:1B:21:00:00:01")
        switchDevice.snmpName = "MikroTik"
        switchDevice.macSource = .snmpInterface
        switchDevice.latency = 0.010
        let scan = LANScanResult(network: network, devices: [switchDevice], date: .distantPast)
        let merged = scan.mergingARP([
            ARPEntry(ip: "192.168.2.12", mac: "3C:52:A1:3E:DA:A8", interface: "en1"),
            ARPEntry(ip: "192.168.2.11", mac: "2C:C8:1B:B6:FD:09", interface: "en1"),
            ARPEntry(ip: "192.168.2.9", mac: "00:1B:21:00:00:02", interface: "en9"),
            ARPEntry(ip: "192.168.0.1", mac: "00:1B:21:00:00:03", interface: "en1"),
        ])
        XCTAssertEqual(merged.devices.map(\.ip), ["192.168.2.11", "192.168.2.12"])
        XCTAssertEqual(merged.devices.first?.mac, "2C:C8:1B:B6:FD:09")
        XCTAssertEqual(merged.devices.first?.macSource, .arp)
        XCTAssertEqual(merged.devices.first?.snmpName, "MikroTik")
        XCTAssertEqual(merged.devices.first?.latency, 0.010)
        XCTAssertNil(merged.devices.last?.latency, "A direct ARP reply is not a measured ICMP response")
    }

    func testOnlyRequestedHostsOnTheProbedInterfaceAreAccepted() throws {
        let subnet = try XCTUnwrap(LANSubnet.parse(cidr: "192.168.2.0/24"))
        let entries = LANOnLinkProbe.entries(in: """
        ? (192.168.2.8) at 0:1b:21:0:0:1 on en9 ifscope [ethernet]
        ? (192.168.2.8) at 0:1b:21:0:0:2 on en1 ifscope [ethernet]
        ? (192.168.2.9) at 0:1b:21:0:0:3 on en1 ifscope [ethernet]
        ? (192.168.0.1) at 0:1b:21:0:0:4 on en1 ifscope [ethernet]
        """, subnet: subnet, interface: "en1", hosts: ["192.168.2.8", "192.168.0.1"])
        XCTAssertEqual(entries, [ARPEntry(ip: "192.168.2.8", mac: "00:1B:21:00:00:02", interface: "en1")])
    }

    func testCommandIsBuiltOnlyFromValidatedParts() throws {
        let subnet = try XCTUnwrap(LANSubnet.parse(cidr: "192.168.2.0/24"))
        let command = try XCTUnwrap(LANOnLinkProbe.command(subnet: subnet, interface: "en1", hosts: ["192.168.2.8", "192.168.0.5", "nope"]))
        XCTAssertTrue(command.hasPrefix("/sbin/route -n add -net 192.168.2.0/24 -interface en1"))
        XCTAssertTrue(command.contains("/sbin/ping -c 1 -t 1 192.168.2.8"))
        XCTAssertFalse(command.contains("192.168.0.5"), "Hosts outside the range are dropped")
        XCTAssertTrue(command.contains("trap '/sbin/route -n delete -net 192.168.2.0/24 -interface en1 >/dev/null 2>&1' EXIT"))
        XCTAssertFalse(command.contains("\""))
        XCTAssertNil(LANOnLinkProbe.command(subnet: subnet, interface: "en1; rm", hosts: ["192.168.2.8"]))
        XCTAssertNil(LANOnLinkProbe.command(subnet: subnet, interface: "en1", hosts: ["10.0.0.1"]))
    }

    func testRouteOwnershipAndCleanupOnSuccessFailureAndSignal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("route.log")
        let subnet = try XCTUnwrap(LANSubnet.parse(cidr: "192.168.2.0/24"))
        let command = try XCTUnwrap(LANOnLinkProbe.command(subnet: subnet, interface: "en1", hosts: ["192.168.2.8"]))

        // Replace all system tools: exercise the actual shell control flow without networking or
        // administrator access.
        for (addStatus, arpCommand, expectedStatus, expectedLog) in [
            (17, "printf arp-result", 17, "add "),
            (0, "printf arp-result", 0, "add delete "),
            (0, "exit 9", 9, "add delete "),
            (0, "kill -TERM $$", 1, "add delete "),
        ] {
            try Data().write(to: log)
            let quotedLog = "'" + log.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let stub = "route_stub() { printf '%s ' $2 >> \(quotedLog); if [ $2 = add ]; then return \(addStatus); fi; return 0; }; "
            let script = stub + command
                .replacingOccurrences(of: "/sbin/route", with: "route_stub")
                .replacingOccurrences(of: "/sbin/ping", with: ":")
                .replacingOccurrences(of: "sleep 2", with: ":")
                .replacingOccurrences(of: "/usr/sbin/arp -an", with: arpCommand)
            let result = try await BoundedProcess.run("/bin/sh", ["-c", script], timeout: 5)
            XCTAssertEqual(result.status, Int32(expectedStatus))
            XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), expectedLog)
            if addStatus != 0 { XCTAssertTrue(result.output.isEmpty, "Do not probe when the route could not be added") }
            if expectedStatus == 0 { XCTAssertEqual(result.output, "arp-result") }
        }
    }
}

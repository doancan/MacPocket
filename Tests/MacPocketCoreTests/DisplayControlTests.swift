import XCTest
@testable import MacPocketCore

final class DDCPacketTests: XCTestCase {
    func testGetRequestMatchesTheDDCCIExample() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        XCTAssertEqual(DDCPacket.getRequest(.brightness), [0x82, 0x01, 0x10, 0xAC])
    }

    func testSetRequestCarriesTheValueBigEndian() {
        // Brightness 50 (0x0032): 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        XCTAssertEqual(DDCPacket.setRequest(.brightness, value: 50), [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        XCTAssertEqual(DDCPacket.setRequest(.contrast, value: 0x0150)[3...4], [0x01, 0x50])
    }

    private func reply(code: UInt8 = 0x10, result: UInt8 = 0, maximum: UInt16 = 100, current: UInt16 = 70) -> [UInt8] {
        var bytes: [UInt8] = [0x6E, 0x88, 0x02, result, code, 0x00, UInt8(maximum >> 8), UInt8(maximum & 0xFF),
                              UInt8(current >> 8), UInt8(current & 0xFF)]
        bytes.append(bytes.reduce(0x50, ^))
        return bytes + [0]
    }

    func testParsesAValidReply() throws {
        let value = try XCTUnwrap(DDCPacket.parseReply(reply(), expecting: .brightness))
        XCTAssertEqual(value.current, 70)
        XCTAssertEqual(value.maximum, 100)
    }

    func testRejectsNullMessagesErrorsWrongCodesAndBadChecksums() {
        // What an LG UltraGear+ with DDC/CI reads disabled returns: repeated null messages.
        XCTAssertNil(DDCPacket.parseReply([0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE], expecting: .brightness))
        XCTAssertNil(DDCPacket.parseReply(reply(result: 1), expecting: .brightness), "unsupported VCP code")
        XCTAssertNil(DDCPacket.parseReply(reply(code: 0x12), expecting: .brightness))
        var corrupted = reply()
        corrupted[9] ^= 0x01
        XCTAssertNil(DDCPacket.parseReply(corrupted, expecting: .brightness))
        XCTAssertNil(DDCPacket.parseReply(reply(maximum: 0, current: 0), expecting: .brightness))
    }

    func testCurrentIsClampedToMaximum() {
        XCTAssertEqual(DDCPacket.parseReply(reply(maximum: 100, current: 140), expecting: .brightness)?.current, 100)
    }
}

final class DisplayMatcherTests: XCTestCase {
    func testMatchesBySerialThenByModel() {
        let registry = [RegistryDisplay(vendor: 7789, product: 30732, serial: 311278, avServiceID: 10),
                        RegistryDisplay(vendor: 1552, product: 100, serial: 0, avServiceID: 20),
                        RegistryDisplay(vendor: 1552, product: 100, serial: 0, avServiceID: 30),
                        RegistryDisplay(vendor: 9, product: 9, serial: 9, avServiceID: nil)]
        let displays: [(id: CGDirectDisplayID, vendor: UInt32, product: UInt32, serial: UInt32)] =
            [(1, 1552, 100, 0), (2, 7789, 30732, 311278), (3, 1552, 100, 0), (4, 9, 9, 9)]
        let result = DisplayMatcher.match(displays, registry: registry)
        XCTAssertEqual(result[2], 10, "the LG matches by vendor, product and serial")
        XCTAssertEqual(Set([result[1], result[3]]), [20, 30], "identical serial-less monitors pair up in order")
        XCTAssertNil(result[4], "no DDC channel under that display")
    }
}

final class BrightnessStepTests: XCTestCase {
    func testStepsSnapToSixteenthsLikeTheBuiltInDisplay() {
        XCTAssertEqual(BrightnessStep.next(from: 0.5, up: true, step: BrightnessStep.normal), 0.5625)
        XCTAssertEqual(BrightnessStep.next(from: 0.53, up: true, step: BrightnessStep.normal), 0.5625, "an off-grid level snaps first")
        XCTAssertEqual(BrightnessStep.next(from: 1, up: true, step: BrightnessStep.normal), 1)
        XCTAssertEqual(BrightnessStep.next(from: 0.03, up: false, step: BrightnessStep.normal), 0)
        XCTAssertEqual(BrightnessStep.next(from: 0.5, up: false, step: BrightnessStep.fine), 0.484375)
    }

    func testChicletsCountSixtyFourths() {
        XCTAssertEqual(BrightnessStep.chiclets(0.5).filled, 32)
        XCTAssertEqual(BrightnessStep.chiclets(2).filled, 64)
        XCTAssertEqual(BrightnessStep.chiclets(0.5).total, 64)
    }
}

final class BrightnessScheduleTests: XCTestCase {
    private func schedule(_ points: [(Int, Double)]) -> BrightnessSchedule {
        var schedule = BrightnessSchedule()
        schedule.points = points.map { BrightnessSchedule.Point(minute: $0.0, level: $0.1) }
        return schedule
    }

    func testInterpolatesBetweenPoints() throws {
        let day = schedule([(8 * 60, 1), (20 * 60, 0.4)])
        XCTAssertEqual(try XCTUnwrap(day.level(at: 8 * 60)), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(day.level(at: 14 * 60)), 0.7, accuracy: 0.0001, "halfway between 08:00 and 20:00")
        XCTAssertEqual(try XCTUnwrap(day.level(at: 20 * 60)), 0.4, accuracy: 0.0001)
    }

    func testWrapsPastMidnight() throws {
        let day = schedule([(8 * 60, 1), (20 * 60, 0.4)])
        // 20:00 → 08:00 is 12 hours; 02:00 is halfway: 0.4 + 0.6 * 0.5.
        XCTAssertEqual(try XCTUnwrap(day.level(at: 2 * 60)), 0.7, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(day.level(at: 23 * 60)), 0.55, accuracy: 0.0001)
    }

    func testOrderOfPointsDoesNotMatterAndEdgeCases() throws {
        XCTAssertEqual(schedule([(20 * 60, 0.4), (8 * 60, 1)]).level(at: 14 * 60).map { ($0 * 1000).rounded() / 1000 }, 0.7)
        XCTAssertEqual(schedule([(600, 0.3)]).level(at: 0), 0.3)
        XCTAssertNil(schedule([]).level(at: 0))
        XCTAssertEqual(BrightnessSchedule.Point(minute: 5000, level: 7), BrightnessSchedule.Point(minute: 1439, level: 1))
    }

    func testOverrideLastsUntilTheNextPoint() {
        let day = schedule([(8 * 60, 1), (20 * 60, 0.4)])
        XCTAssertEqual(day.nextPoint(after: 9 * 60), 20 * 60)
        XCTAssertEqual(day.nextPoint(after: 21 * 60), 8 * 60, "wraps to tomorrow morning")
    }
}

final class BrightnessKeyTests: XCTestCase {
    func testDesktopMacsSendBrightnessAsOrdinaryKeys() {
        // Measured on a Mac with only external displays: Magic Keyboard F1/F2 arrive as key codes 145/144.
        XCTAssertEqual(BrightnessKey(keyCode: 145), .down)
        XCTAssertEqual(BrightnessKey(keyCode: 144), .up)
        XCTAssertNil(BrightnessKey(keyCode: 122), "F1 without the brightness function is not a brightness key")
    }

    func testLaptopsSendBrightnessAsSystemDefinedEvents() {
        XCTAssertEqual(BrightnessKey(systemDefinedSubtype: 8, data1: 0x0003_0A00), .down)
        XCTAssertEqual(BrightnessKey(systemDefinedSubtype: 8, data1: 0x0002_0A00), .up)
        XCTAssertEqual(BrightnessKey(systemDefinedSubtype: 8, data1: 0x0002_0B00), .up, "key up still names the key")
        XCTAssertTrue(BrightnessKey.isSystemDefinedKeyDown(data1: 0x0002_0A00))
        XCTAssertFalse(BrightnessKey.isSystemDefinedKeyDown(data1: 0x0002_0B00))
        XCTAssertNil(BrightnessKey(systemDefinedSubtype: 8, data1: 0x0000_0A00), "volume up is not brightness")
        XCTAssertNil(BrightnessKey(systemDefinedSubtype: 7, data1: 1), "subtype 7 is not a media key")
    }
}

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

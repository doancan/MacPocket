import XCTest
@testable import MacPocketCore

private final class FakeSMC: SMCTransport, @unchecked Sendable {
    var keys: [String: SMCKeyValue] = [:]
    var writes: [(key: String, bytes: [UInt8])] = []
    var failingWrites: Set<String> = []
    /// Writing the target moves the actual speed there, unless a test freezes it.
    var followsTarget = true

    static func float(_ value: Float) -> SMCKeyValue { SMCKeyValue(type: "flt ", bytes: withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }) }

    init(fans: Int = 1, withFtst: Bool = false) {
        keys["FNum"] = SMCKeyValue(type: "ui8 ", bytes: [UInt8(fans)])
        for index in 0..<fans {
            keys["F\(index)Mn"] = Self.float(1100)
            keys["F\(index)Mx"] = Self.float(3500)
            keys["F\(index)Ac"] = Self.float(1300)
            keys["F\(index)Md"] = SMCKeyValue(type: "ui8 ", bytes: [0])
            keys["F\(index)Tg"] = Self.float(0)
        }
        if withFtst { keys["Ftst"] = SMCKeyValue(type: "ui8 ", bytes: [0]) }
    }

    func read(_ key: String) throws -> SMCKeyValue? { keys[key] }

    func write(_ key: String, bytes: [UInt8]) throws {
        if failingWrites.contains(key) { throw FanControlError.writeRefused(key) }
        writes.append((key, bytes))
        keys[key] = SMCKeyValue(type: keys[key]?.type ?? "ui8 ", bytes: bytes)
        if followsTarget, key.hasSuffix("Tg") { keys[key.replacingOccurrences(of: "Tg", with: "Ac")] = keys[key] }
    }

    func decoded(_ key: String) -> Double? { keys[key].flatMap { SMCValue.decode(type: $0.type, bytes: $0.bytes) } }
}

final class FanControllerTests: XCTestCase {
    private func controller(_ smc: FakeSMC) -> FanController { FanController(transport: smc, sleep: { _ in }) }

    func testSetTargetClampsToRange() throws {
        let smc = FakeSMC()
        try controller(smc).setTarget(fan: 0, rpm: 100)
        XCTAssertEqual(smc.decoded("F0Tg"), 1100)
        try controller(smc).setTarget(fan: 0, rpm: 9000)
        XCTAssertEqual(smc.decoded("F0Tg"), 3500)
    }

    func testWritesModeThenTargetWithoutFtst() throws {
        let smc = FakeSMC()
        try controller(smc).setTarget(fan: 0, rpm: 2000)
        XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "F0Tg"])
        XCTAssertEqual(smc.writes[0].bytes, [1])
    }

    func testWritesFtstFirstWhenPresent() throws {
        let smc = FakeSMC(withFtst: true)
        try controller(smc).setTarget(fan: 0, rpm: 2000)
        XCTAssertEqual(smc.writes.map(\.key), ["Ftst", "F0Md", "F0Tg"])
    }

    func testUnknownFanIsRejected() {
        XCTAssertThrowsError(try controller(FakeSMC()).setTarget(fan: 3, rpm: 2000)) {
            XCTAssertEqual($0 as? FanControlError, .noSuchFan)
        }
    }

    func testNoMovementReleasesAndThrows() {
        let smc = FakeSMC()
        smc.followsTarget = false
        XCTAssertThrowsError(try controller(smc).setTarget(fan: 0, rpm: 3000)) {
            XCTAssertEqual($0 as? FanControlError, .noMovement(fan: 0))
        }
        XCTAssertEqual(smc.writes.last?.key, "F0Md")
        XCTAssertEqual(smc.writes.last?.bytes, [0])
    }

    func testReleaseAllReportsFailureWhenAFanCannotBeReleased() {
        let smc = FakeSMC(fans: 2)
        smc.failingWrites = ["F1Md"]
        XCTAssertFalse(controller(smc).releaseAll())
        XCTAssertEqual(smc.decoded("F0Md"), 0, "the other fan is still released")
    }

    func testReleaseAllReportsFailureWhenTheFanCountIsUnreadable() {
        let smc = FakeSMC(fans: 1, withFtst: true)
        smc.keys["FNum"] = nil
        XCTAssertFalse(controller(smc).releaseAll())
        XCTAssertEqual(smc.decoded("Ftst"), 0, "the diagnostic unlock is cleared regardless")
    }

    func testReleaseAllReportsSuccessWhenEverythingIsReleased() {
        let smc = FakeSMC(fans: 2, withFtst: true)
        XCTAssertTrue(controller(smc).releaseAll())
    }

    func testReleaseAllContinuesAfterFailure() {
        let smc = FakeSMC(fans: 2)
        smc.failingWrites = ["F0Md"]
        controller(smc).releaseAll()
        XCTAssertEqual(smc.writes.map(\.key), ["F1Md"])
    }
}

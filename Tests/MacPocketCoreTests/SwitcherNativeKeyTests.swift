import XCTest
@testable import MacPocketCore

private final class NativeKeyFixture: SwitcherNativeKeyAccess {
    var values: [Int32:Bool] = [1:true,2:true]
    var writes: [(Int32,Bool)] = []
    var failOnce: Int32?,ignoreDisable: Int32?,failRestore: Int32?
    func enabled(_ id: Int32) -> Bool? { values[id] }
    func set(_ id: Int32,enabled: Bool) -> Bool {
        writes.append((id,enabled))
        if !enabled,failOnce == id { failOnce = nil;return false }
        if enabled,failRestore == id { return false }
        if enabled || ignoreDisable != id { values[id] = enabled }
        return true
    }
}
final class SwitcherNativeKeyTests: XCTestCase {
    func testAllOriginalCombinationsAreRestoredIncludingPreviouslyDisabledKeys() throws {
        for forward in [false,true] { for reverse in [false,true] {
            let io = NativeKeyFixture()
            io.values = [1:forward,2:reverse]
            let original = try XCTUnwrap(SwitcherNativeKeyTransaction.snapshot(io))
            XCTAssertTrue(SwitcherNativeKeyTransaction.disable(io,original: original))
            XCTAssertEqual(io.values,[1:false,2:false])
            XCTAssertTrue(SwitcherNativeKeyTransaction.restore(io,original: original))
            XCTAssertEqual(io.values,[1:forward,2:reverse])
        } }
    }
    func testPartialDisableFailureRollsBothKeysBack() throws {
        let io = NativeKeyFixture()
        io.failOnce = 2
        let original = try XCTUnwrap(SwitcherNativeKeyTransaction.snapshot(io))
        XCTAssertFalse(SwitcherNativeKeyTransaction.disable(io,original: original))
        XCTAssertEqual(io.values,[1:true,2:true])
    }
    func testAcceptedSetterWithoutActualStateChangeCannotReportSuccess() throws {
        let io = NativeKeyFixture()
        io.ignoreDisable = 2
        let original = try XCTUnwrap(SwitcherNativeKeyTransaction.snapshot(io))
        XCTAssertFalse(SwitcherNativeKeyTransaction.disable(io,original: original))
        XCTAssertEqual(io.values,[1:true,2:true])
    }
    func testRestoreAttemptsSecondKeyEvenWhenFirstFailsAndReportsFailure() {
        let io = NativeKeyFixture()
        io.values = [1:false,2:false]
        io.failRestore = 1
        XCTAssertFalse(SwitcherNativeKeyTransaction.restore(io,original: .init(forward: true,reverse: true)))
        XCTAssertEqual(io.values,[1:false,2:true])
        XCTAssertEqual(io.writes.map(\.0),[1,2])
    }
    func testUnavailableSnapshotDoesNotInventDefaultStateOrWriteAnything() {
        let io = NativeKeyFixture()
        io.values[2] = nil
        XCTAssertNil(SwitcherNativeKeyTransaction.snapshot(io))
        XCTAssertTrue(io.writes.isEmpty)
    }
    func testOnlyTheTwoCommandTabSymbolicKeysAreChanged() {
        let io = NativeKeyFixture()
        _ = SwitcherNativeKeyTransaction.disable(io,original: .init(forward: true,reverse: true))
        _ = SwitcherNativeKeyTransaction.restore(io,original: .init(forward: true,reverse: true))
        XCTAssertEqual(io.writes.map(\.0),[1,2,1,2])
    }
}

import ApplicationServices
import XCTest
@testable import MacPocketCore

final class WindowFocusOwnerTests: XCTestCase {
    private func fixture() -> TabIOFixture {
        let io = TabIOFixture()
        io.pids[10] = 7; io.roles[10] = .value(kAXSheetRole as String); io.numbers[10] = 100
        io.groupRoots[10] = 1
        return io
    }
    func testOrdinaryWindowRetainsItsIdentityWithoutParentReads() {
        let io = fixture()
        XCTAssertEqual(WindowFocusOwner.window(for: 1,processID: 7,io: io),1)
        XCTAssertTrue(io.rootReads.isEmpty)
    }
    func testAttachedSheetResolvesExactOwnerRatherThanItsOwnWindowServerID() {
        let io = fixture()
        XCTAssertEqual(WindowFocusOwner.window(for: 10,processID: 7,io: io),1)
        io.groupRoots[10] = 2
        XCTAssertEqual(WindowFocusOwner.window(for: 10,processID: 7,io: io),2)
        XCTAssertTrue(io.presses.isEmpty)
    }
    func testNestedSheetAndStructuralGroupKeepTheSameVerifiedOwner() {
        let io = fixture()
        io.pids[11] = 7; io.roles[11] = .value("AXGroup"); io.groupRoots[10] = 11; io.groupRoots[11] = 1
        XCTAssertEqual(WindowFocusOwner.window(for: 10,processID: 7,io: io),1)
        io.roles[11] = .value(kAXSheetRole as String)
        XCTAssertEqual(WindowFocusOwner.window(for: 10,processID: 7,io: io),1)
    }
    func testUnrelatedDialogControlsOrApplicationCannotProveWindowFocus() {
        let io = fixture()
        for role in ["AXDialog", "AXTextField", kAXApplicationRole as String] {
            io.roles[10] = .value(role)
            XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
        }
        io.roles[10] = .value(kAXSheetRole as String); io.roles[1] = .value(kAXApplicationRole as String)
        XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
    }
    func testUnknownRoleForeignProcessAndMissingParentRemainUnproven() {
        let io = fixture()
        io.pids[1] = 8
        XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
        io.pids[1] = 7; io.roles[1] = .invalid
        XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
        io.groupRoots[10] = nil
        XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
        io.trusted = false
        XCTAssertNil(WindowFocusOwner.window(for: 1,processID: 7,io: io))
    }
    func testCyclicAndExcessivelyDeepProviderTreesAreBounded() {
        let io = fixture()
        io.groupRoots[10] = 10
        XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
        for node in 10...20 { io.pids[node] = 7; io.roles[node] = .value(kAXSheetRole as String); io.groupRoots[node] = node+1 }
        io.pids[21] = 7; io.roles[21] = .value(kAXWindowRole as String)
        io.rootReads = []
        XCTAssertNil(WindowFocusOwner.window(for: 10,processID: 7,io: io))
        XCTAssertLessThanOrEqual(io.rootReads.count,8)
    }
    func testCancelledWorkDoesNotReadOrPromoteAParent() async {
        let task = Task { () -> Bool in
            let io = TabIOFixture()
            withUnsafeCurrentTask { $0?.cancel() }
            return WindowFocusOwner.window(for: 1,processID: 7,io: io) == nil && io.rootReads.isEmpty
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }
}

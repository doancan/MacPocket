import AppKit
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp
import MacPocketTestSupport

@MainActor private final class CursorFollowerFixture: WindowCursorFollowing {
    var origin: WindowCursorOrigin? = .init(point: CGPoint(x: 20,y: 20))
    var captured = 0
    var followed: [WindowFocusDestination] = []
    var policies: [SwitcherCursorPolicy] = []
    var accepts = true
    var notReadyReads = 0
    var moves = 0
    func captureOrigin() -> WindowCursorOrigin? { captured += 1;return origin }
    func follow(_ target: WindowFocusDestination,from origin: WindowCursorOrigin,policy: SwitcherCursorPolicy) -> WindowCursorFollowOutcome {
        followed.append(target)
        policies.append(policy)
        if notReadyReads > 0 { notReadyReads -= 1;return .notReady }
        if accepts { moves += 1;return .moved }
        return .unavailable
    }
}
private actor CursorCatalogFixture: WindowCatalogServing {
    let destination = WindowFocusDestination(processID: 1,launchedAt: Date(timeIntervalSince1970: 10),windowID: 1,frame: CGRect(x: 1200,y: 200,width: 400,height: 300))
    var failsFocus = false
    var pausedID: String?
    var nilReads = 0
    private var pending: CheckedContinuation<Void,Never>?
    private(set) var destinationRequests = 0
    func configure(fails: Bool = false,pausedID: String? = nil,nilReads: Int = 0) { failsFocus = fails;self.pausedID = pausedID;self.nilReads = nilReads }
    var isWaiting: Bool { pending != nil }
    func release() { pausedID = nil;pending?.resume();pending = nil }
    func snapshot() async -> WindowCatalogReport { .init(windows: [],accessibilityGranted: true,partial: false) }
    func focus(_ id: String) async throws { if failsFocus { throw WindowCatalogError.expired } }
    func focusDestination(_ id: String) async -> WindowFocusDestination? {
        destinationRequests += 1
        if id == pausedID { await withCheckedContinuation { pending = $0 } }
        if nilReads > 0 { nilReads -= 1;return nil }
        return .init(processID: destination.processID,launchedAt: destination.launchedAt,windowID: id == "second" ? 2 : 1,frame: destination.frame)
    }
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

@MainActor final class WindowCursorIntegrationTests: XCTestCase {
    private func defaults() -> UserDefaults {
        temporaryDefaults()
    }
    private func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < end { if await condition() { return true };try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }
    func testDefaultNeverDoesNotReadCursorOrRequestPostFocusGeometry() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let success = await model.focus(id: "first")
        XCTAssertTrue(success)
        XCTAssertEqual(cursor.captured,0)
        XCTAssertTrue(cursor.followed.isEmpty)
        let requests = await catalog.destinationRequests
        XCTAssertEqual(requests,0)
    }
    func testSuccessfulFocusUsesFreshDestinationAndFollowsExactlyOnce() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let success = await model.focus(id: "first",cursorPolicy: .always)
        XCTAssertTrue(success)
        XCTAssertEqual(cursor.captured,1)
        XCTAssertEqual(cursor.followed.count,1)
        XCTAssertEqual(cursor.followed.first?.frame,CGRect(x: 1200,y: 200,width: 400,height: 300))
        XCTAssertEqual(cursor.policies,[.always])
    }
    func testFocusFailureNeverRequestsGeometryOrMovesCursor() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        await catalog.configure(fails: true)
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let success = await model.focus(id: "first",cursorPolicy: .always)
        XCTAssertFalse(success)
        XCTAssertNotNil(model.failure)
        XCTAssertTrue(cursor.followed.isEmpty)
        let requests = await catalog.destinationRequests
        XCTAssertEqual(requests,0)
    }
    func testCancelledMetadataReadCannotMoveCursorOrReplaceNewFailure() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        await catalog.configure(pausedID: "first")
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let task = Task { await model.focus(id: "first",cursorPolicy: .always) }
        let waiting = await wait { await catalog.isWaiting }
        XCTAssertTrue(waiting)
        task.cancel()
        model.failure = "new failure"
        await catalog.release()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertEqual(model.failure,"new failure")
        XCTAssertTrue(cursor.followed.isEmpty)
    }
    func testLateResultOfOlderFocusCannotWarpAfterNewerFocusCompletes() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        await catalog.configure(pausedID: "first")
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let old = Task { await model.focus(id: "first",cursorPolicy: .always) }
        let waiting = await wait { await catalog.isWaiting }
        XCTAssertTrue(waiting)
        let new = await model.focus(id: "second",cursorPolicy: .differentDisplay)
        XCTAssertTrue(new)
        await catalog.release()
        let stale = await old.value
        XCTAssertFalse(stale)
        XCTAssertEqual(cursor.followed.map(\.windowID),[2])
        XCTAssertEqual(cursor.policies,[.differentDisplay])
    }
    func testStoppingModelObservationInvalidatesPendingCursorWork() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        await catalog.configure(pausedID: "first")
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let task = Task { await model.focus(id: "first",cursorPolicy: .always) }
        let waiting = await wait { await catalog.isWaiting }
        XCTAssertTrue(waiting)
        model.stopObserving()
        await catalog.release()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(cursor.followed.isEmpty)
    }
    func testMetadataRetriesAreBoundedAndNeverFallBackToStaleCatalogFrame() async {
        for reads in [2,100] {
            let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
            await catalog.configure(nilReads: reads)
            let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
            let success = await model.focus(id: "first",cursorPolicy: .always)
            XCTAssertTrue(success)
            let requests = await catalog.destinationRequests
            XCTAssertEqual(requests,reads == 2 ? 3 : 8)
            XCTAssertEqual(cursor.followed.count,reads == 2 ? 1 : 0)
        }
    }
    func testReadinessRetriesOnlyReadsAndNeverRepeatsASuccessfulWarp() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        cursor.notReadyReads = 2
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let success = await model.focus(id: "first",cursorPolicy: .always)
        XCTAssertTrue(success)
        XCTAssertEqual(cursor.captured,1)
        XCTAssertEqual(cursor.followed.count,3)
        XCTAssertEqual(cursor.moves,1)
        let reads = await catalog.destinationRequests
        XCTAssertEqual(reads,3)
    }
    func testCursorRefusalDoesNotTurnSuccessfulFocusIntoAnError() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture()
        cursor.accepts = false
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults(),cursorFollower: cursor)
        let success = await model.focus(id: "first",cursorPolicy: .always)
        XCTAssertTrue(success)
        XCTAssertNil(model.failure)
        XCTAssertEqual(cursor.followed.count,1)
    }
    func testMissingOriginSkipsMetadataAndPolicyIsCapturedBeforeAwaiting() async {
        let catalog = CursorCatalogFixture(),cursor = CursorFollowerFixture(),d = defaults()
        cursor.origin = nil
        let model = WindowSwitcherModel(catalog: catalog,defaults: d,cursorFollower: cursor)
        let first = await model.focus(id: "first",cursorPolicy: .always)
        XCTAssertTrue(first)
        let requests = await catalog.destinationRequests
        XCTAssertEqual(requests,0)
        cursor.origin = .init(point: CGPoint(x: 20,y: 20))
        d.set(SwitcherCursorPolicy.always.rawValue,forKey: SwitcherCursorPolicy.key)
        await catalog.configure(pausedID: "first")
        let task = Task { await model.focus(id: "first") }
        let waiting = await wait { await catalog.isWaiting }
        XCTAssertTrue(waiting)
        d.set(SwitcherCursorPolicy.never.rawValue,forKey: SwitcherCursorPolicy.key)
        await catalog.release()
        let second = await task.value
        XCTAssertTrue(second)
        XCTAssertEqual(cursor.policies,[.always])
    }
}

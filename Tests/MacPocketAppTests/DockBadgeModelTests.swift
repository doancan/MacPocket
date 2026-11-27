import AppKit
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

private actor BadgeReaderFixture: DockApplicationBadgeReading {
    private var values: [DockBadgeTarget:DockApplicationBadge] = [:]
    private var pending: CheckedContinuation<Void,Never>?
    private var blocked = false
    private(set) var requests: [[DockBadgeTarget]] = []
    func set(_ values: [DockBadgeTarget:DockApplicationBadge]) { self.values = values }
    func block() { blocked = true }
    var isWaiting: Bool { pending != nil }
    func release() { blocked = false;pending?.resume();pending = nil }
    func badges(for targets: [DockBadgeTarget]) async -> [DockBadgeTarget:DockApplicationBadge] {
        requests.append(targets)
        let captured = values
        if blocked { await withCheckedContinuation { pending = $0 } }
        return captured
    }
}
private actor BadgeCatalogFixture: WindowCatalogServing {
    var rows: [SwitchableWindow]
    init(_ rows: [SwitchableWindow]) { self.rows = rows }
    func set(_ rows: [SwitchableWindow]) { self.rows = rows }
    func snapshot() async -> WindowCatalogReport { .init(windows: rows,accessibilityGranted: true,partial: false) }
    func focus(_ id: String) async throws {}
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}
@MainActor final class DockBadgeModelTests: XCTestCase {
    private func row(_ id: String = "A",pid: Int32 = 10,launch: Date? = Date(timeIntervalSince1970: 1)) -> SwitchableWindow {
        .init(id: id,processID: pid,application: "Fixture",title: id,applicationURL: URL(fileURLWithPath: "/Applications/Fixture.app"),
              minimized: false,hidden: false,fullScreen: false,frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,
              launchedAt: launch,lastFocusedAt: nil,windowID: 1)
    }
    private func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < end { if await condition() { return true };try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }
    func testTwoWindowsShareOneApplicationBadgeRequestAndValue() async throws {
        let a = row(),b = row("B"),reader = BadgeReaderFixture(),target = try XCTUnwrap(DockBadgeTarget(a))
        await reader.set([target: DockApplicationBadge("7")!])
        let model = WindowSwitcherModel(windows: [a,b],badgeReader: reader),epoch = model.beginApplicationBadges()
        let task = Task { await model.runApplicationBadges(session: epoch) }
        defer { model.stopApplicationBadges();task.cancel() }
        let updated = await wait { model.applicationBadge(for: a)?.label == "7" }
        XCTAssertTrue(updated)
        XCTAssertEqual(model.applicationBadge(for: a),model.applicationBadge(for: b))
        let calls = await reader.requests
        XCTAssertEqual(calls.count,1)
        XCTAssertEqual(calls.first?.count,1)
    }
    func testNoKnownApplicationIdentityDoesNotCallProvider() async {
        let reader = BadgeReaderFixture(),model = WindowSwitcherModel(windows: [row(launch: nil)],badgeReader: reader),epoch = model.beginApplicationBadges()
        let task = Task { await model.runApplicationBadges(session: epoch) }
        try? await Task.sleep(for: .milliseconds(50))
        model.stopApplicationBadges()
        task.cancel()
        await task.value
        let requests = await reader.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(model.applicationBadges.isEmpty)
    }
    func testStopRejectsAnAlreadyInFlightReply() async throws {
        let a = row(),reader = BadgeReaderFixture(),target = try XCTUnwrap(DockBadgeTarget(a))
        await reader.set([target: DockApplicationBadge("7")!])
        await reader.block()
        let model = WindowSwitcherModel(windows: [a],badgeReader: reader),epoch = model.beginApplicationBadges()
        let task = Task { await model.runApplicationBadges(session: epoch) }
        let waiting = await wait { await reader.isWaiting }
        XCTAssertTrue(waiting)
        model.stopApplicationBadges()
        task.cancel()
        await reader.release()
        await task.value
        XCTAssertTrue(model.applicationBadges.isEmpty)
    }
    func testOlderSessionCannotReplaceNewerSessionBadge() async throws {
        let a = row(),reader = BadgeReaderFixture(),target = try XCTUnwrap(DockBadgeTarget(a))
        await reader.set([target: DockApplicationBadge("old")!])
        await reader.block()
        let model = WindowSwitcherModel(windows: [a],badgeReader: reader),oldID = model.beginApplicationBadges()
        let old = Task { await model.runApplicationBadges(session: oldID) }
        let waiting = await wait { await reader.isWaiting }
        XCTAssertTrue(waiting)
        model.stopApplicationBadges()
        let newID = model.beginApplicationBadges()
        await reader.set([target: DockApplicationBadge("new")!])
        await reader.release()
        let new = Task { await model.runApplicationBadges(session: newID) }
        let updated = await wait { model.applicationBadge(for: a)?.label == "new" }
        XCTAssertTrue(updated)
        await old.value
        XCTAssertEqual(model.applicationBadge(for: a)?.label,"new")
        model.stopApplicationBadges()
        new.cancel()
        await new.value
    }
    func testRemovedApplicationCannotReceiveAnInFlightBadge() async throws {
        let a = row(),reader = BadgeReaderFixture(),target = try XCTUnwrap(DockBadgeTarget(a)),catalog = BadgeCatalogFixture([a])
        await reader.set([target: DockApplicationBadge("7")!])
        await reader.block()
        let model = WindowSwitcherModel(windows: [a],catalog: catalog,badgeReader: reader),epoch = model.beginApplicationBadges()
        let task = Task { await model.runApplicationBadges(session: epoch) }
        let waiting = await wait { await reader.isWaiting }
        XCTAssertTrue(waiting)
        await catalog.set([])
        await model.refresh()
        await reader.release()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(model.applicationBadges.isEmpty)
        model.stopApplicationBadges()
        task.cancel()
        await task.value
    }
    func testCompleteEmptySnapshotClearsAnOldBadge() async throws {
        let a = row(),reader = BadgeReaderFixture(),target = try XCTUnwrap(DockBadgeTarget(a))
        await reader.set([target: DockApplicationBadge("7")!])
        let model = WindowSwitcherModel(windows: [a],badgeReader: reader),epoch = model.beginApplicationBadges()
        let task = Task { await model.runApplicationBadges(session: epoch) }
        let first = await wait { model.applicationBadge(for: a) != nil }
        XCTAssertTrue(first)
        await reader.set([:])
        let cleared = await wait { model.applicationBadges.isEmpty }
        XCTAssertTrue(cleared)
        model.stopApplicationBadges()
        task.cancel()
        await task.value
    }
    func testUnrequestedOrReusedProcessResultIsIgnored() async throws {
        let a = row(),replacement = row("B",launch: Date(timeIntervalSince1970: 2)),reader = BadgeReaderFixture()
        await reader.set([try XCTUnwrap(DockBadgeTarget(replacement)): DockApplicationBadge("7")!])
        let model = WindowSwitcherModel(windows: [a],badgeReader: reader),epoch = model.beginApplicationBadges()
        let task = Task { await model.runApplicationBadges(session: epoch) }
        let called = await wait { await reader.requests.count == 1 }
        XCTAssertTrue(called)
        XCTAssertTrue(model.applicationBadges.isEmpty)
        model.stopApplicationBadges()
        task.cancel()
        await task.value
    }
    func testDuplicateWorkersAreCoalescedAndModelStopClearsValues() async throws {
        let a = row(),reader = BadgeReaderFixture(),target = try XCTUnwrap(DockBadgeTarget(a))
        await reader.set([target: DockApplicationBadge("7")!])
        let model = WindowSwitcherModel(windows: [a],badgeReader: reader),epoch = model.beginApplicationBadges()
        let first = Task { await model.runApplicationBadges(session: epoch) },second = Task { await model.runApplicationBadges(session: epoch) }
        let updated = await wait { !model.applicationBadges.isEmpty }
        XCTAssertTrue(updated)
        let calls = await reader.requests
        XCTAssertEqual(calls.count,1)
        model.stopObserving()
        XCTAssertTrue(model.applicationBadges.isEmpty)
        first.cancel()
        second.cancel()
        await first.value
        await second.value
    }
}

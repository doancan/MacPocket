import ApplicationServices
import XCTest
@testable import MacPocketCore

final class TabIOFixture: WindowTabIO {
    var trusted = true
    var roles: [Int: WindowTabRole] = [:], pids: [Int: Int32] = [:], numbers: [Int: UInt32] = [:]
    var groupRoots: [Int: Int] = [:], controls: [Int: [Int]] = [:], titles: [Int: String] = [:]
    var selected = Set<Int>(), unavailableChildren = Set<Int>(), subroles: [Int: String] = [:]
    var rootReads: [Int] = [], tabReads = 0, presses: [Int] = []
    var onTabRead: ((Int) -> Void)?
    var pressSucceeds = true, pressChangesSelection = true
    init() { addGroup(base: 1) }
    func addGroup(base: Int, pid: Int32 = 7) {
        let a = base, b = base + 1, group = base + 2, first = base + 3, second = base + 4
        for node in [a, b, group, first, second] { pids[node] = pid }
        roles[a] = .value("AXWindow"); roles[b] = .value("AXWindow"); roles[group] = .value("AXTabGroup")
        roles[first] = .value("AXRadioButton"); roles[second] = .value("AXRadioButton")
        subroles[a] = "AXStandardWindow"; subroles[b] = "AXStandardWindow"
        numbers[a] = UInt32(base * 10); numbers[b] = UInt32(base * 10 + 1)
        groupRoots[group] = a; controls[group] = [first, second]; selected.insert(first)
        titles[first] = "Same"; titles[second] = "Same"
    }
    func equal(_ lhs: Int, _ rhs: Int) -> Bool { lhs == rhs }
    func processID(_ element: Int) -> Int32? { pids[element] }
    func windowID(_ element: Int) -> UInt32? { numbers[element] }
    func role(_ element: Int) -> WindowTabRole { roles[element] ?? .unavailable }
    func string(_ element: Int, attribute: String) -> String? { subroles[element] }
    func flag(_ element: Int, attribute: String) -> Bool { selected.contains(element) }
    func element(_ element: Int, attribute: String) -> Int? {
        rootReads.append(element)
        return groupRoots[element]
    }
    func children(_ element: Int, limit: Int) -> [Int]? {
        guard !unavailableChildren.contains(element) else { return nil }
        let children = controls[element] ?? groupRoots.filter { $0.value == element }.keys.sorted()
        return children.count <= limit ? children : nil
    }
    func tabAttributes(_ element: Int) -> WindowTabAttributes? {
        tabReads += 1; onTabRead?(element)
        return .init(subrole: titles[element] == nil ? nil : "AXTabButton", title: titles[element] ?? "", selected: selected.contains(element))
    }
    func setTimeout(_ element: Int, seconds: Float) {}
    func press(_ element: Int) -> Bool {
        presses.append(element)
        if pressSucceeds, pressChangesSelection, let group = controls.first(where: { $0.value.contains(element) }) {
            selected.subtract(group.value); selected.insert(element)
            let index = group.value.firstIndex(of: element)!
            groupRoots[group.key] = group.key - 2 + index
        }
        return pressSucceeds
    }
}

final class WindowTabAccessibilityTests: XCTestCase {
    func testAnchorResolvesCurrentPhysicalRootWithoutSelectingBackgroundTab() throws {
        let io = TabIOFixture()
        let live = TabAccessibility(io: io)
        let scan = try remember(live, io: io)
        let target = try XCTUnwrap(scan.actions.values.first { $0.button == 4 })
        io.selected = [5]; io.groupRoots[3] = 2
        XCTAssertEqual(try live.anchorWindow(for: target, processID: 7), 2)
        XCTAssertTrue(io.presses.isEmpty)
    }

    func testAnchorRejectsRemovedTargetBeforeAnyActivationCanUseItsWindow() throws {
        let io = TabIOFixture()
        let live = TabAccessibility(io: io)
        let scan = try remember(live, io: io)
        let target = try XCTUnwrap(scan.actions.values.first { $0.button == 5 })
        io.controls[3] = [4]
        XCTAssertThrowsError(try live.anchorWindow(for: target, processID: 7))
        XCTAssertTrue(io.presses.isEmpty)
    }

    func testAnchorRejectsForeignProcessRootWithoutPressing() throws {
        let io = TabIOFixture()
        let adapter = TabAccessibility(io: io)
        let scan = try remember(adapter, io: io)
        let target = try XCTUnwrap(scan.actions.values.first)
        io.pids[1] = 99
        XCTAssertThrowsError(try adapter.anchorWindow(for: target, processID: 7))
        XCTAssertTrue(io.presses.isEmpty)
    }
    private let process = WindowTabProcess(pid: 7, launchedAt: Date(timeIntervalSince1970: 10))
    private let frame = CGRect(x: 40, y: 80, width: 600, height: 400)
    private var deadline: Date { Date().addingTimeInterval(5) }
    private var emptyProjection: WindowTabProjection { WindowTabProjectionResolver.project([], surfaces: [], bars: []) }
    private func anchor(_ root: Int, io: TabIOFixture, process: WindowTabProcess) -> SwitchableWindow {
        .init(id: "root-\(io.numbers[root]!)", processID: process.pid, application: "Fixture", title: "Current",
              applicationURL: nil, minimized: false, hidden: false, fullScreen: false, frontmost: false,
              windowAccessible: true, canClose: true, canMinimize: true, canFullScreen: true,
              launchedAt: process.launchedAt, lastFocusedAt: nil, windowID: io.numbers[root], frame: frame)
    }
    @discardableResult private func remember(_ adapter: TabAccessibility<TabIOFixture>, io: TabIOFixture,
                                            root: Int = 1, process: WindowTabProcess? = nil,
                                            live: Set<WindowTabProcess>? = nil) throws -> TabScan<Int> {
        let owner = process ?? self.process
        let window = anchor(root, io: io, process: owner)
        let scan = try XCTUnwrap(adapter.scan(window: root, anchorID: window.id, deadline: deadline))
        let projection = WindowTabProjectionResolver.project([window], surfaces: [
            .init(id: io.numbers[root]!, processID: owner.pid, frame: frame, spaceIDs: [1]),
            .init(id: io.numbers[root + 1]!, processID: owner.pid, frame: frame, spaceIDs: [])
        ], bars: [scan.bar])
        XCTAssertEqual(projection.windows.count, 2)
        adapter.commit(scans: [scan], processes: [window.id: owner], projection: projection, liveProcesses: live ?? [owner])
        return scan
    }

    func testOnlyPhysicallyCorroboratedGroupsBecomeDiscoverySources() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: TabIOFixture())
        let own = TabAccessibility(io: io)
        let window = anchor(1, io: io, process: process)
        let scan = try XCTUnwrap(own.scan(window: 1, anchorID: window.id, deadline: deadline))
        own.commit(scans: [scan], processes: [window.id: process], projection: emptyProjection, liveProcesses: [process])
        XCTAssertEqual(own.rememberedGroupCount, 0)
        XCTAssertTrue(own.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows.isEmpty)
        XCTAssertEqual(adapter.rememberedGroupCount, 0)
    }

    func testCachedGroupRecoversMissingAXWindowAndChildrenWithFreshTitlesAndSelection() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        let old = try remember(adapter, io: io)
        io.groupRoots[3] = 2; io.selected = [5]; io.titles[5] = "Renamed off Space"
        io.unavailableChildren = [1, 2]
        let recovered = adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline)
        XCTAssertEqual(recovered.windows, [2])
        let fresh = try XCTUnwrap(adapter.scan(window: 2, anchorID: "root-11", cached: recovered.cachedByWindowID[11] ?? [], deadline: deadline))
        XCTAssertEqual(fresh.bar.groupID, old.bar.groupID)
        XCTAssertEqual(fresh.bar.controls.map(\.id), old.bar.controls.map(\.id))
        XCTAssertEqual(fresh.bar.controls.map(\.selected), [false, true])
        XCTAssertEqual(fresh.bar.controls[1].title, "Renamed off Space")
        XCTAssertEqual(fresh.bar.anchorID, "root-11")
    }

    func testCachedRootDoesNotDuplicateWindowAlreadyInAXList() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        try remember(adapter, io: io)
        let recovered = adapter.discoverWindows(listed: [1], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline)
        XCTAssertEqual(recovered.windows, [1])
        XCTAssertEqual(recovered.cachedByWindowID[10]?.count, 1)
    }

    func testGroupWindowMustMatchAnchorBeforeAnyControlRead() {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        io.groupRoots[3] = 2
        // The old AX window can still list a group through a stale child relationship.
        let previous = TabScan(group: 3, bar: WindowTabBar(groupID: "g", anchorID: "old", controls: [
            .init(id: "a", title: "Same", selected: true), .init(id: "b", title: "Same", selected: false)
        ])!, actions: [:])
        XCTAssertNil(adapter.scan(window: 1, anchorID: "old", cached: [previous], deadline: deadline))
        XCTAssertEqual(io.tabReads, 0)
    }

    func testTabChangeDuringReadCannotBindNewListToOldRoot() {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        io.onTabRead = { node in if node == 5 { io.groupRoots[3] = 2 } }
        XCTAssertNil(adapter.scan(window: 1, anchorID: "root-10", deadline: deadline))
        XCTAssertEqual(io.tabReads, 2)
    }

    func testChangedSelectedValueDuringReadCannotPublishACompleteBar() {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        io.onTabRead = { node in if node == 5 { io.selected = [] } }
        XCTAssertNil(adapter.scan(window: 1, anchorID: "root-10", deadline: deadline))
    }

    func testProcessReuseCannotRecoverPreviousGroupsAndCommitPrunesThem() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        try remember(adapter, io: io)
        let reused = WindowTabProcess(pid: 7, launchedAt: Date(timeIntervalSince1970: 30))
        XCTAssertTrue(adapter.discoverWindows(listed: [], process: reused, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows.isEmpty)
        adapter.commit(scans: [], processes: [:], projection: emptyProjection, liveProcesses: [reused])
        XCTAssertEqual(adapter.rememberedGroupCount, 0)
    }

    func testScopedRefreshPreservesOtherLiveApplicationGroups() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        io.addGroup(base: 10, pid: 8)
        let other = WindowTabProcess(pid: 8, launchedAt: process.launchedAt), live: Set<WindowTabProcess> = [process, other]
        try remember(adapter, io: io, live: live)
        try remember(adapter, io: io, root: 10, process: other, live: live)
        adapter.commit(scans: [], processes: [:], projection: emptyProjection, liveProcesses: live)
        XCTAssertEqual(adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows, [1])
        XCTAssertEqual(adapter.discoverWindows(listed: [], process: other, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows, [10])
    }

    func testInvalidGroupIsEvictedButTemporaryReadFailureDoesNotReplayCachedData() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        try remember(adapter, io: io)
        io.roles[3] = .unavailable
        let unavailable = adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline)
        XCTAssertTrue(unavailable.windows.isEmpty); XCTAssertTrue(unavailable.partial)
        adapter.commit(scans: [], processes: [:], projection: emptyProjection, liveProcesses: [process], invalidGroups: unavailable.invalidGroups)
        XCTAssertEqual(adapter.rememberedGroupCount, 1)
        io.roles[3] = .invalid
        let invalid = adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline)
        adapter.commit(scans: [], processes: [:], projection: emptyProjection, liveProcesses: [process], invalidGroups: invalid.invalidGroups)
        XCTAssertEqual(adapter.rememberedGroupCount, 0)
    }

    func testUnknownOrForeignWindowRootIsNotRecovered() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        try remember(adapter, io: io)
        io.pids[1] = 8
        XCTAssertTrue(adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows.isEmpty)
        io.pids[1] = 7; io.numbers.removeValue(forKey: 1)
        XCTAssertTrue(adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows.isEmpty)
    }

    func testCachedAXReferenceWithoutCurrentPhysicalSurfaceCannotCreateAWindow() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        try remember(adapter, io: io)
        let vanished = adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: [], deadline: deadline)
        XCTAssertTrue(vanished.windows.isEmpty); XCTAssertTrue(vanished.partial)
        let ordinaryAX = adapter.discoverWindows(listed: [1], process: process, physicalWindowIDs: [], deadline: deadline)
        XCTAssertEqual(ordinaryAX.windows, [1], "The physical recovery gate does not narrow ordinary live AX enumeration")
    }

    func testTwoCachedGroupsClaimingOneRootAreRejectedTogether() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        io.addGroup(base: 10)
        try remember(adapter, io: io); try remember(adapter, io: io, root: 10)
        io.groupRoots[12] = 1
        let result = adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline)
        XCTAssertTrue(result.windows.isEmpty); XCTAssertEqual(result.invalidGroups.count, 2)
    }

    func testRecoveryBudgetAndWindowLimitAreExplicitlyPartial() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        try remember(adapter, io: io)
        let expired = adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline, recoveryBudget: 0)
        XCTAssertTrue(expired.windows.isEmpty); XCTAssertTrue(expired.partial)
        let full = adapter.discoverWindows(listed: [2], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline, limit: 1)
        XCTAssertEqual(full.windows, [2]); XCTAssertTrue(full.partial)
    }

    func testGroupAndControlBudgetsEvictLeastRecentlyVerifiedGroups() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io, groupLimit: 1, controlLimit: 2)
        io.addGroup(base: 10)
        try remember(adapter, io: io); try remember(adapter, io: io, root: 10)
        XCTAssertEqual(adapter.rememberedGroupCount, 1)
        XCTAssertEqual(adapter.discoverWindows(listed: [], process: process, physicalWindowIDs: Set(io.numbers.values), deadline: deadline).windows, [10])
    }

    func testPermissionRevocationClearsRetainedReferencesAndPreventsActions() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        let scan = try remember(adapter, io: io), target = try XCTUnwrap(scan.actions[scan.bar.controls[1].id])
        io.trusted = false
        XCTAssertThrowsError(try adapter.press(target, processID: process.pid)) { XCTAssertEqual($0 as? WindowCatalogError, .permissionRequired) }
        adapter.commit(scans: [], processes: [:], projection: emptyProjection, liveProcesses: [process])
        XCTAssertEqual(adapter.rememberedGroupCount, 0); XCTAssertTrue(io.presses.isEmpty)
    }

    func testRemovedSameLabelControlCannotReceiveSavedAction() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        let scan = try remember(adapter, io: io), target = try XCTUnwrap(scan.actions[scan.bar.controls[1].id])
        io.controls[3] = [4, 6]; io.titles[6] = "Same"; io.pids[6] = 7
        XCTAssertThrowsError(try adapter.press(target, processID: process.pid)) { XCTAssertEqual($0 as? WindowCatalogError, .expired) }
        XCTAssertTrue(io.presses.isEmpty)
    }

    func testRenamedControlAndForeignButtonCannotReceiveSavedAction() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        let scan = try remember(adapter, io: io), target = try XCTUnwrap(scan.actions[scan.bar.controls[1].id])
        io.titles[5] = "Changed"
        XCTAssertThrowsError(try adapter.press(target, processID: process.pid)) { XCTAssertEqual($0 as? WindowCatalogError, .expired) }
        io.titles[5] = "Same"; io.pids[5] = 8
        XCTAssertThrowsError(try adapter.press(target, processID: process.pid)) { XCTAssertEqual($0 as? WindowCatalogError, .expired) }
        XCTAssertTrue(io.presses.isEmpty)
    }

    func testReorderedControlKeepsExactActionAndSelectionIsVerifiedSeparately() throws {
        let io = TabIOFixture(), adapter = TabAccessibility(io: io)
        let scan = try remember(adapter, io: io), target = try XCTUnwrap(scan.actions[scan.bar.controls[1].id])
        io.controls[3] = [5, 4]
        // The fixture's transport chooses a root by index; disable that convenience and
        // explicitly model the correct root after proving the action hit the original node.
        io.pressChangesSelection = false
        try adapter.press(target, processID: process.pid)
        XCTAssertEqual(io.presses, [5]); XCTAssertNil(adapter.selectedWindow(for: target, processID: process.pid))
        io.selected = [5]; io.groupRoots[3] = 2
        XCTAssertEqual(adapter.selectedWindow(for: target, processID: process.pid), 2)
    }
}

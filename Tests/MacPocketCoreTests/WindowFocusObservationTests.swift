import XCTest
@testable import MacPocketCore

final class WindowFocusObservationTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_000)

    func testRepeatedFocusChangesWithinOneApplicationKeepIndependentWindowTimes() {
        var timeline = WindowFocusTimeline()
        timeline.record(pid: 1, launchedAt: launch, windowID: 10, elementHash: 100, at: Date(timeIntervalSince1970: 10))
        timeline.record(pid: 1, launchedAt: launch, windowID: 20, elementHash: 200, at: Date(timeIntervalSince1970: 20))
        timeline.record(pid: 1, launchedAt: launch, windowID: 10, elementHash: 100, at: Date(timeIntervalSince1970: 30))
        let keyA = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: 10, elementHash: 100)
        let keyB = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: 20, elementHash: 200)
        XCTAssertEqual(timeline.timestamps[keyA], Date(timeIntervalSince1970: 30))
        XCTAssertEqual(timeline.timestamps[keyB], Date(timeIntervalSince1970: 20))
        let windows = [UInt32(20), 10, 30].map { id in
            let key = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: id, elementHash: 0)
            return SwitchableWindow(id: key, processID: 1, application: "Fixture", title: "Window \(id)", applicationURL: nil,
                minimized: false, hidden: false, fullScreen: false, frontmost: false, windowAccessible: true,
                canClose: true, canMinimize: true, canFullScreen: true, launchedAt: launch,
                lastFocusedAt: timeline.timestamps[key], windowID: id)
        }
        XCTAssertEqual(WindowFiltering.apply(windows).compactMap(\.windowID), [10, 20, 30])
        XCTAssertNil(windows.last?.lastFocusedAt, "A sibling window must not inherit the application's activation time")
    }

    func testWindowServerAndAXFallbackIdentitiesResolveTheSameEventWithoutGuessingByTitle() {
        var timeline = WindowFocusTimeline()
        let time = Date(timeIntervalSince1970: 20)
        timeline.record(pid: 1, launchedAt: launch, windowID: 10, elementHash: 900, at: time)
        let serverKey = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: 10, elementHash: 0)
        let axKey = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: nil, elementHash: 900)
        XCTAssertEqual(timeline.timestamps[serverKey], time)
        XCTAssertEqual(timeline.timestamps[axKey], time)
        timeline.record(pid: 1, launchedAt: launch, windowID: nil, elementHash: 901, at: time)
        let fallback = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: nil, elementHash: 901)
        XCTAssertEqual(timeline.timestamps[fallback], time)
        XCTAssertEqual(timeline.count, 2)
    }

    func testLaunchIdentityAndTerminationProtectAgainstPIDReuseAndLateEvents() {
        var timeline = WindowFocusTimeline()
        let newLaunch = launch.addingTimeInterval(500)
        timeline.record(pid: 1, launchedAt: launch, windowID: 10, elementHash: 100, at: Date(timeIntervalSince1970: 10))
        timeline.record(pid: 1, launchedAt: newLaunch, windowID: 10, elementHash: 100, at: Date(timeIntervalSince1970: 30))
        timeline.record(pid: 1, launchedAt: newLaunch, windowID: 10, elementHash: 100, at: Date(timeIntervalSince1970: 20))
        timeline.remove(pid: 1, launchedAt: launch)
        XCTAssertEqual(timeline.count, 1)
        let oldKey = CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: 10, elementHash: 100)
        let newKey = CatalogWindowIdentity.window(pid: 1, launchedAt: newLaunch, windowID: 10, elementHash: 100)
        XCTAssertNil(timeline.timestamps[oldKey])
        XCTAssertEqual(timeline.timestamps[newKey], Date(timeIntervalSince1970: 30))
        timeline.record(pid: 2, launchedAt: nil, windowID: 10, elementHash: 100, at: .now)
        XCTAssertEqual(timeline.count, 1, "Unstable process identities must not create inherited history")
        timeline.remove(pid: 1, launchedAt: nil)
        XCTAssertTrue(timeline.timestamps.isEmpty)
    }

    func testHistoryIsBoundedAndClearDropsAllAliases() {
        var timeline = WindowFocusTimeline(capacity: 2)
        for index in 1...3 {
            timeline.record(pid: 1, launchedAt: launch, windowID: UInt32(index), elementHash: UInt(index), at: Date(timeIntervalSince1970: Double(index)))
        }
        XCTAssertEqual(timeline.count, 2)
        XCTAssertNil(timeline.timestamps[CatalogWindowIdentity.window(pid: 1, launchedAt: launch, windowID: 1, elementHash: 1)])
        timeline.clear()
        XCTAssertTrue(timeline.timestamps.isEmpty)
        var disabled = WindowFocusTimeline(capacity: 0)
        disabled.record(pid: 1, launchedAt: launch, windowID: 1, elementHash: 1, at: .now)
        XCTAssertTrue(disabled.timestamps.isEmpty)
    }

    func testMissingOrReusedProcessLaunchCannotValidateAWindowTarget() {
        XCTAssertFalse(CatalogWindowIdentity.matchesProcessLaunch(expected: nil, actual: nil))
        XCTAssertFalse(CatalogWindowIdentity.matchesProcessLaunch(expected: launch, actual: nil))
        XCTAssertFalse(CatalogWindowIdentity.matchesProcessLaunch(expected: nil, actual: launch))
        XCTAssertFalse(CatalogWindowIdentity.matchesProcessLaunch(expected: launch, actual: launch.addingTimeInterval(1)))
        XCTAssertTrue(CatalogWindowIdentity.matchesProcessLaunch(expected: launch, actual: launch))
    }

    func testKernelIdentityWorksForTheOwnedProcessWithoutAnAppKitLaunchDate() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let initial = try XCTUnwrap(CatalogWindowIdentity.processLaunchDate(pid: pid, applicationDate: nil))
        let repeated = CatalogWindowIdentity.processLaunchDate(pid: pid, applicationDate: Date())
        XCTAssertEqual(initial, repeated, "An optional AppKit date changing must not expire a kernel identity")
        XCTAssertGreaterThan(initial.timeIntervalSince1970, 0)
        XCTAssertLessThanOrEqual(initial, Date())
        XCTAssertNil(CatalogWindowIdentity.processLaunchDate(pid: -1, applicationDate: launch))
    }

    func testProcessLaunchResolutionPrefersKernelButRetainsAppKitFallback() {
        let kernel = launch, application = launch.addingTimeInterval(0.5)
        XCTAssertEqual(CatalogWindowIdentity.resolvedLaunchDate(kernel: kernel, application: application), kernel)
        XCTAssertEqual(CatalogWindowIdentity.resolvedLaunchDate(kernel: kernel, application: nil), kernel)
        XCTAssertEqual(CatalogWindowIdentity.resolvedLaunchDate(kernel: nil, application: application), application)
        XCTAssertNil(CatalogWindowIdentity.resolvedLaunchDate(kernel: nil, application: nil))
    }
}

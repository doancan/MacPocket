import XCTest
@testable import MacPocketCore

final class WindowListFilterTests: XCTestCase {
    private func window(_ id: String, pid: Int32 = 1, minimized: Bool = false, hidden: Bool = false,
                        fullScreen: Bool = false, real: Bool = true, otherSpace: Bool = false,
                        display: UInt32? = nil, z: Int? = nil, frame: CGRect? = nil,
                        focused: TimeInterval? = nil, launched: TimeInterval? = nil) -> SwitchableWindow {
        .init(id: id, processID: pid, application: "App \(pid)", title: id,
              applicationURL: URL(fileURLWithPath: "/Applications/App\(pid).app"),
              minimized: minimized, hidden: hidden, fullScreen: fullScreen, frontmost: false,
              windowAccessible: real, canClose: real, canMinimize: real, canFullScreen: real,
              launchedAt: launched.map(Date.init(timeIntervalSince1970:)), lastFocusedAt: focused.map(Date.init(timeIntervalSince1970:)),
              windowID: real ? UInt32(pid) : nil, frame: frame, displayID: display, otherSpace: otherSpace, zOrder: z)
    }

    func testLegacyBooleansMigrateWithoutDiscardingShortcutFilters() throws {
        let legacy = Data(#"{"includeMinimized":false,"includeHidden":true,"includeWindowless":true,"currentApplicationOnly":true,"currentSpaceOnly":true,"currentScreenOnly":true}"#.utf8)
        let filter = try JSONDecoder().decode(WindowListFilter.self, from: legacy)
        XCTAssertEqual(filter.minimized, .hide)
        XCTAssertEqual(filter.hidden, .show)
        XCTAssertEqual(filter.windowless, .show)
        XCTAssertEqual(filter.applicationScope, .frontmost)
        XCTAssertEqual(filter.spaceScope, .visible)
        XCTAssertTrue(filter.currentScreenOnly)
        XCTAssertTrue(filter.includeFullScreen)
        XCTAssertEqual(filter.grouping, .allWindows)
        let empty = try JSONDecoder().decode(WindowListFilter.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, WindowListFilter())
    }

    func testNewFiltersRoundTripAndEncodeLegacyVisibilityForOlderVersions() throws {
        var filter = WindowListFilter()
        filter.minimized = .atEnd
        filter.hidden = .hide
        filter.windowless = .atEnd
        filter.applicationScope = .other
        filter.spaceScope = .notVisible
        filter.currentScreenOnly = true
        filter.includeFullScreen = false
        filter.grouping = .onePerApplication
        let data = try JSONEncoder().encode(filter)
        XCTAssertEqual(try JSONDecoder().decode(WindowListFilter.self, from: data), filter)
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(legacy["includeMinimized"] as? Bool, true)
        XCTAssertEqual(legacy["includeHidden"] as? Bool, false)
        XCTAssertEqual(legacy["includeWindowless"] as? Bool, true)
        XCTAssertEqual(legacy["currentApplicationOnly"] as? Bool, false)
        let unknown = Data(#"{"minimized":"new-policy","includeMinimized":false,"applicationScope":"new-scope","currentApplicationOnly":true,"spaceScope":"future","currentSpaceOnly":true,"grouping":"new-group"}"#.utf8)
        let decoded = try JSONDecoder().decode(WindowListFilter.self, from: unknown)
        XCTAssertEqual(decoded.minimized, .hide)
        XCTAssertEqual(decoded.applicationScope, .frontmost)
        XCTAssertEqual(decoded.spaceScope, .visible)
        XCTAssertEqual(decoded.grouping, .allWindows)
    }

    func testTrailingCategoriesPartitionWithoutReversingRequestedOrderOrDuplicatingOverlaps() {
        let input = [window("z-normal"), window("a-minimized", minimized: true), window("b-hidden", hidden: true),
                     window("c-both", minimized: true, hidden: true), window("d-windowless", real: false), window("e-normal")]
        var filter = WindowListFilter()
        filter.minimized = .atEnd
        filter.hidden = .atEnd
        filter.windowless = .atEnd
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, order: .title).map(\.id),
                       ["e-normal", "z-normal", "a-minimized", "b-hidden", "c-both", "d-windowless"])
        filter.hidden = .hide
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, order: .title).map(\.id),
                       ["e-normal", "z-normal", "a-minimized", "d-windowless"])
    }

    func testFullscreenApplicationSearchAndExclusionsComposeBeforeGrouping() {
        let input = [window("current", pid: 1), window("Report full", pid: 2, fullScreen: true),
                     window("Report one", pid: 2), window("Report two", pid: 2), window("Report excluded", pid: 3)]
        var filter = WindowListFilter()
        filter.applicationScope = .other
        filter.includeFullScreen = false
        filter.grouping = .onePerApplication
        let result = WindowFiltering.apply(input, filter: filter, context: .init(foregroundPID: 1), search: "REPORT",
                                           excludedBundlePaths: ["/Applications/App3.app"], order: .title)
        XCTAssertEqual(result.map(\.id), ["Report one"])
        XCTAssertTrue(WindowFiltering.apply(input, filter: filter).isEmpty, "A missing front app must not silently expand the scope")
        filter.applicationScope = .frontmost
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: .init(foregroundPID: 1)).map(\.id), ["current"])
    }

    func testPointerApplicationUsesFrontWindowBeforeSearchOrBlacklist() {
        let rect = CGRect(x: -500, y: 50, width: 200, height: 100)
        let input = [window("back report", pid: 1, z: 9, frame: rect), window("front", pid: 2, z: 1, frame: rect),
                     window("minimized", pid: 3, minimized: true, z: 0, frame: rect),
                     window("hidden", pid: 4, hidden: true, z: 0, frame: rect),
                     window("other space", pid: 5, otherSpace: true, z: 0, frame: rect),
                     window("unknown visibility", pid: 6, frame: rect)]
        let context = WindowFilterContext(pointerLocation: CGPoint(x: -450, y: 75))
        XCTAssertEqual(WindowFiltering.applicationUnderPointer(input, at: context.pointerLocation), 2)
        var filter = WindowListFilter()
        filter.applicationScope = .pointerApplication
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: context).map(\.id), ["front"])
        XCTAssertTrue(WindowFiltering.apply(input, filter: filter, context: context, search: "report").isEmpty)
        XCTAssertTrue(WindowFiltering.apply(input, filter: filter, context: context, excludedBundlePaths: ["/Applications/App2.app"]).isEmpty)
        XCTAssertTrue(WindowFiltering.apply(input, filter: filter, context: .init(pointerLocation: .zero)).isEmpty)
    }

    func testPointerWindowsIncludesOverlappingVisibleWindowsAndUsesCapturedApplication() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let input = [window("back", pid: 1, z: 9, frame: rect), window("front", pid: 2, z: 1, frame: rect),
                     window("not-under-pointer", pid: 1, z: 5, frame: CGRect(x: 400, y: 0, width: 100, height: 100))]
        var filter = WindowListFilter()
        filter.applicationScope = .pointerWindows
        let context = WindowFilterContext(pointerLocation: CGPoint(x: 10, y: 10), pointerApplicationPID: 1)
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: context).map(\.id), ["front", "back"])
        filter.applicationScope = .pointerApplication
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: context).map(\.id), ["not-under-pointer", "back"])
    }

    func testSpaceInferenceAndUnknownDisplayAreNeverInvented() {
        let input = [window("visible", display: 1, z: 1), window("other-visible-screen", display: 2, z: 2),
                     window("inferred-other", otherSpace: true, display: 1),
                     window("minimized-unknown-space", minimized: true, display: 1), window("unknown-both")]
        var filter = WindowListFilter()
        filter.currentScreenOnly = true
        filter.spaceScope = .visible
        let context = WindowFilterContext(displayID: 1)
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: context).map(\.id),
                       ["visible", "minimized-unknown-space", "unknown-both"])
        filter.spaceScope = .notVisible
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: context).map(\.id),
                       ["inferred-other", "minimized-unknown-space", "unknown-both"])
    }

    func testGroupingKeepsFirstEligibleWindowAndDistinctRunningInstances() {
        let input = [window("a-min", pid: 1, minimized: true, focused: 50), window("b-normal", pid: 1, focused: 10),
                     window("c-second-instance", pid: 2), window("d-reused-pid", pid: 1, launched: 90)]
        var filter = WindowListFilter()
        filter.minimized = .atEnd
        filter.grouping = .onePerApplication
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, order: .title).map(\.id),
                       ["b-normal", "c-second-instance", "d-reused-pid"])
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, search: "min").map(\.id), ["a-min"])
        filter.minimized = .show
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, order: .recent).first?.id, "a-min")
    }

    func testOffscreenOrMissingFramesDoNotInventADisplay() {
        let screens: [(UInt32, CGRect)] = [(1, CGRect(x: 0, y: 0, width: 1_000, height: 800)),
                                           (2, CGRect(x: -800, y: -100, width: 800, height: 600))]
        XCTAssertEqual(WindowFiltering.displayID(for: CGRect(x: -700, y: 0, width: 200, height: 200), among: screens), 2)
        XCTAssertEqual(WindowFiltering.displayID(for: CGRect(x: -100, y: 0, width: 400, height: 200), among: screens), 1)
        XCTAssertEqual(WindowFiltering.displayID(for: CGRect(x: 900, y: 700, width: 400, height: 400), among: screens), 1)
        XCTAssertNil(WindowFiltering.displayID(for: CGRect(x: 2_000, y: 0, width: 400, height: 400), among: screens))
        XCTAssertNil(WindowFiltering.displayID(for: nil, among: screens))
        XCTAssertNil(WindowFiltering.displayID(for: .zero, among: []))
    }
}

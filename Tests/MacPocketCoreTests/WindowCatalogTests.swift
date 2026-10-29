import XCTest
@testable import MacPocketCore

final class WindowCatalogTests: XCTestCase {
    private func window(_ id: String, app: String = "Browser", pid: Int32 = 10, minimized: Bool = false,
                        hidden: Bool = false, accessible: Bool = true, focusedAt: Date? = nil) -> SwitchableWindow {
        .init(id: id, processID: pid, application: app, title: id, applicationURL: URL(fileURLWithPath: "/Applications/\(app).app"),
              minimized: minimized, hidden: hidden, fullScreen: false, frontmost: false, windowAccessible: accessible,
              canClose: accessible, canMinimize: accessible, canFullScreen: accessible, launchedAt: nil, lastFocusedAt: focusedAt)
    }
    func testIndependentVisibilityFiltersAndBlacklist() {
        let input = [window("normal"), window("min", minimized: true), window("hidden", hidden: true),
                     window("no-window", accessible: false), window("excluded", app: "Excluded")]
        XCTAssertEqual(WindowFiltering.apply(input, includeMinimized: false, includeHidden: false, includeWindowless: false,
                                            excludedBundlePaths: ["/Applications/Excluded.app"]).map(\.id), ["normal"])
        XCTAssertEqual(WindowFiltering.apply(input, includeHidden: false).count, 4)
        XCTAssertEqual(WindowFiltering.apply(input, includeMinimized: false).count, 4)
    }
    func testApplicationScopeAndCaseInsensitiveSearchCompose() {
        let input = [window("Document A", app: "Editor", pid: 1), window("document B", app: "Editor", pid: 2), window("Other", pid: 1)]
        XCTAssertEqual(WindowFiltering.apply(input, search: "DOCUMENT", currentApplication: 1).map(\.id), ["Document A"])
        XCTAssertTrue(WindowFiltering.apply(input, currentApplication: 99).isEmpty)
    }
    func testRecentOrderUsesObservedHistoryAndPreservesUnknownTies() {
        let input = [window("unknown-A"), window("old", focusedAt: Date(timeIntervalSince1970: 10)),
                     window("recent", focusedAt: Date(timeIntervalSince1970: 20)), window("unknown-B")]
        XCTAssertEqual(WindowFiltering.apply(input).map(\.id), ["recent", "old", "unknown-A", "unknown-B"])
        XCTAssertEqual(WindowFiltering.apply(input, order: .title).map(\.id), ["old", "recent", "unknown-A", "unknown-B"])
    }
    func testUnknownHandlesFailBeforeAnyWindowMutation() async {
        let catalog = WindowCatalog()
        for action in [WindowAction.close, .minimize, .restore, .toggleFullScreen, .hideApplication] {
            do { try await catalog.perform(action, on: "not-a-live-handle"); XCTFail("Unknown handle accepted") }
            catch WindowCatalogError.expired {} catch { XCTFail("Unexpected error: \(error)") }
        }
        do { try await catalog.focus("not-a-live-handle"); XCTFail("Unknown focus accepted") }
        catch WindowCatalogError.expired {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

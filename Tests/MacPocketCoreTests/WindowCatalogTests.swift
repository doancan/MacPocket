import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

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
    func testSwitchSelectionUsesCapturedForegroundAfterPanelHasTakenFocus() {
        let input = [window("current", pid: 1), window("previous", pid: 2), window("third", pid: 3)]
        XCTAssertEqual(WindowSwitchSelection.initial(input, foregroundPID: 1, backwards: false), "previous")
        XCTAssertEqual(WindowSwitchSelection.initial(input, foregroundPID: 1, backwards: true), "third")
    }
    func testSwitchSelectionRetainsRapidPressesWhilePreparing() {
        let input = [window("a", pid: 1), window("b", pid: 2), window("c", pid: 3)]
        XCTAssertEqual(WindowSwitchSelection.initial(input, foregroundPID: 1, backwards: false, queuedSteps: 7), "c")
        XCTAssertEqual(WindowSwitchSelection.initial(input, foregroundPID: 1, backwards: false, queuedSteps: -7), "a")
        XCTAssertEqual(WindowSwitchSelection.initial(input, foregroundPID: 99, backwards: false), "a")
        XCTAssertEqual(WindowSwitchSelection.initial(input, foregroundPID: 99, backwards: true), "c")
        XCTAssertNil(WindowSwitchSelection.initial([], foregroundPID: 1, backwards: false))
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

    func testGeometryFallbackRequiresOneUnambiguousWindow() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        let first = ServerWindow(id: 1, pid: 10, frame: frame, title: "Same title", onScreen: true)
        let duplicate = ServerWindow(id: 2, pid: 10, frame: frame, title: "Same title", onScreen: true)
        let near = ServerWindow(id: 3, pid: 10, frame: frame.offsetBy(dx: 1, dy: 1), title: "Another tab", onScreen: false)
        XCTAssertEqual(WindowCatalog.uniqueWindowID(matching: frame, candidates: [first]), 1)
        XCTAssertNil(WindowCatalog.uniqueWindowID(matching: frame, candidates: [first, duplicate]))
        XCTAssertNil(WindowCatalog.uniqueWindowID(matching: frame, candidates: [first, near]))
        XCTAssertNil(WindowCatalog.uniqueWindowID(matching: frame.offsetBy(dx: 100, dy: 0), candidates: [first]))
    }

    func testEnvironmentRefreshRetainsTargetAndAppliesQueuedInputOnce() {
        let old = [window("old"), window("kept"), window("last")]
        let fresh = [window("new"), window("kept"), window("other")]
        XCTAssertEqual(WindowSwitchSelection.refreshed(old, preserving: "kept", queuedSteps: 1), "last")
        XCTAssertEqual(WindowSwitchSelection.refreshed(fresh, preserving: "kept", queuedSteps: 1), "other")
        XCTAssertEqual(WindowSwitchSelection.refreshed(fresh, preserving: "kept", queuedSteps: -2), "other")
        XCTAssertEqual(WindowSwitchSelection.refreshed(fresh, preserving: "gone"), "new")
        XCTAssertEqual(WindowSwitchSelection.refreshed(fresh, preserving: "gone", queuedSteps: -1), "other")
        XCTAssertNotNil(WindowSwitchSelection.refreshed(fresh, preserving: nil, queuedSteps: .max))
        XCTAssertNotNil(WindowSwitchSelection.refreshed(fresh, preserving: nil, queuedSteps: .min))
        XCTAssertNil(WindowSwitchSelection.refreshed([], preserving: "kept", queuedSteps: 100))
    }
}

final class SwitcherConfigurationTests: XCTestCase {
    private func window(_ id: String, otherSpace: Bool = false, display: UInt32? = nil, zOrder: Int? = nil,
                        windowID: UInt32? = 1, accessible: Bool = false) -> SwitchableWindow {
        .init(id: id, processID: 1, application: "Safari", title: id, applicationURL: nil, minimized: false, hidden: false,
              fullScreen: false, frontmost: false, windowAccessible: accessible, canClose: false, canMinimize: false,
              canFullScreen: false, launchedAt: nil, lastFocusedAt: nil, windowID: windowID, displayID: display,
              otherSpace: otherSpace, zOrder: zOrder)
    }

    func testSpaceAndScreenFiltersAndServerOnlyWindowsCountAsReal() {
        let input = [window("here", display: 1), window("elsewhere", otherSpace: true, display: 1), window("second", display: 2),
                     window("windowless", windowID: nil)]
        XCTAssertEqual(WindowFiltering.apply(input, includeWindowless: false).map(\.id), ["here", "elsewhere", "second"])
        XCTAssertEqual(WindowFiltering.apply(input, includeWindowless: false, currentSpaceOnly: true).map(\.id), ["here", "second"])
        XCTAssertEqual(WindowFiltering.apply(input, includeWindowless: false, displayID: 2).map(\.id), ["second"])
    }

    func testUnobservedWindowsFollowStackingOrder() {
        let input = [window("back", zOrder: 5), window("offscreen"), window("front", zOrder: 1)]
        XCTAssertEqual(WindowFiltering.apply(input).map(\.id), ["front", "back", "offscreen"])
    }

    func testSearchMatchesEveryTermIgnoringCaseAndDiacritics() {
        XCTAssertTrue(WindowFiltering.matches("goo chr", "Google Chrome Issues"))
        XCTAssertTrue(WindowFiltering.matches("SIKISTIR", "Sıkıştırılmış rapor".replacingOccurrences(of: "ı", with: "i")))
        XCTAssertTrue(WindowFiltering.matches("rapor", "Günlük RAPOR"))
        XCTAssertFalse(WindowFiltering.matches("chrome mail", "Google Chrome"))
    }

    func testCarbonFlagsAndDisplayName() {
        let shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab, modifiers: [.control, .option])
        XCTAssertEqual(shortcut.modifiers.carbonFlags, 0x1800)
        XCTAssertEqual(SwitcherModifiers.command.carbonFlags, 0x0100)
        XCTAssertEqual(shortcut.displayName, "⌃⌥⇥")
        XCTAssertEqual(SwitcherShortcut(keyCode: SwitcherKeys.grave, modifiers: .command).displayName, "⌘`")
    }

    func testValidationRejectsReservedDuplicateUnmodifiedAndTooMany() {
        XCTAssertTrue(SwitcherShortcutValidation.problems([.defaultOptionTab]).isEmpty)
        XCTAssertFalse(SwitcherShortcutValidation.problems([]).isEmpty)
        XCTAssertFalse(SwitcherShortcutValidation.problems([.init(keyCode: SwitcherKeys.tab, modifiers: .init(rawValue: 128))]).isEmpty)
        XCTAssertTrue(SwitcherShortcutValidation.problems([.init(keyCode: SwitcherKeys.tab, modifiers: .command)]).isEmpty)
        XCTAssertFalse(SwitcherShortcutValidation.problems([.init(keyCode: SwitcherKeys.tab, modifiers: [])]).isEmpty)
        XCTAssertFalse(SwitcherShortcutValidation.problems([.defaultOptionTab, .defaultOptionTab]).isEmpty)
        XCTAssertFalse(SwitcherShortcutValidation.problems([.init(keyCode: SwitcherKeys.escape, modifiers: .option)]).isEmpty)
        let ten = (0..<10).map { SwitcherShortcut(keyCode: UInt16(18 + $0 % 9), modifiers: $0 < 9 ? .option : .control) }
        XCTAssertTrue(SwitcherShortcutValidation.problems(ten).contains { $0.contains("En fazla") })
    }

    func testStoreMigratesLegacyPresetAndRoundTrips() throws {
        let defaults = temporaryDefaults()
        defaults.set("controlOptionSpace", forKey: "switcher.shortcut")
        defaults.set(false, forKey: "switcher.releaseToChoose")
        defaults.set(true, forKey: "switcher.currentApplication")
        let migrated = SwitcherShortcutStore.load(defaults)
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].displayName, "⌃⌥" + String(localized: "Boşluk"))
        XCTAssertFalse(migrated[0].releaseToChoose)
        XCTAssertTrue(migrated[0].filter.currentApplicationOnly)
        var second = SwitcherShortcut(keyCode: SwitcherKeys.grave, modifiers: .option)
        second.filter.currentSpaceOnly = true
        SwitcherShortcutStore.save(migrated + [second], defaults)
        XCTAssertEqual(SwitcherShortcutStore.load(defaults), migrated + [second])
    }

    func testAutoSizeShrinksToFitAndTitlesUseOneColumn() {
        let screen = CGSize(width: 1440, height: 900)
        let few = SwitcherLayout.compute(count: 3, style: .thumbnails, available: screen, autoSize: true)
        XCTAssertEqual(few.columns, 3)
        XCTAssertEqual(few.rows, 1)
        let many = SwitcherLayout.compute(count: 40, style: .thumbnails, available: screen, autoSize: true)
        XCTAssertLessThan(many.itemSize.width, few.itemSize.width)
        XCTAssertLessThanOrEqual(many.panelSize.width, screen.width * 0.9 + 0.5)
        XCTAssertLessThanOrEqual(many.panelSize.height, screen.height * 0.8 + 0.5)
        let fixed = SwitcherLayout.compute(count: 40, style: .thumbnails, available: screen, autoSize: false)
        XCTAssertEqual(fixed.itemSize.width, few.itemSize.width)
        let titles = SwitcherLayout.compute(count: 6, style: .titles, available: screen, autoSize: true)
        XCTAssertEqual(titles.columns, 1)
        XCTAssertEqual(titles.rows, 6)
    }
}

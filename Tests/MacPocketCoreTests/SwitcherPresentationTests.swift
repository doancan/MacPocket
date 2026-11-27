import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class SwitcherPresentationTests: XCTestCase {
    func testLegacyShortcutKeepsIdentityFiltersAndReleaseChoice() throws {
        let data = Data(#"[{"id":"5DE39B3A-DACA-4869-98C3-C7057624D946","keyCode":48,"modifiers":2,"releaseToChoose":false,"filter":{"includeHidden":false,"currentApplicationOnly":true}}]"#.utf8)
        let shortcuts = try JSONDecoder().decode([SwitcherShortcut].self, from: data)
        let shortcut = try XCTUnwrap(shortcuts.first)
        XCTAssertEqual(shortcut.id.uuidString, "5DE39B3A-DACA-4869-98C3-C7057624D946")
        XCTAssertEqual(shortcut.keyCode, 48)
        XCTAssertEqual(shortcut.modifiers, .option)
        XCTAssertEqual(shortcut.releaseBehavior, .hold)
        XCTAssertFalse(shortcut.filter.includeHidden)
        XCTAssertTrue(shortcut.filter.currentApplicationOnly)
        XCTAssertTrue(shortcut.filter.includeMinimized)
        XCTAssertFalse(shortcut.filter.currentSpaceOnly)
        XCTAssertTrue(shortcut.presentation.isEmpty)
    }

    func testNewShortcutRoundTripKeepsSearchAndIndependentOverrides() throws {
        var first = SwitcherShortcut.defaultOptionTab
        first.releaseBehavior = .search
        first.presentation.style = .titles
        first.presentation.theme = .dark
        first.presentation.order = .title
        first.presentation.autoSize = false
        first.presentation.sizeScale = 1.2
        first.presentation.previewSelected = true
        let second = SwitcherShortcut(keyCode: SwitcherKeys.grave, modifiers: .option)
        let data = try JSONEncoder().encode([first, second])
        XCTAssertEqual(try JSONDecoder().decode([SwitcherShortcut].self, from: data), [first, second])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(object[0]["releaseToChoose"] as? Bool, false)
        XCTAssertEqual(object[0]["releaseBehavior"] as? String, "search")
    }

    func testUnsetOverridesFollowSubsequentGlobalChanges() {
        var global = SwitcherPresentation()
        var overrides = SwitcherPresentationOverrides()
        overrides.style = .titles
        overrides.previewSelected = true
        XCTAssertEqual(overrides.resolve(over: global).style, .titles)
        global.style = .icons
        global.theme = .dark
        global.order = .application
        let resolved = overrides.resolve(over: global)
        XCTAssertEqual(resolved.style, .titles)
        XCTAssertEqual(resolved.theme, .dark)
        XCTAssertEqual(resolved.order, .application)
        XCTAssertTrue(resolved.previewSelected)
        XCTAssertEqual(SwitcherPresentationOverrides().resolve(over: global), global)
    }

    func testUnknownOptionalValuesFallBackWithoutDroppingOtherSettings() throws {
        let data = Data(#"{"keyCode":48,"modifiers":2,"releaseToChoose":false,"releaseBehavior":"future-mode","presentation":{"style":"future-style","theme":"future-theme","sizeScale":2,"order":"future-order","previewSelected":true}}"#.utf8)
        let shortcut = try JSONDecoder().decode(SwitcherShortcut.self, from: data)
        XCTAssertEqual(shortcut.releaseBehavior, .hold)
        XCTAssertNil(shortcut.presentation.style)
        XCTAssertNil(shortcut.presentation.theme)
        XCTAssertNil(shortcut.presentation.order)
        XCTAssertEqual(shortcut.presentation.sizeScale, 1.4)
        XCTAssertEqual(shortcut.presentation.previewSelected, true)
    }

    func testScaleRejectsNonFiniteAndClampsToSupportedRange() {
        var overrides = SwitcherPresentationOverrides()
        overrides.sizeScale = .nan
        XCTAssertEqual(overrides.resolve(over: .init()).sizeScale, 1)
        overrides.sizeScale = 0.1
        XCTAssertEqual(overrides.resolve(over: .init()).sizeScale, 0.6)
    }

    func testReleaseNeverChoosesWhileSearchingEvenWithEmptyQuery() {
        for behavior in SwitcherReleaseBehavior.allCases {
            XCTAssertEqual(SwitcherReleaseDecision.resolve(behavior, isSearching: true), .keepOpen)
        }
        XCTAssertEqual(SwitcherReleaseDecision.resolve(.choose, isSearching: false), .choose)
        XCTAssertEqual(SwitcherReleaseDecision.resolve(.hold, isSearching: false), .keepOpen)
        XCTAssertEqual(SwitcherReleaseDecision.resolve(.search, isSearching: false), .beginSearch)
    }

    func testDifferentShortcutsAreNotDeduplicatedDuringFastModeChanges() {
        var events = SwitcherInvocationDeduplicator()
        let first = UUID(), second = UUID()
        XCTAssertTrue(events.accepts(id: first, backwards: false, source: "carbon", timestamp: 1))
        XCTAssertFalse(events.accepts(id: first, backwards: false, source: "local", timestamp: 1.001))
        XCTAssertTrue(events.accepts(id: second, backwards: false, source: "local", timestamp: 1.002))
        XCTAssertTrue(events.accepts(id: second, backwards: true, source: "carbon", timestamp: 1.003))
        XCTAssertTrue(events.accepts(id: second, backwards: true, source: "carbon", timestamp: 1.004))
    }

    func testLegacyStoreLoadsWholeListRatherThanResettingToSinglePreset() throws {
        let defaults = temporaryDefaults()
        let original = Data(#"[{"id":"5DE39B3A-DACA-4869-98C3-C7057624D946","keyCode":48,"modifiers":2,"releaseToChoose":true,"filter":{}},{"id":"25E38603-91A3-4074-B124-FE76CEE65820","keyCode":50,"modifiers":2,"releaseToChoose":false,"filter":{"currentApplicationOnly":true}}]"#.utf8)
        defaults.set(original, forKey: SwitcherShortcutStore.key)
        let loaded = SwitcherShortcutStore.load(defaults)
        XCTAssertEqual(loaded.count, 2)
        let second = try XCTUnwrap(loaded.dropFirst().first)
        XCTAssertEqual(second.id.uuidString, "25E38603-91A3-4074-B124-FE76CEE65820")
        XCTAssertTrue(second.filter.currentApplicationOnly)
        SwitcherShortcutStore.save(loaded, defaults)
        XCTAssertEqual(SwitcherShortcutStore.load(defaults), loaded)
        defaults.removeObject(forKey: SwitcherShortcutStore.key)
    }
}

import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class SwitcherDisplayOptionsTests: XCTestCase {
    private func window(real: Bool = true) -> SwitchableWindow {
        .init(id: "w", processID: 1, application: "Editor", title: "Window title", applicationURL: nil,
              minimized: false, hidden: false, fullScreen: false, frontmost: false, windowAccessible: real,
              canClose: real, canMinimize: real, canFullScreen: real, launchedAt: nil, lastFocusedAt: nil,
              windowID: real ? 1 : nil)
    }
    func testDefaultPresentationPreservesEstablishedAppearanceAndTiming() {
        let value = SwitcherPresentation()
        XCTAssertEqual(value.titleMode, .standard)
        XCTAssertEqual(value.truncation, .tail)
        XCTAssertEqual(value.screen, .pointer)
        XCTAssertTrue(value.showActions && value.showStatus && value.showThumbnails)
        XCTAssertFalse(value.showSpaces)
        XCTAssertEqual(value.openingDelayMilliseconds, 110)
        XCTAssertEqual(value.effectiveStyle, .thumbnails)
        let plan = SwitcherMotionPlan(presentation: value, reduceMotion: false)
        XCTAssertEqual(plan.opening, 0.09)
        XCTAssertEqual(plan.selection, 0.16)
        XCTAssertEqual(plan.closing, 0)
        XCTAssertEqual(plan.preview, 0)
    }
    func testEveryNewOverrideRoundTripsWithoutLosingFalseOrZero() throws {
        var override = SwitcherPresentationOverrides()
        override.titleMode = .both
        override.truncation = .middle
        override.screen = .activeWindow
        override.showStatus = false
        override.showSpaces = true
        override.showActions = false
        override.showThumbnails = false
        override.openingDelayMilliseconds = 0
        override.animateOpening = false
        override.animateClosing = true
        override.animateSelection = false
        override.animatePreview = true
        let decoded = try JSONDecoder().decode(SwitcherPresentationOverrides.self, from: JSONEncoder().encode(override))
        XCTAssertEqual(decoded, override)
        let resolved = decoded.resolve(over: .init())
        XCTAssertEqual(resolved.effectiveStyle, .icons)
        XCTAssertEqual(resolved.openingDelayMilliseconds, 0)
        XCTAssertEqual(resolved.titleMode, .both)
        XCTAssertEqual(resolved.screen, .activeWindow)
        XCTAssertFalse(resolved.showStatus || resolved.showActions || resolved.animateOpening || resolved.animateSelection)
        XCTAssertTrue(resolved.showSpaces && resolved.animateClosing && resolved.animatePreview)
    }
    func testMissingNewFieldsAndUnknownEnumsRetainOtherSavedChoices() throws {
        let old = try JSONDecoder().decode(SwitcherPresentationOverrides.self, from: Data(#"{"style":"titles","theme":"dark","screen":"future","titleMode":"future","truncation":"future"}"#.utf8))
        XCTAssertEqual(old.style, .titles)
        XCTAssertEqual(old.theme, .dark)
        XCTAssertNil(old.titleMode)
        XCTAssertNil(old.truncation)
        XCTAssertNil(old.screen)
        XCTAssertNil(old.showSpaces)
        XCTAssertEqual(old.resolve(over: .init()).screen, .pointer)
        XCTAssertTrue(try JSONDecoder().decode(SwitcherPresentationOverrides.self, from: Data("{}".utf8)).isEmpty)
    }
    func testUnsetOptionsFollowGlobalChangesAndFalseOverrideRemainsExplicit() {
        var global = SwitcherPresentation(), override = SwitcherPresentationOverrides()
        override.showStatus = false
        global.titleMode = .application
        global.screen = .menuBar
        global.truncation = .head
        global.showSpaces = true
        global.openingDelayMilliseconds = 750
        global.animateClosing = true
        let value = override.resolve(over: global)
        XCTAssertEqual(value.titleMode, .application)
        XCTAssertEqual(value.screen, .menuBar)
        XCTAssertEqual(value.truncation, .head)
        XCTAssertTrue(value.showSpaces && value.animateClosing)
        XCTAssertFalse(value.showStatus)
        XCTAssertEqual(value.openingDelayMilliseconds, 750)
    }
    func testGlobalDefaultsLoadFalseValuesAndSanitizeUnknownValues() throws {
        let defaults = temporaryDefaults()
        defaults.set(false, forKey: "switcher.showThumbnails")
        defaults.set(false, forKey: "switcher.showActions")
        defaults.set(false, forKey: "switcher.animateOpening")
        defaults.set(true, forKey: "switcher.showSpaces")
        defaults.set("future", forKey: "switcher.screen")
        defaults.set("both", forKey: "switcher.titleMode")
        defaults.set(5_000, forKey: "switcher.openingDelayMilliseconds")
        let value = SwitcherPresentation.load(defaults)
        XCTAssertFalse(value.showThumbnails || value.showActions || value.animateOpening)
        XCTAssertTrue(value.showSpaces)
        XCTAssertEqual(value.titleMode, .both)
        XCTAssertEqual(value.screen, .pointer)
        XCTAssertEqual(value.openingDelayMilliseconds, 900)
        XCTAssertEqual(value.effectiveStyle, .icons)
    }
    func testDelayBoundsAvoidOverflowAndDecodeFractionalFutureData() throws {
        for (input, expected) in [(Double.nan,110), (.infinity,110), (-100,0), (0,0), (110.5,111), (1e300,900)] {
            XCTAssertEqual(SwitcherPresentation.boundedDelay(input), expected)
        }
        let value = try JSONDecoder().decode(SwitcherPresentationOverrides.self, from: Data(#"{"openingDelayMilliseconds":110.5}"#.utf8))
        XCTAssertEqual(value.openingDelayMilliseconds, 111)
        var override = SwitcherPresentationOverrides()
        override.openingDelayMilliseconds = Int.max
        XCTAssertEqual(override.resolve(over: .init()).openingDelayMilliseconds, 900)
    }
    func testTitleModesUseFullSourceStringsAndWindowlessAppHasOneName() {
        let actual = window()
        XCTAssertEqual(SwitcherTitleMode.window.labels(for: actual, style: .titles).primary, "Window title")
        XCTAssertNil(SwitcherTitleMode.window.labels(for: actual, style: .titles).secondary)
        XCTAssertEqual(SwitcherTitleMode.application.labels(for: actual, style: .thumbnails).primary, "Editor")
        XCTAssertEqual(SwitcherTitleMode.both.labels(for: actual, style: .icons).secondary, "Editor")
        XCTAssertNil(SwitcherTitleMode.both.labels(for: window(real: false), style: .icons).secondary)
        XCTAssertNil(SwitcherTitleMode.standard.labels(for: actual, style: .thumbnails).secondary)
        XCTAssertEqual(SwitcherTitleMode.standard.labels(for: actual, style: .titles).secondary, "Editor")
    }
    func testHiddenThumbnailsChangeOnlyThumbnailStyleAndLeaveLargePreviewIndependent() {
        var value = SwitcherPresentation()
        value.showThumbnails = false
        value.previewSelected = true
        XCTAssertEqual(value.effectiveStyle, .icons)
        XCTAssertTrue(value.previewSelected)
        value.style = .titles
        XCTAssertEqual(value.effectiveStyle, .titles)
    }
    func testScreenPoliciesDistinguishPointerActiveWindowAndPrimaryDisplay() {
        let screens: [(UInt32, CGRect)] = [(1, CGRect(x: 0, y: 0, width: 1_000, height: 800)),
                                          (2, CGRect(x: -800, y: 100, width: 800, height: 600))]
        let pointer = CGPoint(x: 200, y: 200), active = CGRect(x: -700, y: 150, width: 400, height: 300)
        XCTAssertEqual(SwitcherScreenPolicy.pointer.displayID(screens: screens, pointer: pointer, activeWindowFrame: active, primaryDisplayID: 2), 1)
        XCTAssertEqual(SwitcherScreenPolicy.activeWindow.displayID(screens: screens, pointer: pointer, activeWindowFrame: active, primaryDisplayID: 1), 2)
        XCTAssertEqual(SwitcherScreenPolicy.menuBar.displayID(screens: screens, pointer: pointer, activeWindowFrame: active, primaryDisplayID: 2), 2)
    }
    func testMissingActiveWindowAndDisconnectedDisplaysUseDeterministicFallbacks() {
        let screens: [(UInt32, CGRect)] = [(7, CGRect(x: 0, y: 0, width: 800, height: 600))]
        XCTAssertEqual(SwitcherScreenPolicy.activeWindow.displayID(screens: screens, pointer: CGPoint(x: 30, y: 30), activeWindowFrame: nil, primaryDisplayID: 99), 7)
        XCTAssertEqual(SwitcherScreenPolicy.pointer.displayID(screens: screens, pointer: CGPoint(x: -1_000, y: -1_000), activeWindowFrame: nil, primaryDisplayID: 7), 7)
        XCTAssertNil(SwitcherScreenPolicy.menuBar.displayID(screens: [], pointer: .zero, activeWindowFrame: nil, primaryDisplayID: 7))
    }
    func testSpaceBadgeNeverDisplaysRawOrGuessedIDs() {
        XCTAssertEqual(SwitcherSpaceBadge.text(nil), "?")
        let a = WindowSpace(id: 999_999, ordinal: 3, displayIdentifier: "main", kind: .desktop, visible: false)
        let b = WindowSpace(id: 888_888, ordinal: 5, displayIdentifier: "main", kind: .desktop, visible: true)
        XCTAssertEqual(SwitcherSpaceBadge.text(.init(spaces: [a])), "3")
        XCTAssertEqual(SwitcherSpaceBadge.text(.init(spaces: [a,b], unknownIDs: [7])), "3+?")
    }
    func testReducedMotionOverridesAllFourAnimationChoices() {
        var value = SwitcherPresentation()
        value.animateOpening = true
        value.animateClosing = true
        value.animateSelection = true
        value.animatePreview = true
        let plan = SwitcherMotionPlan(presentation: value, reduceMotion: true)
        XCTAssertEqual(plan.opening + plan.closing + plan.selection + plan.preview, 0)
    }
    func testMinimumIconTileStillHasRoomForControlsAndTwoTitleLines() {
        let layout = SwitcherLayout.compute(count: 10, style: .icons, available: CGSize(width: 800, height: 600), autoSize: false, scale: 0.6)
        XCTAssertGreaterThanOrEqual(layout.itemSize.width, 84)
        XCTAssertGreaterThanOrEqual(layout.itemSize.height, 92)
        XCTAssertLessThanOrEqual(layout.panelSize.width, 800)
    }
}

import XCTest
@testable import MacPocketCore

final class WindowLayoutGeometryTests: XCTestCase {
    /// A 1440×875 visible frame starting 25 pt up (Dock at the bottom).
    private let area = CGRect(x: 0, y: 25, width: 1440, height: 875)

    private func frame(_ action: WindowLayoutAction, gap: CGFloat = 0, step: Int = 0, current: CGRect? = nil) -> CGRect? {
        WindowLayoutGeometry.frame(for: action, in: area, gap: gap, step: step, current: current)
    }

    func testHalvesQuartersAndThirdsWithoutGap() {
        XCTAssertEqual(frame(.leftHalf), CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(frame(.rightHalf), CGRect(x: 720, y: 25, width: 720, height: 875))
        XCTAssertEqual(frame(.topHalf), CGRect(x: 0, y: 463, width: 1440, height: 438), "y up: top half starts mid-screen")
        XCTAssertEqual(frame(.topLeft), CGRect(x: 0, y: 463, width: 720, height: 438))
        XCTAssertEqual(frame(.bottomRight), CGRect(x: 720, y: 25, width: 720, height: 438))
        XCTAssertEqual(frame(.centerThird), CGRect(x: 480, y: 25, width: 480, height: 875))
        XCTAssertEqual(frame(.rightTwoThirds), CGRect(x: 480, y: 25, width: 960, height: 875))
        XCTAssertEqual(frame(.maximize), area)
        XCTAssertEqual(frame(.almostMaximize), CGRect(x: 72, y: 69, width: 1296, height: 788))
    }

    func testGapSurroundsScreenEdgesAndSplitsBetweenNeighbours() throws {
        let left = try XCTUnwrap(frame(.leftHalf, gap: 10))
        let right = try XCTUnwrap(frame(.rightHalf, gap: 10))
        XCTAssertEqual(left.minX, 10)
        XCTAssertEqual(left.minY, 35)
        XCTAssertEqual(left.maxY, 890)
        XCTAssertEqual(right.maxX, 1430)
        XCTAssertEqual(right.minX - left.maxX, 10, "exactly one gap between the two halves")
        XCTAssertEqual(left.width, right.width)
    }

    func testRepeatedHalfCyclesWidth() {
        XCTAssertEqual(frame(.leftHalf, step: 1)?.width, 960)
        XCTAssertEqual(frame(.leftHalf, step: 2)?.width, 480)
        XCTAssertEqual(frame(.leftHalf, step: 3)?.width, 720, "wraps around")
        XCTAssertEqual(frame(.rightHalf, step: 1), CGRect(x: 480, y: 25, width: 960, height: 875))
    }

    func testCenterKeepsSizeAndShrinksOnlyWhenTooBig() {
        XCTAssertEqual(frame(.center, current: CGRect(x: 5, y: 5, width: 800, height: 600)), CGRect(x: 320, y: 163, width: 800, height: 600))
        XCTAssertEqual(frame(.center, gap: 10, current: CGRect(x: 0, y: 0, width: 3000, height: 2000)),
                       CGRect(x: 10, y: 35, width: 1420, height: 855))
        XCTAssertNil(frame(.center))
    }

    func testNonRegionActionsHaveNoFrame() {
        XCTAssertNil(frame(.nextDisplay))
        XCTAssertNil(frame(.restore))
    }

    func testMovingBetweenDisplaysKeepsRelativePlacement() {
        let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)
        let left = CGRect(x: 0, y: 25, width: 720, height: 875)
        XCTAssertEqual(WindowLayoutGeometry.move(left, from: area, to: external), CGRect(x: 1440, y: 0, width: 1280, height: 1415))
        let small = CGRect(x: 1000, y: 500, width: 400, height: 300)
        let moved = WindowLayoutGeometry.move(small, from: area, to: external)
        XCTAssertTrue(external.contains(moved))
    }

    func testFlipBetweenAccessibilityAndAppKitCoordinates() {
        let ax = CGRect(x: 100, y: 50, width: 400, height: 300)
        let appKit = WindowLayoutGeometry.flip(ax, primaryHeight: 900)
        XCTAssertEqual(appKit, CGRect(x: 100, y: 550, width: 400, height: 300))
        XCTAssertEqual(WindowLayoutGeometry.flip(appKit, primaryHeight: 900), ax, "flipping twice is the identity")
    }

    func testCyclingNeedsSameHalfActionWithinShortInterval() {
        let now = Date()
        XCTAssertEqual(WindowLayoutGeometry.nextStep(previous: (.leftHalf, 0, now - 1), action: .leftHalf, now: now, cycling: true), 1)
        XCTAssertEqual(WindowLayoutGeometry.nextStep(previous: (.leftHalf, 0, now - 3), action: .leftHalf, now: now, cycling: true), 0)
        XCTAssertEqual(WindowLayoutGeometry.nextStep(previous: (.leftHalf, 0, now), action: .rightHalf, now: now, cycling: true), 0)
        XCTAssertEqual(WindowLayoutGeometry.nextStep(previous: (.maximize, 0, now), action: .maximize, now: now, cycling: true), 0)
        XCTAssertEqual(WindowLayoutGeometry.nextStep(previous: (.leftHalf, 0, now), action: .leftHalf, now: now, cycling: false), 0)
    }
}

final class WindowLayoutSettingsTests: XCTestCase {
    func testDefaultShortcutsAreValidAndDistinct() {
        let settings = WindowLayoutSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.conflicts, [])
        for action in WindowLayoutAction.allCases {
            XCTAssertTrue(action.defaultShortcut.isValidGlobalShortcut, action.rawValue)
        }
        XCTAssertEqual(WindowLayoutAction.leftHalf.defaultShortcut.displayName, "⌃⌥←")
        XCTAssertEqual(WindowLayoutAction.nextDisplay.defaultShortcut.displayName, "⌃⌥⌘→")
    }

    func testConflictsListTheLaterDuplicate() {
        var settings = WindowLayoutSettings()
        settings.shortcuts[.maximize] = WindowLayoutAction.leftHalf.defaultShortcut
        XCTAssertEqual(settings.conflicts, [.maximize])
    }

    func testRoundTripKeepsCustomAndSwitchedOffShortcuts() throws {
        var settings = WindowLayoutSettings()
        settings.enabled = true
        settings.gap = 8
        settings.shortcuts[.center] = KeyCombo(keyCode: 8, modifiers: [.command, .option])
        settings.shortcuts[.restore] = .some(nil)
        let decoded = try JSONDecoder().decode(WindowLayoutSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertNil(decoded.shortcut(for: .restore))
        XCTAssertEqual(decoded.shortcut(for: .center)?.displayName, "⌥⌘C")
        XCTAssertEqual(decoded.shortcut(for: .leftHalf), WindowLayoutAction.leftHalf.defaultShortcut)
    }

    func testDecodingClampsGapAndDropsInvalidEntries() throws {
        let json = #"{"gap":99,"shortcuts":{"leftHalf":{"keyCode":0,"modifiers":8},"bogus":{"keyCode":0,"modifiers":4}},"disabled":["nope"]}"#
        let settings = try JSONDecoder().decode(WindowLayoutSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.gap, 24)
        XCTAssertTrue(settings.shortcuts.isEmpty, "⇧A alone is invalid; unknown actions are ignored")
    }
}

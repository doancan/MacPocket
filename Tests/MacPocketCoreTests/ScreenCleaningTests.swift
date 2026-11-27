import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class ScreenCleaningTests: XCTestCase {
    func testLockedInputIsDroppedExceptThatEscapeLeaves() {
        XCTAssertEqual(CleaningInputPolicy.decision(isKeyDown: true, keyCode: 53), .exit)
        XCTAssertEqual(CleaningInputPolicy.decision(isKeyDown: false, keyCode: 53), .drop, "Releasing Esc must not leak to an app")
        XCTAssertEqual(CleaningInputPolicy.decision(isKeyDown: true, keyCode: 0), .drop)
        XCTAssertEqual(CleaningInputPolicy.decision(isKeyDown: true, keyCode: 36), .drop, "Return can't dismiss it")
    }

    func testDefaultsKeepTodaysBehaviorAndRoundTrip() throws {
        let defaults = temporaryDefaults()
        var settings = ScreenCleaningSettings.load(from: defaults)
        XCTAssertEqual(settings.color, .black)
        XCTAssertFalse(settings.locksInput, "A system-wide input lock is opt-in")
        settings.color = .white
        settings.locksInput = true
        settings.save(to: defaults)
        XCTAssertEqual(ScreenCleaningSettings.load(from: defaults), settings)
    }

    func testOverlayTextContrastsWithEveryBackground() {
        for color in CleaningColor.allCases {
            XCTAssertNotEqual(color.usesDarkText, color.isDark, "\(color) needs text that stands out")
        }
        XCTAssertTrue(CleaningColor.white.usesDarkText)
        XCTAssertFalse(CleaningColor.black.usesDarkText)
    }

    func testCorruptStoredSettingsFallBack() throws {
        let defaults = temporaryDefaults()
        defaults.set(Data("nope".utf8), forKey: ScreenCleaningSettings.storageKey)
        XCTAssertEqual(ScreenCleaningSettings.load(from: defaults), ScreenCleaningSettings())
    }
}

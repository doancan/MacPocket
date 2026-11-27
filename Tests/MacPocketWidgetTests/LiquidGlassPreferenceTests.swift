import MacPocketShared
import MacPocketTestSupport
import XCTest

final class LiquidGlassPreferenceTests: XCTestCase {
    func testOnUntilThePersonTurnsItOff() {
        let defaults = temporaryDefaults()
        XCTAssertTrue(LiquidGlass.isEnabled(in: defaults))
        defaults.set(false, forKey: LiquidGlass.preferenceKey)
        XCTAssertFalse(LiquidGlass.isEnabled(in: defaults))
        defaults.set(true, forKey: LiquidGlass.preferenceKey)
        XCTAssertTrue(LiquidGlass.isEnabled(in: defaults))
    }
}

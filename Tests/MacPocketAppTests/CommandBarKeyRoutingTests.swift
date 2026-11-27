import AppKit
import XCTest
@testable import MacPocketApp

@MainActor final class CommandBarKeyRoutingTests: XCTestCase {
    private func window() -> NSWindow { NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true) }

    func testKeysFromAssistiveInputWithoutAWindowReachTheKeyPanel() {
        let panel = window()
        // Accessibility Keyboard / Switch Control post events with no window; Return and Esc must still work.
        XCTAssertTrue(CommandBarPanelController.targetsPanel(eventWindow: nil, keyWindow: panel, panel: panel))
    }

    func testKeysForAnotherWindowAreLeftAlone() {
        let panel = window(), other = window()
        XCTAssertFalse(CommandBarPanelController.targetsPanel(eventWindow: other, keyWindow: panel, panel: panel))
        XCTAssertFalse(CommandBarPanelController.targetsPanel(eventWindow: nil, keyWindow: other, panel: panel))
        XCTAssertFalse(CommandBarPanelController.targetsPanel(eventWindow: nil, keyWindow: nil, panel: nil))
    }

    func testKeysTypedIntoThePanelAreHandled() {
        let panel = window()
        XCTAssertTrue(CommandBarPanelController.targetsPanel(eventWindow: panel, keyWindow: nil, panel: panel))
    }
}

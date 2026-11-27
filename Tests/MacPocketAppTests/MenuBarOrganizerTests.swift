import AppKit
import XCTest
@testable import MacPocketApp
import MacPocketTestSupport

@MainActor final class MenuBarOrganizerTests: XCTestCase {
    private func service() -> (MenuBarOrganizerService, UserDefaults) {
        let name = "MacPocket.MenuBarOrganizerTests." + UUID().uuidString
        let defaults = temporaryDefaults()
        return (MenuBarOrganizerService(defaults: defaults, autosavePrefix: name), defaults)
    }
    func testDisabledModuleDoesNotCreateItemsOrChangePreferences() {
        let (service, defaults) = service()
        service.start()
        service.start()
        service.setCollapsed(true)
        XCTAssertFalse(service.enabled)
        XCTAssertFalse(service.collapsed)
        XCTAssertTrue(service.diagnosticFrames.isEmpty)
        service.stopForModule()
        XCTAssertNil(defaults.object(forKey: MenuBarOrganizerService.enabledKey))
    }
    func testHiddenGroupCannotContainSystemOrOwnControlsAndSurvivesStop() {
        let (service, defaults) = service()
        service.start()
        service.setHidden(true, for: "com.apple.controlcenter")
        if let own = Bundle.main.bundleIdentifier { service.setHidden(true, for: own) }
        service.setHidden(true, for: "")
        XCTAssertTrue(service.hiddenApplications.isEmpty)
        service.setHidden(true, for: "org.example.Utility")
        XCTAssertTrue(service.hiddenApplications.contains("org.example.Utility"))
        XCTAssertTrue(service.diagnosticFrames.isEmpty)
        service.stopForModule()
        XCTAssertEqual(defaults.stringArray(forKey: "MacPocket.menuBarOrganizer.hiddenApplications"), ["org.example.Utility"])
    }

}

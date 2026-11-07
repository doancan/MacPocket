import XCTest
@testable import MacPocketCore

final class PermissionUsageTests: XCTestCase {
    func testAllOffLeavesOnlyAlwaysAvailableCoreFeaturesRelevant() {
        let relevant = OnboardingPermission.allCases.filter { PermissionUsageMap.usage($0, availableModules: []).isRelevant }
        XCTAssertEqual(relevant, [.fullDiskAccess, .location, .notifications])
        XCTAssertTrue(PermissionUsageMap.usage(.accessibility, availableModules: []).activeModules.isEmpty)
    }
    func testScreenshotAndScreenGrabUseScreenCaptureButNotAccessibility() {
        let active: Set<PocketModule> = [.screenGrab, .screenshot]
        XCTAssertEqual(PermissionUsageMap.usage(.screenRecording, availableModules: active).activeModules, [.screenGrab, .screenshot])
        XCTAssertFalse(PermissionUsageMap.usage(.accessibility, availableModules: active).isRelevant)
    }
    func testMouseBindingsDoNotImplyBatteryHIDInputMonitoring() {
        XCTAssertTrue(PermissionUsageMap.usage(.accessibility, availableModules: [.mouseButtons]).isRelevant)
        XCTAssertFalse(PermissionUsageMap.usage(.inputMonitoring, availableModules: [.mouseButtons]).isRelevant)
        XCTAssertTrue(PermissionUsageMap.usage(.inputMonitoring, availableModules: [.bluetoothBattery]).isRelevant)
        XCTAssertTrue(PermissionUsageMap.usage(.accessibility, availableModules: [.menuBarOrganizer]).isRelevant)
        XCTAssertFalse(PermissionUsageMap.usage(.screenRecording, availableModules: [.menuBarOrganizer]).isRelevant)
    }
    func testModuleChangesPartitionDependenciesWithoutDuplicates() {
        for permission in OnboardingPermission.allCases {
            let all = PermissionUsageMap.usage(permission, availableModules: Set(PocketModule.allCases))
            let off = PermissionUsageMap.usage(permission, availableModules: [])
            XCTAssertEqual(all.activeModules, off.inactiveModules)
            XCTAssertTrue(all.inactiveModules.isEmpty)
            XCTAssertEqual(Set(all.activeModules).count, all.activeModules.count)
        }
    }
    func testNotificationModulesAndAudioOnlyPermissionStayAccurate() {
        let notify = PermissionUsageMap.usage(.notifications, availableModules: [.focus, .privacy])
        XCTAssertEqual(notify.activeModules, [.privacy, .focus])
        XCTAssertFalse(PermissionUsageMap.usage(.screenRecording, availableModules: [.mixer]).isRelevant)
    }
}

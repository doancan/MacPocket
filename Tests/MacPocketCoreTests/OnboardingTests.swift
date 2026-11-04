import CoreGraphics
import XCTest
@testable import MacPocketCore

final class OnboardingTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testStepsMoveForwardAndBack() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .permissions, .preferences, .finish])
        XCTAssertTrue(OnboardingStep.welcome.isFirst)
        XCTAssertEqual(OnboardingStep.welcome.next, .permissions)
        XCTAssertEqual(OnboardingStep.finish.previous, .preferences)
        XCTAssertTrue(OnboardingStep.finish.isLast)
        XCTAssertNil(OnboardingStep.finish.next)
    }

    func testRecordPresentsOnceAndResumesAnInterruptedRun() {
        let store = defaults()
        XCTAssertTrue(OnboardingRecord.needsPresentation(store))
        XCTAssertEqual(OnboardingRecord.resumeStep(store), .welcome)
        OnboardingRecord.saveResumeStep(.permissions, store)
        XCTAssertEqual(OnboardingRecord.resumeStep(store), .permissions, "A relaunch for a permission comes back to the list")
        OnboardingRecord.markCompleted(store)
        XCTAssertFalse(OnboardingRecord.needsPresentation(store))
        XCTAssertEqual(OnboardingRecord.resumeStep(store), .welcome)
    }

    func testEveryPermissionOpensItsOwnPane() {
        let urls = OnboardingPermission.allCases.map { $0.settingsURL(bundleIdentifier: "com.example.app").absoluteString }
        XCTAssertEqual(Set(urls).count, urls.count)
        XCTAssertTrue(urls.allSatisfy { $0.hasPrefix("x-apple.systempreferences:") })
        XCTAssertEqual(OnboardingPermission.fullDiskAccess.settingsURL().absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        XCTAssertTrue(OnboardingPermission.notifications.settingsURL(bundleIdentifier: "com.example.app").absoluteString.hasSuffix("?id=com.example.app"))
        XCTAssertEqual(OnboardingPermission.allCases.filter(\.acceptsDraggedApp),
                       [.accessibility, .screenRecording, .fullDiskAccess, .inputMonitoring])
        XCTAssertTrue(OnboardingPermission.allCases.allSatisfy { $0.acceptsDraggedApp != $0.hasSystemPrompt })
    }

    func testFullDiskAccessProbeNeedsAReadableFile() throws {
        let readable = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString)")
        try Data("x".utf8).write(to: readable)
        defer { try? FileManager.default.removeItem(at: readable) }
        XCTAssertFalse(FullDiskAccessProbe.granted(checking: ["/nonexistent/\(UUID().uuidString)"]), "Missing files prove nothing")
        XCTAssertTrue(FullDiskAccessProbe.granted(checking: ["/nonexistent/x", readable.path]))
    }

    func testHelperSitsBesideTheSettingsWindowAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panel = CGSize(width: 300, height: 120)
        let centred = CGRect(x: 600, y: 300, width: 700, height: 600)
        XCTAssertEqual(PermissionHelperPlacement.frame(panel: panel, beside: centred, within: screen),
                       CGRect(x: 1312, y: 780, width: 300, height: 120), "Right of the window, top aligned")

        let rightEdge = CGRect(x: 1200, y: 300, width: 700, height: 600)
        let below = PermissionHelperPlacement.frame(panel: panel, beside: rightEdge, within: screen)
        XCTAssertEqual(below.maxY, rightEdge.minY - 12)

        let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let inside = PermissionHelperPlacement.frame(panel: panel, beside: full, within: screen)
        XCTAssertTrue(screen.contains(inside))

        XCTAssertEqual(PermissionHelperPlacement.appKitRect(fromWindowList: CGRect(x: 10, y: 100, width: 200, height: 300), primaryScreenHeight: 1080),
                       CGRect(x: 10, y: 680, width: 200, height: 300))
    }
}

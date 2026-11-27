import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class DockPreviewTests: XCTestCase {
    func testLayoutsFitEveryEdgeAndSecondaryScreenOrigins() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 120, width: 1920, height: 1080),
                       CGRect(x: 100, y: -900, width: 1280, height: 800), CGRect(x: 0, y: 0, width: 320, height: 240)] {
            for edge in DockEdge.allCases {
                let icon: CGRect
                switch edge {
                case .bottom: icon = CGRect(x: screen.maxX - 80, y: screen.minY, width: 56, height: 56)
                case .left: icon = CGRect(x: screen.minX, y: screen.minY + 20, width: 56, height: 56)
                case .right: icon = CGRect(x: screen.maxX - 56, y: screen.maxY - 80, width: 56, height: 56)
                }
                for count in [0, 1, 4, 20, 80] {
                    let layout = DockPreviewLayout.compute(count: count, icon: icon, visibleFrame: screen, edge: edge)
                    XCTAssertTrue(screen.insetBy(dx: 9, dy: 9).contains(layout.frame), "\(screen) \(edge) \(count): \(layout.frame)")
                    XCTAssertGreaterThan(layout.frame.width, 0)
                    XCTAssertGreaterThan(layout.frame.height, 0)
                    XCTAssertTrue((1...3).contains(layout.columns))
                    XCTAssertLessThanOrEqual(CGFloat(layout.columns) * layout.cardSize.width, layout.frame.width)
                }
            }
        }
    }

    func testPointerCanCrossGapAfterAutoHideWithoutOpeningBroadDeadZone() {
        let icon = CGRect(x: 100, y: 0, width: 50, height: 50)
        let panel = CGRect(x: 20, y: 90, width: 300, height: 240)
        for point in [CGPoint(x: 125, y: 25), CGPoint(x: 125, y: 70), CGPoint(x: 40, y: 120), CGPoint(x: 300, y: 300)] {
            XCTAssertTrue(DockPreviewGeometry.keepsOpen(point: point, icon: icon, panel: panel, edge: .bottom))
        }
        for point in [CGPoint(x: 30, y: 0), CGPoint(x: 310, y: 60), CGPoint(x: 500, y: 250), CGPoint(x: CGFloat.nan, y: 20)] {
            XCTAssertFalse(DockPreviewGeometry.keepsOpen(point: point, icon: icon, panel: panel, edge: .bottom))
        }
        XCTAssertTrue(DockPreviewGeometry.keepsOpen(point: CGPoint(x: 70, y: 125), icon: CGRect(x: 0, y: 100, width: 50, height: 50),
                                                  panel: CGRect(x: 90, y: 20, width: 240, height: 300), edge: .left))
        XCTAssertTrue(DockPreviewGeometry.keepsOpen(point: CGPoint(x: 350, y: 125), icon: CGRect(x: 370, y: 100, width: 50, height: 50),
                                                  panel: CGRect(x: 90, y: 20, width: 240, height: 300), edge: .right))
    }

    func testOnlyRelevantScreenEdgeRequiresAccessibilityHitTesting() {
        let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        XCTAssertTrue(DockPreviewGeometry.nearDock(CGPoint(x: -500, y: 120), screen: screen, edge: .bottom))
        XCTAssertFalse(DockPreviewGeometry.nearDock(CGPoint(x: -500, y: 700), screen: screen, edge: .bottom))
        XCTAssertFalse(DockPreviewGeometry.nearDock(CGPoint(x: 10, y: 120), screen: screen, edge: .right))
        XCTAssertTrue(DockPreviewGeometry.nearDock(CGPoint(x: -1420, y: 400), screen: screen, edge: .left))
    }

    func testSettingsAreOptInBoundedAndExclusionsSurviveRelaunch() throws {
        let defaults = temporaryDefaults()
        XCTAssertFalse(DockPreviewSettings.load(from: defaults).enabled)
        var settings = DockPreviewSettings()
        settings.enabled = true
        settings.hoverDelayMilliseconds = Int.max
        settings.hideDelayMilliseconds = -100
        settings.excludedPaths = ["/Applications/Test.app", "/Applications/Test.app", "relative"]
        settings.save(to: defaults)
        let restored = DockPreviewSettings.load(from: defaults)
        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(restored.hoverDelayMilliseconds, 1200)
        XCTAssertEqual(restored.hideDelayMilliseconds, 100)
        XCTAssertEqual(restored.excludedPaths, ["/Applications/Test.app"])
    }

    func testScopedCatalogNeverFallsBackToAllApplicationsAndRejectsStaleLayoutTargets() async {
        let catalog = WindowCatalog()
        let empty = await catalog.snapshot(processIDs: [], includingCurrentApplication: true)
        XCTAssertTrue(empty.windows.isEmpty)
        let wrongApplication = await catalog.snapshot(processIDs: [ProcessInfo.processInfo.processIdentifier], includingCurrentApplication: true,
                                                     matchingApplicationURL: URL(fileURLWithPath: "/Applications/Not-The-Running-App.app"))
        XCTAssertTrue(wrongApplication.windows.isEmpty)
        do { try await catalog.layout(.leftHalf, on: "not-a-live-window"); XCTFail("Unknown target accepted") }
        catch WindowCatalogError.expired {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

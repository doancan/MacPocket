import XCTest
@testable import MacPocketCore

final class DisplayModesTests: XCTestCase {
    /// A slice of the MateView (3840 × 2560 panel) mode list on this Mac.
    private let modes: [DisplayModeInfo] = [
        .init(id: 0, width: 800, height: 533, pixelWidth: 1600, pixelHeight: 1066, refreshRate: 60),
        .init(id: 1, width: 800, height: 533, pixelWidth: 1600, pixelHeight: 1066, refreshRate: 30),
        .init(id: 3, width: 800, height: 600, pixelWidth: 800, pixelHeight: 600, refreshRate: 60),
        .init(id: 8, width: 1024, height: 682, pixelWidth: 1024, pixelHeight: 682, refreshRate: 60),
        .init(id: 10, width: 1024, height: 683, pixelWidth: 2048, pixelHeight: 1366, refreshRate: 60),
        .init(id: 46, width: 1920, height: 1280, pixelWidth: 3840, pixelHeight: 2560, refreshRate: 60),
        .init(id: 48, width: 1920, height: 1280, pixelWidth: 3840, pixelHeight: 2560, refreshRate: 30),
        .init(id: 47, width: 1920, height: 1280, pixelWidth: 1920, pixelHeight: 1280, refreshRate: 60),
        .init(id: 62, width: 2560, height: 1707, pixelWidth: 5120, pixelHeight: 3414, refreshRate: 60),
        .init(id: 60, width: 2560, height: 1706, pixelWidth: 2560, pixelHeight: 1706, refreshRate: 60),
        .init(id: 999, width: 3840, height: 2560, pixelWidth: 3840, pixelHeight: 2560, refreshRate: 60),
        .init(id: 500, width: 640, height: 480, pixelWidth: 640, pixelHeight: 480, refreshRate: 60, usableForDesktop: false),
    ]

    func testHiDPIResolutionsFirstClassAndLowResolutionOnRequest() {
        let sharp = DisplayModeCatalog.resolutions(modes, includeLowResolution: false)
        XCTAssertEqual(sharp.map(\.id), ["800x533@2x", "1024x683@2x", "1920x1280@2x", "2560x1707@2x"])
        XCTAssertEqual(sharp[0].refreshRates, [60, 30])
        XCTAssertEqual(sharp[0].mode(refresh: 30)?.id, 1)
        XCTAssertEqual(sharp[0].mode(refresh: nil)?.id, 0, "Highest refresh by default")
        let all = DisplayModeCatalog.resolutions(modes, includeLowResolution: true)
        XCTAssertTrue(all.contains { $0.id == "3840x2560" })
        XCTAssertTrue(all.contains { $0.id == "1920x1280" })
        XCTAssertFalse(all.contains { $0.width == 640 }, "Not usable for the desktop")
    }

    func testNearDuplicatesCollapse() {
        let all = DisplayModeCatalog.resolutions(modes, includeLowResolution: true)
        XCTAssertEqual(all.filter { !$0.isHiDPI && $0.width == 1024 }.count, 1)
        XCTAssertEqual(all.filter { !$0.isHiDPI && $0.width == 2560 }.count, 1)
    }

    func testLowResolutionOnlyDisplaysStillListModes() {
        let plain: [DisplayModeInfo] = [.init(id: 1, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144),
                                        .init(id: 2, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60),
                                        .init(id: 3, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60)]
        let resolutions = DisplayModeCatalog.resolutions(plain, includeLowResolution: false)
        XCTAssertEqual(resolutions.map(\.id), ["1280x720", "1920x1080"])
        XCTAssertEqual(resolutions[1].refreshRates, [144, 60])
    }

    func testRecommendedIsNativeAtTwoX() throws {
        let native = try XCTUnwrap(DisplayModeCatalog.nativePixels(modes))
        XCTAssertEqual(native.width, 3840)
        let resolutions = DisplayModeCatalog.resolutions(modes, includeLowResolution: false)
        XCTAssertEqual(DisplayModeCatalog.recommended(resolutions, native: native)?.id, "1920x1280@2x")
    }

    func testMakingAnotherDisplayMainShiftsEveryOrigin() {
        let origins: [UInt32: (x: Int32, y: Int32)] = [3: (0, 0), 1: (2560, -120)]
        let moved = DisplayArrangement.originsMakingMain(1, origins: origins)
        XCTAssertEqual(moved[1]?.x, 0); XCTAssertEqual(moved[1]?.y, 0)
        XCTAssertEqual(moved[3]?.x, -2560); XCTAssertEqual(moved[3]?.y, 120)
    }

    func testConfirmationCountsDown() {
        let start = Date(timeIntervalSince1970: 1000)
        let confirmation = DisplayChangeConfirmation(startedAt: start)
        XCTAssertEqual(confirmation.remaining(at: start), 15)
        XCTAssertEqual(confirmation.remaining(at: start.addingTimeInterval(14.2)), 1)
        XCTAssertFalse(confirmation.expired(at: start.addingTimeInterval(14.9)))
        XCTAssertTrue(confirmation.expired(at: start.addingTimeInterval(15)))
    }
}

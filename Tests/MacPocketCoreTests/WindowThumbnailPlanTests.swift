import XCTest
@testable import MacPocketCore

final class WindowThumbnailPlanTests: XCTestCase {
    private func window(_ index: Int, minimized: Bool = false, windowless: Bool = false) -> SwitchableWindow {
        .init(id: "w\(index)", processID: 1, application: "Fixture", title: "Document \(index)", applicationURL: nil,
              minimized: minimized, hidden: false, fullScreen: false, frontmost: false, windowAccessible: false,
              canClose: false, canMinimize: false, canFullScreen: false, launchedAt: nil, lastFocusedAt: nil,
              windowID: windowless ? nil : UInt32(index + 1))
    }

    func testSelectedWindowBeyondFirstBatchAlwaysGetsAnImage() {
        let windows = (0..<80).map { window($0) }
        let targets = WindowThumbnailPlan.targets(windows, selection: "w79", visibleIDs: [])
        XCTAssertEqual(targets.first?.id, "w79")
        XCTAssertEqual(targets.count, 48)
        XCTAssertEqual(Set(targets.map(\.id)).count, 48)
    }

    func testScrollingCapturesNewViewportInsteadOfFirstPage() {
        let windows = (0..<80).map { window($0) }
        XCTAssertEqual(WindowThumbnailPlan.targets(windows, selection: "w62", visibleIDs: ["w60", "w61", "w62"]).map(\.id),
                       ["w62", "w60", "w61"])
    }

    func testMinimizedWindowKeepsCacheWithoutBeingCaptured() {
        let windows = [window(0), window(1, minimized: true), window(2, windowless: true)]
        XCTAssertEqual(WindowThumbnailPlan.targets(windows, selection: "w1", visibleIDs: ["w0", "w1", "w2"]).map(\.id), ["w0"])
        XCTAssertTrue(WindowThumbnailPlan.targets(windows, selection: "w0", visibleIDs: [], limit: 0).isEmpty)
    }

    func testRetinaPreviewUsesNativePixelsWithoutUpscaling() {
        XCTAssertEqual(WindowPreviewSizing.pixels(contentSize: CGSize(width: 800, height: 600), pixelScale: 2,
                                                maxPixels: CGSize(width: 1600, height: 1200)), CGSize(width: 1600, height: 1200))
        XCTAssertEqual(WindowPreviewSizing.pixels(contentSize: CGSize(width: 800, height: 600), pixelScale: 1,
                                                maxPixels: CGSize(width: 1600, height: 1200)), CGSize(width: 800, height: 600))
        XCTAssertEqual(WindowPreviewSizing.pixels(contentSize: CGSize(width: 800, height: 600), pixelScale: 2,
                                                maxPixels: CGSize(width: 400, height: 250)), CGSize(width: 333, height: 250))
        XCTAssertNil(WindowPreviewSizing.pixels(contentSize: .zero, pixelScale: 2, maxPixels: CGSize(width: 400, height: 250)))
        XCTAssertNil(WindowPreviewSizing.pixels(contentSize: CGSize(width: 800, height: 600), pixelScale: .nan,
                                               maxPixels: CGSize(width: 400, height: 250)))
    }
}

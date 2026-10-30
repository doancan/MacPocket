import XCTest
@testable import MacPocketCore

final class WorkspaceMatcherTests: XCTestCase {
    private func window(_ title: String, x: CGFloat = 0) -> SavedWindow {
        SavedWindow(bundleID: "com.apple.Safari", title: title, frame: CGRect(x: x, y: 0, width: 800, height: 600))
    }

    func testSameTitleWinsThenOrder() {
        let saved = [window("Belgeler", x: 1), window("GitHub", x: 2), window("", x: 3)]
        let pairs = WorkspaceMatcher.match(saved: saved, currentTitles: ["GitHub", "Yeni Sekme", "Belgeler"])
        let byX = Dictionary(uniqueKeysWithValues: pairs.map { ($0.saved.frame.minX, $0.index) })
        XCTAssertEqual(byX[1], 2, "“Belgeler” finds its window wherever it is now")
        XCTAssertEqual(byX[2], 0)
        XCTAssertEqual(byX[3], 1, "untitled takes the remaining window")
    }

    func testFewerCurrentWindowsLeavesTheRest() {
        let pairs = WorkspaceMatcher.match(saved: [window("A"), window("B"), window("C")], currentTitles: ["X"])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.index, 0)
    }

    func testMoreCurrentWindowsAreLeftAlone() {
        XCTAssertEqual(WorkspaceMatcher.match(saved: [window("A")], currentTitles: ["A", "B", "C"]).map(\.index), [0])
        XCTAssertTrue(WorkspaceMatcher.match(saved: [window("A")], currentTitles: []).isEmpty)
    }

    func testReachabilityProtectsAgainstMissingDisplays() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertTrue(WorkspaceMatcher.isReachable(CGRect(x: 100, y: 100, width: 800, height: 600), screens: screens))
        XCTAssertFalse(WorkspaceMatcher.isReachable(CGRect(x: 2000, y: 100, width: 800, height: 600), screens: screens),
                       "saved on an external display that's gone")
        XCTAssertFalse(WorkspaceMatcher.isReachable(CGRect(x: 1420, y: 100, width: 800, height: 600), screens: screens),
                       "only a sliver of the title bar would be visible")
    }

    func testApplicationsAreUniqueInOrder() {
        let layout = WorkspaceLayout(name: "Kod", windows: [
            SavedWindow(bundleID: "a", title: "", frame: .zero), SavedWindow(bundleID: "b", title: "", frame: .zero),
            SavedWindow(bundleID: "a", title: "2", frame: .zero),
        ], savedAt: Date())
        XCTAssertEqual(layout.applications, ["a", "b"])
    }

    func testStoreRoundTrip() throws {
        let store = WorkspaceStore(layouts: [WorkspaceLayout(name: "Toplantı", windows: [window("Zoom")],
                                                             shortcut: KeyCombo(keyCode: 46, modifiers: [.control, .option]),
                                                             savedAt: Date(timeIntervalSince1970: 1_800_000_000))])
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceStore.self, from: JSONEncoder().encode(store)), store)
    }
}

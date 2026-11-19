import XCTest
@testable import MacPocketApp
@testable import MacPocketCore

@MainActor final class MenuBarLauncherTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "MacPocket.LauncherTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testFavoritesPersistInTheirOwnDefaultsWithoutDuplicates() {
        let store = LauncherStore(defaults: defaults)
        let safari = URL(fileURLWithPath: "/Applications/Safari.app"), downloads = URL(fileURLWithPath: "/Users/Shared")
        store.add([safari, downloads, safari])
        store.add([downloads])
        XCTAssertEqual(store.items.map(\.url), [safari, downloads])
        XCTAssertEqual(LauncherStore(defaults: defaults).items.map(\.url), [safari, downloads], "reloads from the same defaults")
        XCTAssertNil(UserDefaults.standard.data(forKey: "MacPocket.menubar.launcher.test-leak"))
    }

    func testCapacityLimitsTheGrid() {
        let store = LauncherStore(defaults: defaults)
        store.add((0..<(LauncherStore.capacity + 5)).map { URL(fileURLWithPath: "/tmp/item\($0)") })
        XCTAssertEqual(store.items.count, LauncherStore.capacity)
    }

    func testRemoveForgetsTheFavorite() throws {
        let store = LauncherStore(defaults: defaults)
        store.add([URL(fileURLWithPath: "/Applications")])
        store.remove(try XCTUnwrap(store.items.first))
        XCTAssertTrue(LauncherStore(defaults: defaults).items.isEmpty)
    }

    func testCorruptDataStartsEmptyInsteadOfCrashing() {
        defaults.set(Data("not json".utf8), forKey: "MacPocket.menubar.launcher")
        XCTAssertTrue(LauncherStore(defaults: defaults).items.isEmpty)
    }

    func testWebAddressAcceptsOnlyHTTPWithAHost() {
        XCTAssertEqual(LauncherStore.webAddress("apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(LauncherStore.webAddress("  http://example.org/path ")?.absoluteString, "http://example.org/path")
        // Internationalized hosts are accepted (Foundation encodes them; the encoding is its business).
        XCTAssertNotNil(LauncherStore.webAddress("https://türkçe.örnek")?.host())
        XCTAssertNil(LauncherStore.webAddress(""))
        XCTAssertNil(LauncherStore.webAddress("file:///etc/passwd"))
        XCTAssertNil(LauncherStore.webAddress("javascript://alert(1)"))
        XCTAssertNil(LauncherStore.webAddress("https://"))
    }

    func testChartRangesMapToTheRecordedHistory() {
        XCTAssertNil(ChartRange.live.metricRange)
        XCTAssertEqual(ChartRange.allCases.compactMap(\.metricRange), MetricRange.allCases)
    }
}

@MainActor final class MenuBarPageLinksTests: XCTestCase {
    func testLinksPreferTheTabThenTheMainWindowAndOtherwiseAreUnavailable() {
        var selected: MenuBarModule?, opened: PocketPage?
        let links = MenuBarPageLinks(tabs: [.overview, .cpu], selectTab: { selected = $0 }, openPage: { opened = $0 })
        links.open(.cpu)
        XCTAssertEqual(selected, .cpu); XCTAssertNil(opened)
        links.open(.disk)
        XCTAssertEqual(opened, .storage, "no Disk tab: the main window's Disk Analysis page")
        XCTAssertFalse(links.canOpen(.timeline), "no tab and no page: the link is disabled")
        XCTAssertTrue(MenuBarPageLinks().canOpen(.power), "a separate popover still reaches the main window")
    }
}

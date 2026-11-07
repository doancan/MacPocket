import AppKit
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

private actor ProjectionCatalog: WindowCatalogServing {
    private var rows: [SwitchableWindow]
    init(_ rows: [SwitchableWindow]) { self.rows = rows }
    func replace(_ rows: [SwitchableWindow]) { self.rows = rows }
    func snapshot() async -> WindowCatalogReport { .init(windows: rows,accessibilityGranted: true,partial: false) }
    func focus(_ id: String) async throws {}
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

@MainActor final class WindowSwitcherProjectionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "WindowSwitcherProjectionTests."+UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("title",forKey: "switcher.sort")
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }
    private var rows: [SwitchableWindow] {
        (0..<3).map { (index: Int) -> SwitchableWindow in
            SwitchableWindow(id: ["a","b","c"][index],processID: index == 1 ? 202 : 101,application: index == 1 ? "B" : "A",
                title: ["Alpha","Beta","Gamma"][index],applicationURL: nil,minimized: index == 2,hidden: false,fullScreen: false,
                frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,
                launchedAt: Date(timeIntervalSince1970: 1),lastFocusedAt: Date(timeIntervalSince1970: Double(index)),windowID: UInt32(index+1),
                frame: CGRect(x: index == 1 ? 200 : 0,y: 0,width: 100,height: 100),displayID: index == 1 ? 2 : 1,zOrder: index,
                bundleIdentifier: index == 1 ? "com.example.B" : "com.example.A")
        }
    }
    func testEachModelsSortDomainAndExternalPreferenceChangeAreRespected() {
        let first = defaults(),second = defaults()
        second.set("recent",forKey: "switcher.sort")
        let a = WindowSwitcherModel(windows: rows,defaults: first),b = WindowSwitcherModel(windows: rows,defaults: second)
        XCTAssertEqual(a.filtered.map(\.id),["a","b","c"])
        XCTAssertEqual(b.filtered.map(\.id),["c","b","a"])
        first.set("recent",forKey: "switcher.sort")
        XCTAssertEqual(a.filtered.map(\.id),["c","b","a"])
        second.set("title",forKey: "switcher.sort")
        XCTAssertEqual(b.filtered.map(\.id),["a","b","c"])
    }
    func testTableAndSessionSearchRemainIndependentAfterRepeatedReads() {
        let model = WindowSwitcherModel(windows: rows,defaults: defaults())
        model.search = "Beta";XCTAssertEqual(model.filtered.map(\.id),["b"])
        model.sessionFilter = .init();model.sessionSearch = "Alpha"
        XCTAssertEqual(model.filtered.map(\.id),["a"])
        model.sessionSearch = "Gamma";XCTAssertEqual(model.filtered.map(\.id),["c"])
        model.sessionSearch = "";XCTAssertEqual(model.filtered.count,3)
        model.sessionFilter = nil;XCTAssertEqual(model.filtered.map(\.id),["b"])
        model.search = "";XCTAssertEqual(model.filtered.count,3)
    }
    func testForegroundDisplayAndPointerContextEditsUpdateVisibleRowsImmediately() {
        let model = WindowSwitcherModel(windows: rows,defaults: defaults())
        var filter = WindowListFilter();filter.applicationScope = .frontmost
        model.sessionFilter = filter;model.foregroundPID = 101
        XCTAssertEqual(model.filtered.map(\.id),["a","c"])
        model.foregroundPID = 202;XCTAssertEqual(model.filtered.map(\.id),["b"])
        filter.applicationScope = .all;filter.currentScreenOnly = true;model.sessionFilter = filter
        model.sessionDisplayID = 1;XCTAssertEqual(model.filtered.map(\.id),["a","c"])
        model.sessionDisplayID = 2;XCTAssertEqual(model.filtered.map(\.id),["b"])
        filter.currentScreenOnly = false;filter.applicationScope = .pointerWindows;model.sessionFilter = filter
        model.captureSessionPointer(at: CGPoint(x: 10,y: 10));XCTAssertEqual(model.filtered.map(\.id),["a"])
        model.captureSessionPointer(at: CGPoint(x: 210,y: 10));XCTAssertEqual(model.filtered.map(\.id),["b"])
        filter.applicationScope = .pointerApplication;model.sessionFilter = filter
        model.captureSessionPointer(at: CGPoint(x: 10,y: 10));XCTAssertEqual(model.filtered.map(\.id),["a","c"])
        model.captureSessionPointer(at: nil);XCTAssertTrue(model.filtered.isEmpty)
    }
    func testInPlaceFilterEditsSessionOrderAndSelectionKeepCorrectProjection() {
        let model = WindowSwitcherModel(windows: rows,defaults: defaults())
        model.sessionFilter = .init();XCTAssertEqual(model.filtered.map(\.id),["a","b","c"])
        model.sessionFilter?.includeMinimized = false;XCTAssertEqual(model.filtered.map(\.id),["a","b"])
        model.sessionFilter?.includeMinimized = true;model.sessionOrder = .recent
        XCTAssertEqual(model.filtered.map(\.id),["c","b","a"])
        model.selection = "a";XCTAssertEqual(model.selected?.title,"Alpha")
        model.selection = "b";XCTAssertEqual(model.selected?.title,"Beta")
        model.sessionFilter?.grouping = .onePerApplication;XCTAssertEqual(model.filtered.map(\.id),["c","b"])
        model.sessionOrder = .title;XCTAssertEqual(model.filtered.map(\.id),["a","b"])
    }
    func testExceptionReloadAndCatalogReplacementDoNotReuseRemovedWindows() async {
        let defaults = defaults(),catalog = ProjectionCatalog(rows)
        let model = WindowSwitcherModel(windows: rows,catalog: catalog,defaults: defaults)
        XCTAssertEqual(model.filtered.count,3)
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundleIdentifier,value: "com.example.A",visibility: .alwaysHide)],defaults))
        model.reloadExceptions();XCTAssertEqual(model.filtered.map(\.id),["b"])
        XCTAssertTrue(SwitcherExceptionStore.save([],defaults));model.reloadExceptions()
        XCTAssertEqual(model.filtered.count,3)
        await catalog.replace([rows[2]]);await model.refresh()
        XCTAssertEqual(model.filtered.map(\.id),["c"])
        await catalog.replace([]);await model.refresh();XCTAssertTrue(model.filtered.isEmpty)
    }
}

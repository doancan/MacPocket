import AppKit
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

private actor CommandCatalogFixture: WindowCatalogServing {
    var report: WindowCatalogReport
    private(set) var focuses: [String] = []
    var rejectsFocus = false
    var delay: Duration = .zero
    init(_ rows: [SwitchableWindow],trusted: Bool = true) { report = .init(windows: rows,accessibilityGranted: trusted,partial: true,spaceMetadataPartial: true) }
    func configure(reject: Bool = false,delay: Duration = .zero) { rejectsFocus = reject;self.delay = delay }
    func snapshot() async -> WindowCatalogReport { try? await Task.sleep(for: delay);return report }
    func focus(_ id: String) async throws { if rejectsFocus { throw WindowCatalogError.focusFailed };focuses.append(id) }
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

@MainActor final class SwitcherCommandServiceTests: XCTestCase {
    private func row(_ id: String,windowID: UInt32?,focused: Double,frontmost: Bool = false) -> SwitchableWindow {
        .init(id: id,processID: 10,application: "Fixture",title: id,applicationURL: nil,minimized: false,hidden: false,fullScreen: false,
              frontmost: frontmost,windowAccessible: windowID != nil,canClose: false,canMinimize: false,canFullScreen: false,
              launchedAt: nil,lastFocusedAt: Date(timeIntervalSince1970: focused),windowID: windowID)
    }
    private func service(_ catalog: CommandCatalogFixture) -> (SwitcherCommandService,WindowSwitcherModel) {
        let model = WindowSwitcherModel(catalog: catalog)
        return (SwitcherCommandService(model: model,show: { _ in false },hide: {},visible: { false }),model)
    }
    func testListUsesFreshMRUExcludesWindowlessAndPreservesTableSelection() async {
        let catalog = CommandCatalogFixture([row("old",windowID: 41,focused: 1),row("new",windowID: 42,focused: 2),row("empty",windowID: nil,focused: 3)])
        let (service,model) = service(catalog);model.selection = "unchanged";model.search = "no results"
        let reply = await service.execute(.init(command: .list(detailed: true)))
        XCTAssertEqual(reply.windows?.map(\.id),["new","old"]);XCTAssertEqual(reply.windows?.map(\.mru),[1,2])
        XCTAssertEqual(reply.windows?.first?.details?.processID,10);XCTAssertEqual(reply.partial,true);XCTAssertEqual(reply.spaceMetadataPartial,true)
        XCTAssertEqual(model.selection,"unchanged");XCTAssertEqual(model.search,"no results")
    }
    func testFocusByOpaqueIDNumericWindowIDAndMRUUseSameCatalog() async {
        let catalog = CommandCatalogFixture([row("old",windowID: 41,focused: 1),row("new",windowID: 42,focused: 2)])
        let (service,_) = service(catalog)
        for command in [SwitcherCLICommand.focus("old"),.focus("42"),.focusMRU(2)] {
            let response = await service.execute(.init(command: command));XCTAssertEqual(response.status,"focused");XCTAssertNil(response.errorCode)
        }
        let focuses = await catalog.focuses;XCTAssertEqual(focuses,["old","new","old"])
    }
    func testMissingWindowAndMRUOutOfRangeDoNotFallBackToAnotherTarget() async {
        let catalog = CommandCatalogFixture([row("one",windowID: 41,focused: 1)]), (service,_) = service(catalog)
        for command in [SwitcherCLICommand.focus("expired"),.focusMRU(2)] {
            let response = await service.execute(.init(command: command));XCTAssertEqual(response.errorCode,"not-found")
        }
        let focuses = await catalog.focuses;XCTAssertTrue(focuses.isEmpty)
    }
    func testPermissionDenialAndFocusFailureAreNotReportedAsSuccess() async {
        let rows = [row("one",windowID: 41,focused: 1)]
        let denied = service(CommandCatalogFixture(rows,trusted: false)).0
        let denial = await denied.execute(.init(command: .focus("41")));XCTAssertEqual(denial.errorCode,"permission-required")
        let catalog = CommandCatalogFixture(rows);await catalog.configure(reject: true)
        let rejected = await service(catalog).0.execute(.init(command: .focus("41")));XCTAssertEqual(rejected.errorCode,"focus-failed")
    }
    func testExpiredScanCannotFocusAfterItsDeadline() async {
        let catalog = CommandCatalogFixture([row("one",windowID: 41,focused: 1)]);await catalog.configure(delay: .milliseconds(70))
        let reply = await service(catalog).0.execute(.init(command: .focus("41"),expiresAt: Date().addingTimeInterval(0.02)))
        XCTAssertEqual(reply.errorCode,"expired");let focuses = await catalog.focuses;XCTAssertTrue(focuses.isEmpty)
    }
    func testShowHideAndStatusUsePanelRoutingWithoutFocusingAWindow() async {
        let catalog = CommandCatalogFixture([]),model = WindowSwitcherModel(catalog: catalog)
        var visible = false,profiles: [Int] = [],hides = 0
        let service = SwitcherCommandService(model: model,show: { profiles.append($0);visible = true;return true },hide: { hides += 1;visible = false },visible: { visible })
        let show = await service.execute(.init(command: .show(3)));XCTAssertEqual(show.status,"opening");XCTAssertEqual(show.panelVisible,true)
        let status = await service.execute(.init(command: .status));XCTAssertEqual(status.panelVisible,true)
        let hide = await service.execute(.init(command: .hide));XCTAssertEqual(hide.status,"hidden");XCTAssertEqual(hide.panelVisible,false)
        XCTAssertEqual(profiles,[3]);XCTAssertEqual(hides,1);let focuses = await catalog.focuses;XCTAssertTrue(focuses.isEmpty)
    }
    func testUnavailableProfileAndInvalidWireCommandDoNotSucceed() async {
        let catalog = CommandCatalogFixture([]),(service,_) = service(catalog)
        let missing = await service.execute(.init(command: .show(9)));XCTAssertEqual(missing.errorCode,"unavailable")
        let invalid = await service.execute(.init(command: .show(0)));XCTAssertEqual(invalid.errorCode,"invalid-command")
    }
}

import AppKit
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp
import MacPocketTestSupport

private actor FullscreenRuleFixture {
    private var value: Bool?
    private var continuation: CheckedContinuation<Bool?, Never>?
    private var blocked = false
    private(set) var requests = 0
    init(_ value: Bool?) { self.value = value }
    func set(_ value: Bool?) { self.value = value }
    func block() { blocked = true }
    func release(_ value: Bool?) { blocked = false; continuation?.resume(returning: value); continuation = nil }
    var waiting: Bool { continuation != nil }
    func read(_ application: SwitcherForegroundApplication) async -> Bool? {
        requests += 1
        if blocked { return await withCheckedContinuation { continuation = $0 } }
        return value
    }
}

@MainActor final class SwitcherExceptionIntegrationTests: XCTestCase {
    private let application = SwitcherForegroundApplication(processID: 1, launchedAt: Date(timeIntervalSince1970: 10),
        bundleIdentifier: "com.example.Editor", applicationPath: "/Applications/Editor.app", name: "Editor")
    private func defaults() -> UserDefaults {
        temporaryDefaults()
    }
    private func window(_ id: String) -> SwitchableWindow {
        .init(id: id, processID: 1, application: "Editor", title: id, applicationURL: URL(fileURLWithPath: "/Applications/Editor.app"),
              minimized: false, hidden: false, fullScreen: false, frontmost: true, windowAccessible: true,
              canClose: true, canMinimize: true, canFullScreen: true, launchedAt: nil, lastFocusedAt: nil, windowID: 1,
              bundleIdentifier: "com.example.Editor")
    }
    private func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(3) {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    func testTitleRuleUpdatesTableAndActiveSessionWithoutRefreshingCatalog() {
        let d = defaults()
        let configured = WindowSwitcherModel(windows: [window("Private"),window("Report")], defaults: d)
        XCTAssertEqual(configured.filtered.count,2)
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundlePrefix,value: "com.example",visibility: .titleContains,titlePatterns: ["Private"])],d))
        configured.reloadExceptions()
        XCTAssertEqual(configured.filtered.map(\.id),["Report"])
        configured.sessionFilter = .init()
        configured.foregroundPID = 1
        XCTAssertEqual(configured.filtered.map(\.id),["Report"])
        XCTAssertTrue(SwitcherExceptionStore.save([],d))
        configured.reloadExceptions()
        XCTAssertEqual(configured.filtered.count,2)
    }
    func testQuickExcludeUsesUnifiedStoreAndPreservesConditionalRules() {
        let d = defaults(), conditional = SwitcherExceptionRule(target: .bundlePrefix,value: "com.example",shortcuts: .fullscreen)
        XCTAssertTrue(SwitcherExceptionStore.save([conditional],d))
        let model = WindowSwitcherModel(windows: [window("Report")],defaults: d)
        model.selection = "Report"
        model.excludeSelected()
        XCTAssertTrue(model.filtered.isEmpty)
        XCTAssertNil(model.selection)
        XCTAssertEqual(SwitcherExceptionStore.load(d).rules.first,conditional)
        XCTAssertEqual(SwitcherExceptionStore.load(d).rules.count,2)
    }
    func testQuickExcludeDoesNotOverwriteUnreadablePreferences() {
        let d = defaults(), data = Data("unknown future data".utf8)
        d.set(data,forKey: SwitcherExceptionStore.key)
        let model = WindowSwitcherModel(windows: [window("Report")],defaults: d)
        model.selection = "Report"
        model.excludeSelected()
        XCTAssertNotNil(model.failure)
        XCTAssertEqual(model.selection,"Report")
        XCTAssertEqual(d.data(forKey: SwitcherExceptionStore.key),data)
    }
    func testAlwaysDisableAppliesOnStartupAndPreferenceEditWithoutForegroundActivation() async {
        let d = defaults(), reader = FullscreenRuleFixture(true)
        let model = WindowSwitcherModel(defaults: d), application = application
        let controller = WindowSwitcherHotkeyController(model: model,exceptionApplication: { application },fullscreenReader: { await reader.read($0) })
        defer { controller.stopForModule() }
        controller.updateExceptionsForAudit()
        XCTAssertNil(controller.suspendedForApplication)
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundleIdentifier,value: "com.example.Editor",shortcuts: .alwaysDisable)],d))
        controller.updateExceptionsForAudit()
        XCTAssertEqual(controller.suspendedForApplication,"Editor")
        XCTAssertEqual(controller.moduleDiagnosticResources["conditionalExceptionTask"],0)
        let calls = await reader.requests
        XCTAssertEqual(calls,0)
        XCTAssertTrue(SwitcherExceptionStore.save([],d))
        controller.updateExceptionsForAudit()
        XCTAssertNil(controller.suspendedForApplication)
    }
    func testSameAppFullscreenTransitionsAndUnknownAXStateUpdateWithoutActivation() async {
        let d = defaults(), reader = FullscreenRuleFixture(false), application = application
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundlePrefix,value: "com.example",shortcuts: .fullscreen)],d))
        let controller = WindowSwitcherHotkeyController(model: WindowSwitcherModel(defaults: d),exceptionApplication: { application },fullscreenReader: { await reader.read($0) })
        defer { controller.stopForModule() }
        controller.updateExceptionsForAudit()
        XCTAssertNil(controller.suspendedForApplication)
        await reader.set(true)
        let suspended = await wait { controller.suspendedForApplication == "Editor" }
        XCTAssertTrue(suspended)
        await reader.set(false)
        let resumed = await wait { controller.suspendedForApplication == nil }
        XCTAssertTrue(resumed)
        await reader.set(true)
        let suspendedAgain = await wait { controller.suspendedForApplication != nil }
        XCTAssertTrue(suspendedAgain)
        await reader.set(nil)
        let unknown = await wait { controller.suspendedForApplication == nil }
        XCTAssertTrue(unknown)
        XCTAssertEqual(controller.moduleDiagnosticResources["hotKeys"],0,"Audit must never take global keys")
        controller.stopForModule()
        XCTAssertEqual(controller.moduleDiagnosticResources["conditionalExceptionTask"],0)
    }
    func testLateFullscreenSampleCannotResuspendAfterRuleRemovalOrStop() async {
        let d = defaults(), reader = FullscreenRuleFixture(true), application = application
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundlePrefix,value: "com.example",shortcuts: .fullscreen)],d))
        await reader.block()
        let controller = WindowSwitcherHotkeyController(model: WindowSwitcherModel(defaults: d),exceptionApplication: { application },fullscreenReader: { await reader.read($0) })
        controller.updateExceptionsForAudit()
        let waiting = await wait { await reader.waiting }
        XCTAssertTrue(waiting)
        XCTAssertTrue(SwitcherExceptionStore.save([],d))
        controller.updateExceptionsForAudit()
        await reader.release(true)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(controller.suspendedForApplication)
        XCTAssertEqual(controller.moduleDiagnosticResources["conditionalExceptionTask"],0)
        controller.stopForModule()
    }
    func testStoppingDuringAnAXReadCancelsTheLoopAndRejectsItsLateResult() async {
        let d = defaults(), reader = FullscreenRuleFixture(true), application = application
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundlePrefix,value: "com.example",shortcuts: .fullscreen)],d))
        await reader.block()
        let controller = WindowSwitcherHotkeyController(model: WindowSwitcherModel(defaults: d),exceptionApplication: { application },fullscreenReader: { await reader.read($0) })
        controller.updateExceptionsForAudit()
        let waiting = await wait { await reader.waiting }
        XCTAssertTrue(waiting)
        controller.stopForModule()
        await reader.release(true)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(controller.suspendedForApplication)
        XCTAssertEqual(controller.moduleDiagnosticResources["conditionalExceptionTask"],0)
        let calls = await reader.requests
        XCTAssertEqual(calls,1)
    }
    func testChangingForegroundApplicationCannotInheritALateFullscreenResult() async {
        let d = defaults(), reader = FullscreenRuleFixture(true)
        var foreground: SwitcherForegroundApplication? = application
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundlePrefix,value: "com.example",shortcuts: .fullscreen)],d))
        await reader.block()
        let controller = WindowSwitcherHotkeyController(model: WindowSwitcherModel(defaults: d),exceptionApplication: { foreground },fullscreenReader: { await reader.read($0) })
        defer { controller.stopForModule() }
        controller.updateExceptionsForAudit()
        let waiting = await wait { await reader.waiting }
        XCTAssertTrue(waiting)
        foreground = .init(processID: 2,launchedAt: Date(timeIntervalSince1970: 20),bundleIdentifier: "org.other.Editor",applicationPath: "/Applications/Other.app")
        controller.updateExceptionsForAudit()
        await reader.release(true)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(controller.suspendedForApplication)
        XCTAssertEqual(controller.moduleDiagnosticResources["conditionalExceptionTask"],0)
    }

}

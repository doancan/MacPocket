import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

@MainActor private final class UninstallProcessFixture: UninstallProcessManaging {
    var processes: [UninstallRunningProcess] = []
    var calls: [(Int32, Bool)] = []
    var ignoresQuit = false
    var inspectCount = 0
    var relaunchOnInspection: Int?
    var relaunched: UninstallRunningProcess?
    var afterQuit: (() throws -> Void)?
    func inspect(_ application: InstalledApplication, validateBundle: Bool) async throws -> [UninstallRunningProcess] {
        inspectCount += 1
        if let threshold = relaunchOnInspection, inspectCount >= threshold, let relaunched { return [relaunched] }
        return processes
    }
    func quit(_ process: UninstallRunningProcess, application: InstalledApplication, force: Bool) async throws {
        try Task.checkCancellation()
        calls.append((process.pid, force))
        if force || !ignoresQuit { processes.removeAll { $0.pid == process.pid }; try afterQuit?() }
    }
}
private actor UninstallTrashFixture {
    var requests: [FileTrashRequest] = []
    func record(_ values: [FileTrashRequest]) -> [FileTrashResult] {
        requests += values
        return values.map { .init(source: $0.url, trashURL: $0.url.appendingPathExtension("owned-trash"), error: nil) }
    }
    func paths() -> [String] { requests.map { $0.url.path } }
}

@MainActor final class UninstallPreparationTests: XCTestCase {
    private func fixture() async throws -> UninstallPlan {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/uninstall-improvements/unit-" + UUID().uuidString).resolvingSymlinksInPath()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "org.example.UninstallFixture", "CFBundleName": "Example"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let prefs = root.appendingPathComponent("Library/Preferences/org.example.UninstallFixture.plist")
        try FileManager.default.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("before quit".utf8).write(to: prefs)
        let apps = try await ApplicationInventory().scan(roots: [root])
        return try UninstallPlanner.plan(XCTUnwrap(apps.first), home: root)
    }
    private func process(_ pid: Int32, main: Bool, birth: UInt64 = 1, canStop: Bool = true) -> UninstallRunningProcess {
        let identity = ProcessIdentity(pid: pid, startSeconds: birth, startMicroseconds: 0, effectiveUserID: 501, realUserID: 501,
                                       executablePath: "/Applications/Example.app/Contents/MacOS/Example")
        let entry = ProcessEntry(pid: pid, name: "Fixture", user: "fixture", state: "running", cpuPercent: 0, cpuSampleAvailable: false,
                                 residentBytes: 0, memorySampleAvailable: false, threadCount: nil, parentPID: 1,
                                 command: identity.executablePath, identity: identity, canTerminate: canStop)
        return .init(pid: pid, name: main ? "Example" : "Helper", entry: entry, isMainApplication: main)
    }
    private func model(_ plan: UninstallPlan, _ service: UninstallProcessFixture) -> UninstallPreparationModel {
        .init(application: plan.application, service: service, grace: .milliseconds(15), interval: .milliseconds(2))
    }
    func testInspectDoesNotQuitAndNormalExitPrecedesHelperTermination() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture()
        service.processes = [process(42, main: false), process(41, main: true)]
        let preparation = model(plan, service)
        await preparation.refresh(); XCTAssertTrue(service.calls.isEmpty)
        let ready = await preparation.prepare()
        XCTAssertTrue(ready); XCTAssertEqual(service.calls.map(\.0), [41, 42])
        XCTAssertTrue(service.calls.allSatisfy { !$0.1 })
    }
    func testRefusedQuitPreservesHelpersAndDoesNotAutomaticallyForce() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture()
        service.processes = [process(41, main: true), process(42, main: false)]; service.ignoresQuit = true
        let preparation = model(plan, service)
        let ready = await preparation.prepare()
        XCTAssertFalse(ready); XCTAssertEqual(service.calls.map(\.0), [41])
        XCTAssertTrue(service.calls.allSatisfy { !$0.1 }); XCTAssertTrue(preparation.canOfferForce)
        await preparation.refresh(); XCTAssertNotNil(preparation.failure, "Polling must not erase the reason removal was blocked")
    }
    func testExplicitForceRequiresExactCurrentProcessIdentities() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture()
        let main = process(41, main: true), helper = process(42, main: false)
        service.processes = [main, helper]; service.ignoresQuit = true
        let preparation = model(plan, service)
        _ = await preparation.prepare()
        let consent = preparation.forceIdentities
        service.calls = []
        let ready = await preparation.prepare(forceConsent: consent)
        XCTAssertTrue(ready); XCTAssertEqual(service.calls.count, 2); XCTAssertTrue(service.calls.allSatisfy(\.1))
    }
    func testPIDReuseAndNewHelpersRequireAnotherForceConfirmation() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture()
        let original = process(41, main: true), consent = Set([try XCTUnwrap(original.identity)])
        for running in [[process(41, main: true, birth: 2)], [original, process(42, main: false)]] {
            service.processes = running; service.calls = []
            let preparation = model(plan, service)
            let ready = await preparation.prepare(forceConsent: consent)
            XCTAssertFalse(ready); XCTAssertTrue(service.calls.isEmpty)
        }
    }
    func testProtectedProcessCannotOfferForceOrAllowRemoval() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture()
        service.processes = [process(41, main: true, canStop: false)]
        let preparation = model(plan, service)
        let ready = await preparation.prepare()
        XCTAssertFalse(ready); XCTAssertFalse(preparation.canOfferForce); XCTAssertTrue(service.calls.isEmpty)
    }
    func testCancellationStopsWaitingWithoutSignallingHelpers() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture()
        service.processes = [process(41, main: true), process(42, main: false)]; service.ignoresQuit = true
        let preparation = UninstallPreparationModel(application: plan.application, service: service, grace: .seconds(10), interval: .milliseconds(2))
        let task = Task { await preparation.prepare() }
        for _ in 0..<100 { if !service.calls.isEmpty { break }; await Task.yield() }
        preparation.cancel()
        let ready = await task.value
        XCTAssertFalse(ready); XCTAssertFalse(preparation.busy); XCTAssertFalse(service.calls.contains { $0.0 == 42 })
    }
    func testRemovalBackendCannotBypassRunningProcessGuard() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture(), trash = UninstallTrashFixture()
        service.processes = [process(42, main: false)]
        let workspace = ApplicationWorkspaceModel(uninstallProcesses: service, uninstallTrash: { await trash.record($0) })
        let removed = await workspace.uninstall(plan, selected: [plan.application.id])
        let paths = await trash.paths()
        XCTAssertFalse(removed); XCTAssertTrue(paths.isEmpty); XCTAssertTrue(service.calls.isEmpty); XCTAssertNotNil(workspace.failure)
    }
    func testPreferencesSavedOnQuitAreRevalidatedAndNewItemsStayUnselected() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture(), trash = UninstallTrashFixture()
        let preference = try XCTUnwrap(plan.candidates.first { $0.containsUserData })
        try Data("saved on quit with different bytes".utf8).write(to: preference.request.url, options: .atomic)
        let unselected = plan.home.appendingPathComponent("Library/Caches/" + plan.application.bundleID)
        try FileManager.default.createDirectory(at: unselected, withIntermediateDirectories: true)
        let workspace = ApplicationWorkspaceModel(uninstallProcesses: service, uninstallTrash: { requests in
            for request in requests {
                do { try request.validate() }
                catch { return [.init(source: request.url, trashURL: nil, error: error.localizedDescription)] }
            }
            return await trash.record(requests)
        })
        let removed = await workspace.uninstall(plan, selected: [preference.id, plan.application.id])
        let paths = await trash.paths()
        XCTAssertTrue(removed); XCTAssertEqual(paths, [preference.id, plan.application.id]); XCTAssertFalse(paths.contains(unselected.path))
    }
    func testRelaunchBetweenMovesPreservesApplicationAndRemainingFiles() async throws {
        let plan = try await fixture(), service = UninstallProcessFixture(), trash = UninstallTrashFixture()
        let preference = try XCTUnwrap(plan.candidates.first { $0.containsUserData })
        service.relaunchOnInspection = 3; service.relaunched = process(42, main: false)
        let workspace = ApplicationWorkspaceModel(uninstallProcesses: service, uninstallTrash: { await trash.record($0) })
        let removed = await workspace.uninstall(plan, selected: [preference.id, plan.application.id])
        let paths = await trash.paths()
        XCTAssertFalse(removed); XCTAssertEqual(paths, [preference.id]); XCTAssertNotNil(workspace.failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.application.url.path))
    }
}

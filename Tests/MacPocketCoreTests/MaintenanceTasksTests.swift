import XCTest
@testable import MacPocketCore

final class MaintenanceTasksTests: XCTestCase {
    func testAdministratorProcessPreservesCancellationAndShellErrorCodes() {
        XCTAssertNil(AdministratorShell.processFailure(.init(status: 0, output: "ok", errorOutput: "")))
        XCTAssertEqual(AdministratorShell.processFailure(.init(status: 1, output: "", errorOutput: "execution error: User canceled. (-128)\n")), .cancelled)
        XCTAssertEqual(AdministratorShell.processFailure(.init(status: 1, output: "", errorOutput: "execution error: route failed (17)\n")),
                       .failed(code: 17, message: "execution error: route failed (17)"))
        XCTAssertEqual(AdministratorShell.processFailure(.init(status: 2, output: "", errorOutput: "syntax error")),
                       .failed(code: 2, message: "syntax error"))
    }

    private struct Call: Equatable { let path: String; let arguments: [String] }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [Call] = []
        private(set) var scripts: [String] = []
        private(set) var events: [(MaintenanceTaskID, MaintenanceProgress)] = []
        func add(_ call: Call) { lock.withLock { calls.append(call) } }
        func add(script: String) { lock.withLock { scripts.append(script) } }
        func add(event: (MaintenanceTaskID, MaintenanceProgress)) { lock.withLock { events.append(event) } }
    }

    private func catalog(missing: Set<String> = [], only ids: Set<MaintenanceTaskID>? = nil) -> [MaintenanceTask] {
        MaintenanceCatalog.tasks(isExecutable: { !missing.contains($0) }).filter { ids?.contains($0.id) ?? true }
    }

    private func outcome(_ results: [MaintenanceResult], _ id: MaintenanceTaskID) -> MaintenanceOutcome? {
        results.first { $0.task.id == id }?.outcome
    }

    private let ok: MaintenanceRunner.Execute = { _, _, _ in BoundedProcess.Result(status: 0, output: "", errorOutput: "") }

    func testCatalogIsBuiltFromMacOSToolsAndRecommendsOnlySafeTasks() {
        let tasks = catalog()
        XCTAssertEqual(tasks.map(\.id), MaintenanceTaskID.allCases)
        XCTAssertEqual(Set(tasks.filter(\.recommended).map(\.id)), [.quickLook, .launchServices, .flushDNS, .verifyDisk])
        XCTAssertTrue(tasks.filter { !$0.recommended }.allSatisfy { $0.caution != nil }, "Opt-in tasks explain their side effect")
        XCTAssertEqual(Set(tasks.filter(\.requiresAdministrator).map(\.id)), [.flushDNS, .purgeMemory, .spotlight])
        XCTAssertTrue(tasks.allSatisfy { !$0.steps.isEmpty })
    }

    func testUserTasksRunInOrderAndAdministratorTasksShareOnePrompt() async {
        let recorder = Recorder()
        let results = await MaintenanceRunner.run(catalog(), execute: { path, arguments, _ in
            recorder.add(Call(path: path, arguments: arguments))
            return BoundedProcess.Result(status: 0, output: "", errorOutput: "")
        }, administrator: { script in
            recorder.add(script: script)
            return "MACPOCKET-STATUS:flushDNS:0\rMACPOCKET-STATUS:purgeMemory:0\rMACPOCKET-STATUS:spotlight:1\r"
        })
        XCTAssertEqual(recorder.calls.first, Call(path: "/usr/bin/qlmanage", arguments: ["-r", "cache"]))
        XCTAssertEqual(recorder.calls.filter { $0.path == "/usr/bin/killall" }.map(\.arguments), [["Dock"], ["Finder"], ["SystemUIServer"]])
        XCTAssertFalse(recorder.calls.contains { $0.path == "/usr/sbin/purge" }, "Administrator tasks never run unprivileged")
        XCTAssertEqual(recorder.scripts.count, 1, "One password prompt for every administrator task")
        XCTAssertTrue(recorder.scripts[0].contains("( /usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder ) >/dev/null 2>&1; echo MACPOCKET-STATUS:flushDNS:$?"))
        guard case .ran = outcome(results, .flushDNS) else { return XCTFail("DNS ran as root") }
        XCTAssertEqual(outcome(results, .spotlight), .failed("Çıkış kodu 1."))
        guard case let .ran(_, note) = outcome(results, .verifyDisk) else { return XCTFail() }
        XCTAssertNotNil(note)
        XCTAssertEqual(results.count, MaintenanceTaskID.allCases.count)
    }

    func testCancelledPromptSkipsOnlyAdministratorTasks() async {
        let results = await MaintenanceRunner.run(catalog(only: [.quickLook, .flushDNS]), execute: ok,
                                                  administrator: { _ in throw MaintenanceAdministratorError.cancelled })
        guard case .ran = outcome(results, .quickLook) else { return XCTFail() }
        guard case .skipped(let reason) = outcome(results, .flushDNS) else { return XCTFail() }
        XCTAssertFalse(reason.isEmpty)
    }

    func testMissingToolIsSkippedWithAReason() async {
        let results = await MaintenanceRunner.run(catalog(missing: ["/usr/sbin/purge"], only: [.purgeMemory]), execute: ok,
                                                  administrator: { _ in XCTFail("nothing to run"); return "" })
        guard case .skipped(let reason) = outcome(results, .purgeMemory) else { return XCTFail() }
        XCTAssertFalse(reason.isEmpty)
    }

    func testFailuresDoNotStopTheRunAndReportTheirCause() async {
        let results = await MaintenanceRunner.run(catalog(only: [.quickLook, .launchServices, .verifyDisk]), execute: { path, _, _ in
            if path.hasSuffix("qlmanage") { return BoundedProcess.Result(status: 3, output: "", errorOutput: "boom\nsecond line") }
            if path.hasSuffix("diskutil") { return BoundedProcess.Result(status: 1, output: "Checking…\nThe volume was found corrupt\n", errorOutput: "") }
            throw BoundedProcess.Failure.timedOut
        })
        XCTAssertEqual(outcome(results, .quickLook), .failed("boom"), "First line of stderr")
        XCTAssertEqual(outcome(results, .verifyDisk), .failed("The volume was found corrupt"), "Last line of stdout when stderr is empty")
        guard case .failed(let message) = outcome(results, .launchServices) else { return XCTFail("a throw is a failure") }
        XCTAssertFalse(message.isEmpty)
    }

    func testMultiStepTaskStopsAtTheFirstFailingStep() async {
        let recorder = Recorder()
        let results = await MaintenanceRunner.run(catalog(only: [.restartInterface]), execute: { path, arguments, _ in
            recorder.add(Call(path: path, arguments: arguments))
            return BoundedProcess.Result(status: arguments == ["Finder"] ? 1 : 0, output: "", errorOutput: "")
        })
        XCTAssertEqual(recorder.calls.map(\.arguments), [["Dock"], ["Finder"]])
        XCTAssertEqual(outcome(results, .restartInterface), .failed("Çıkış kodu 1."))
    }

    func testProgressIsReportedPerTask() async {
        let recorder = Recorder()
        _ = await MaintenanceRunner.run(catalog(only: [.quickLook]), execute: ok, progress: { id, state in recorder.add(event: (id, state)) })
        XCTAssertEqual(recorder.events.count, 3)
        XCTAssertEqual(recorder.events.prefix(2).map(\.1), [.waiting, .running])
        guard case .finished(.ran)? = recorder.events.last?.1 else { return XCTFail("ends finished") }
    }

    func testCancellationSkipsTheRemainingTasks() async {
        let recorder = Recorder()
        let tasks = catalog(only: [.quickLook, .launchServices, .flushDNS])
        let task = Task {
            await MaintenanceRunner.run(tasks, execute: { path, arguments, _ in
                recorder.add(Call(path: path, arguments: arguments))
                withUnsafeCurrentTask { $0?.cancel() }
                return BoundedProcess.Result(status: 0, output: "", errorOutput: "")
            }, administrator: { script in recorder.add(script: script); return "" })
        }
        let results = await task.value
        XCTAssertEqual(recorder.calls.count, 1, "The second task never started")
        XCTAssertTrue(recorder.scripts.isEmpty, "No password prompt after cancelling")
        guard case .skipped = outcome(results, .launchServices), case .skipped = outcome(results, .flushDNS) else { return XCTFail() }
    }

    func testAdministratorCommandRejectsUnsafeWordsAndParsesStatuses() throws {
        let unsafe = MaintenanceTask(id: .purgeMemory, group: .system, title: "", detail: "", symbol: "",
                                     steps: [.init("/usr/sbin/purge", ["; rm -rf /"])], requiresAdministrator: true,
                                     recommended: false, caution: nil, timeout: 1, support: .ready)
        XCTAssertThrowsError(try MaintenanceRunner.administratorCommand(for: [unsafe]))
        XCTAssertEqual(MaintenanceRunner.parseAdministratorStatuses("noise\nMACPOCKET-STATUS:flushDNS:0\nMACPOCKET-STATUS:bogus:0\nMACPOCKET-STATUS:spotlight:x"),
                       [.flushDNS: 0])
    }
}

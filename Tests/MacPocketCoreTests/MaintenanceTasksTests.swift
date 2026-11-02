import XCTest
@testable import MacPocketCore

final class MaintenanceTasksTests: XCTestCase {
    private struct Call: Equatable { let path: String; let arguments: [String] }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [Call] = []
        func add(_ call: Call) { lock.withLock { calls.append(call) } }
    }

    private func catalog(missing: Set<String> = []) -> [MaintenanceTask] {
        MaintenanceCatalog.tasks(isExecutable: { !missing.contains($0) })
    }

    private func outcome(_ results: [MaintenanceResult], _ id: MaintenanceTaskID) -> MaintenanceOutcome? {
        results.first { $0.task.id == id }?.outcome
    }

    func testReadyTasksRunWithTheirExactCommandAndOthersAreSkippedWithAReason() async {
        let recorder = Recorder()
        let results = await MaintenanceRunner.run(catalog(missing: ["/usr/sbin/periodic"]), execute: { path, arguments in
            recorder.add(Call(path: path, arguments: arguments))
            return BoundedProcess.Result(status: 0, output: "", errorOutput: "")
        })
        XCTAssertEqual(recorder.calls, [Call(path: "/usr/bin/qlmanage", arguments: ["-r", "cache"]),
                                        Call(path: "/usr/bin/atsutil", arguments: ["databases", "-removeUser"])],
                       "Only user-level tasks run; administrator tasks and missing tools do not")
        guard case .ran = outcome(results, .quickLook) else { return XCTFail("Quick Look should have run") }
        guard case .skipped(let adminReason) = outcome(results, .flushDNS) else { return XCTFail("DNS needs an administrator") }
        XCTAssertFalse(adminReason.isEmpty)
        guard case .skipped(let missingReason) = outcome(results, .periodicScripts) else { return XCTFail("periodic is missing") }
        XCTAssertNotEqual(missingReason, adminReason, "Each skip explains its own cause")
    }

    func testNonZeroExitAndThrownErrorsAreFailuresThatDoNotStopTheRun() async {
        let results = await MaintenanceRunner.run(catalog(), execute: { path, _ in
            if path.hasSuffix("qlmanage") { return BoundedProcess.Result(status: 3, output: "", errorOutput: "boom\nsecond line") }
            throw BoundedProcess.Failure.timedOut
        })
        XCTAssertEqual(outcome(results, .quickLook), .failed("boom"), "First line of stderr")
        guard case .failed(let message) = outcome(results, .userFontCache) else { return XCTFail("a throw is a failure") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(results.count, catalog().count, "Every requested task has a result")
    }

    func testExitCodeIsReportedWhenThereIsNoErrorText() async {
        let results = await MaintenanceRunner.run(catalog(), execute: { _, _ in BoundedProcess.Result(status: 9, output: "", errorOutput: "  \n") })
        guard case .failed(let message) = outcome(results, .quickLook) else { return XCTFail() }
        XCTAssertTrue(message.contains("9"))
    }

    func testRunsOnlyTheRequestedTasks() async {
        let recorder = Recorder()
        let only = catalog().filter { $0.id == .quickLook }
        let results = await MaintenanceRunner.run(only, execute: { path, arguments in
            recorder.add(Call(path: path, arguments: arguments))
            return BoundedProcess.Result(status: 0, output: "", errorOutput: "")
        })
        XCTAssertEqual(results.map(\.task.id), [.quickLook])
        XCTAssertEqual(recorder.calls.count, 1)
    }

    func testCancellationStopsBeforeTheNextTask() async {
        let recorder = Recorder()
        let tasks = catalog()
        let task = Task {
            await MaintenanceRunner.run(tasks, execute: { path, arguments in
                recorder.add(Call(path: path, arguments: arguments))
                withUnsafeCurrentTask { $0?.cancel() }
                return BoundedProcess.Result(status: 0, output: "", errorOutput: "")
            })
        }
        let results = await task.value
        XCTAssertEqual(recorder.calls.count, 1, "The second ready task never started")
        XCTAssertLessThan(results.count, tasks.count)
    }
}

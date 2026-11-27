import XCTest
@testable import MacPocketCore

final class BoundedProcessTests: XCTestCase {
    func testCollectsOutputAndStatus() async throws {
        let ok = try await BoundedProcess.run("/bin/zsh", ["-c", "printf 'Merhaba İstanbul'; printf hata >&2"], timeout: 5)
        XCTAssertEqual(ok.status, 0)
        XCTAssertEqual(ok.output, "Merhaba İstanbul")
        XCTAssertEqual(ok.errorOutput, "hata")
        let failed = try await BoundedProcess.run("/bin/zsh", ["-c", "exit 7"], timeout: 5)
        XCTAssertEqual(failed.status, 7)
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        // 1 MB is far beyond a pipe buffer; without draining while running this would hang until the timeout.
        let result = try await BoundedProcess.run("/bin/zsh", ["-c", "head -c 1048576 /dev/zero | tr '\\\\0' a"], timeout: 10)
        XCTAssertEqual(result.output.count, 1_048_576)
    }

    func testTimeoutKillsACommandThatIgnoresSIGTERM() async throws {
        let start = Date()
        do {
            _ = try await BoundedProcess.run("/bin/zsh", ["-c", "trap '' TERM; sleep 30"], timeout: 0.5)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? BoundedProcess.Failure, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5 + BoundedProcess.killGrace + 2, "escalated to SIGKILL")
    }

    /// Every run parks two reader tasks until its process exits. With more runs than CPU cores, blocking those
    /// reads (or the kill grace) on the cooperative pool starves the watchdogs that would end the processes.
    func testManyConcurrentTimeoutsDoNotStarveTheThreadPool() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount * 2 + 2
        let start = Date()
        let allTimedOut = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<count {
                group.addTask {
                    do {
                        _ = try await BoundedProcess.run("/bin/sleep", ["5"], timeout: 0.3)
                        return false
                    } catch {
                        return (error as? BoundedProcess.Failure) == .timedOut
                    }
                }
            }
            var all = true
            for await timedOut in group { all = all && timedOut }
            return all
        }
        XCTAssertTrue(allTimedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "\(count) concurrent timeouts must finish promptly")
    }

    func testCancellationIsReportedAsCancellationNotTimeout() async throws {
        let task = Task { try await BoundedProcess.run("/bin/zsh", ["-c", "sleep 30"], timeout: 60) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let start = Date()
        switch await task.result {
        case .success: XCTFail("expected cancellation")
        case let .failure(error): XCTAssertEqual(error as? BoundedProcess.Failure, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    /// A background child inherits the pipe, so EOF only comes when it exits; the caller must not wait for it.
    func testALeftoverChildHoldingThePipeDoesNotBlockTheResult() async throws {
        let start = Date()
        let result = try await BoundedProcess.run("/bin/zsh", ["-c", "sleep 8 & echo done"], timeout: 10)
        XCTAssertEqual(result.output, "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 4, "returned without waiting for the background child")
    }
}

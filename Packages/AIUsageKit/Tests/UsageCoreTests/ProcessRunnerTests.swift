import XCTest
import Foundation
@testable import UsageCore

final class ProcessRunnerTests: XCTestCase {
    func testACommandThatIgnoresSIGTERMIsKilledAfterTheGracePeriod() async {
        let start = Date()
        let result = await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                             arguments: ["-c", "trap '' TERM; sleep 10"], timeout: 0.3)
        XCTAssertNil(result.exitCode, "terminated by a signal, not a normal exit")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3 + ProcessRunner.killGrace + 3, "escalated to SIGKILL")
    }
}

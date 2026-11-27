import XCTest
@testable import MacPocketCore

final class SecureKeyboardInputStatusTests: XCTestCase {
    private func row(uid: Any = 501, pid: Any = 751, console: Any = true) -> [String: Any] {
        ["kCGSSessionUserIDKey": uid, "kCGSSessionSecureInputPID": pid, "kCGSSessionOnConsoleKey": console]
    }
    func testDisabledStatusIgnoresStaleOwner() {
        let value = SecureKeyboardInputStatus.resolve(enabled: false, consoleUsers: [row()], userID: 501)
        XCTAssertFalse(value.enabled)
        XCTAssertNil(value.processID)
    }
    func testOnlyCurrentOnConsoleUsersOwnerIsReported() {
        let value = SecureKeyboardInputStatus.resolve(enabled: true, consoleUsers: [row(uid: 502, pid: 12), row(pid: 13, console: false), row()], userID: 501)
        XCTAssertTrue(value.enabled)
        XCTAssertEqual(value.processID, 751)
    }
    func testEnabledStateSurvivesMissingOrMalformedRegistryData() {
        for rows: Any in [NSNull(), "invalid", [], [row(uid: true)], [row(console: "true")]] {
            let value = SecureKeyboardInputStatus.resolve(enabled: true, consoleUsers: rows, userID: 501)
            XCTAssertTrue(value.enabled)
            XCTAssertNil(value.processID)
        }
    }
    func testInvalidPIDsAreNotConvertedToRealProcesses() {
        for pid: Any in [true, false, "751", 0, -1, 0.5, Double.nan, Double.infinity, Int64(Int32.max) + 1, UInt64.max] {
            XCTAssertNil(SecureKeyboardInputStatus.resolve(enabled: true, consoleUsers: [row(pid: pid)], userID: 501).processID, "\(pid)")
        }
    }
    func testConflictingOwnersAreUnknownWhileRepeatedSameOwnerIsAllowed() {
        XCTAssertNil(SecureKeyboardInputStatus.resolve(enabled: true, consoleUsers: [row(), row(pid: 752)], userID: 501).processID)
        XCTAssertEqual(SecureKeyboardInputStatus.resolve(enabled: true, consoleUsers: [row(), row()], userID: 501).processID, 751)
    }
}

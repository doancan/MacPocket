import XCTest
@testable import MacPocketCore

final class ExecutableReplacementCheckTests: XCTestCase {
    private func bundle() throws -> (root: URL, executable: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReplacementCheck-" + UUID().uuidString)
        let executable = root.appendingPathComponent("App.app/Contents/MacOS/Helper")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old build".utf8).write(to: executable)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return (root, executable)
    }

    func testUntouchedExecutableIsNotReplaced() throws {
        let (_, executable) = try bundle()
        let check = try ExecutableReplacementCheck(url: executable)
        XCTAssertFalse(check.isReplaced)
    }

    func testDeleteAndCopyReinstallIsNoticed() throws {
        let (_, executable) = try bundle()
        let check = try ExecutableReplacementCheck(url: executable)
        try FileManager.default.removeItem(at: executable)
        try Data("new build".utf8).write(to: executable)
        XCTAssertTrue(check.isReplaced)
    }

    func testUpdateThatMovesTheOldBundleAwayIsNoticed() throws {
        // Sparkle renames the old bundle instead of deleting it, so the old file still exists elsewhere.
        let (root, executable) = try bundle()
        let check = try ExecutableReplacementCheck(url: executable)
        let app = root.appendingPathComponent("App.app")
        try FileManager.default.moveItem(at: app, to: root.appendingPathComponent("Old.app"))
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("new build".utf8).write(to: executable)
        XCTAssertTrue(check.isReplaced)
    }

    func testMissingExecutableCountsAsReplaced() throws {
        let (root, executable) = try bundle()
        let check = try ExecutableReplacementCheck(url: executable)
        try FileManager.default.removeItem(at: root.appendingPathComponent("App.app"))
        XCTAssertTrue(check.isReplaced)
    }

    func testCurrentProcessExecutableIsFound() throws {
        let check = try ExecutableReplacementCheck.currentProcess()
        XCTAssertTrue(check.url.path.hasPrefix("/"))
        XCTAssertFalse(check.isReplaced)
    }
}

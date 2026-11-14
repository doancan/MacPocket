import XCTest
@testable import MacPocketCore

final class FileRemovalTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-removal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try canonicalFileURL(root)
    }
    private func request(_ url: URL, root: URL) throws -> FileTrashRequest {
        FileTrashRequest(url: url, identity: try .read(url), root: root)
    }
    private func service(administrator: AdministratorRemover = AdministratorRemover { _ in
        XCTFail("administrator must not run"); return .init(status: 1, output: "", errorOutput: "")
    }) -> FileTrashService {
        FileTrashService(move: { _ in XCTFail("must not trash"); throw FileServiceError.unreadable }, administrator: administrator)
    }

    func testPermanentDeleteRemovesFolderTreeWithoutUsingTrash() async throws {
        let root = try fixture()
        let folder = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("nested/file"))
        let results = await service().remove([try request(folder, root: root)], mode: .deletePermanently)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].succeeded)
        XCTAssertNil(results[0].trashURL)
        XCTAssertEqual(results[0].mode, .deletePermanently)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testPermanentDeleteKeepsValidationAndLeavesChangedItem() async throws {
        let root = try fixture()
        let file = root.appendingPathComponent("a")
        try Data("one".utf8).write(to: file)
        let stale = try request(file, root: root)
        try Data("changed contents".utf8).write(to: file)
        let results = await service().remove([stale], mode: .deletePermanently)
        XCTAssertFalse(results[0].succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "A changed item must survive")
    }

    func testPermanentDeleteUnlinksSymlinkTargetUntouched() async throws {
        let root = try fixture(), outside = try fixture()
        let precious = outside.appendingPathComponent("precious")
        try Data("keep".utf8).write(to: precious)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let results = await service().remove([try request(link, root: root)], mode: .deletePermanently)
        XCTAssertFalse(results[0].succeeded, "Symbolic links are rejected, never followed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.path))
    }

    func testPermissionFailureWithoutAdministratorPromptStaysAFailure() async throws {
        let root = try fixture()
        let file = root.appendingPathComponent("a"); try Data("a".utf8).write(to: file)
        let denied = FileTrashService(move: { _ in throw FileServiceError.unreadable },
                                      delete: { _ in throw CocoaError(.fileWriteNoPermission) },
                                      administrator: AdministratorRemover { _ in
            XCTFail("no prompt was offered"); return .init(status: 1, output: "", errorOutput: "") })
        let results = await denied.remove([try request(file, root: root)], mode: .deletePermanently)
        XCTAssertFalse(results[0].succeeded)
    }

    func testPermissionFailureRetriesAllDeniedItemsInOneAdministratorCall() async throws {
        let root = try fixture()
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b"), c = root.appendingPathComponent("c")
        for url in [a, b, c] { try Data(url.lastPathComponent.utf8).write(to: url) }
        let calls = Calls()
        let admin = AdministratorRemover { arguments in
            await calls.record(arguments)
            for name in ["a", "b"] { try? FileManager.default.removeItem(at: root.appendingPathComponent(name)) }
            return .init(status: 0, output: "", errorOutput: "")
        }
        let service = FileTrashService(move: { _ in throw FileServiceError.unreadable }, delete: { url in
            if url.lastPathComponent == "c" { try FileManager.default.removeItem(at: url) }
            else { throw CocoaError(.fileWriteNoPermission) }
        }, administrator: admin)
        let results = await service.remove([try request(a, root: root), try request(b, root: root), try request(c, root: root)],
                                           mode: .deletePermanently, administratorPrompt: "prompt")
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy(\.succeeded))
        let recorded = await calls.all
        XCTAssertEqual(recorded.count, 1, "One password prompt for every denied item")
        XCTAssertTrue(recorded[0].joined().contains(a.path) && recorded[0].joined().contains(b.path))
        XCTAssertFalse(recorded[0].joined().contains(c.path))
    }

    func testDeclinedAdministratorPromptReportsFailureAndKeepsFile() async throws {
        let root = try fixture()
        let file = root.appendingPathComponent("a"); try Data("a".utf8).write(to: file)
        let admin = AdministratorRemover { _ in .init(status: 1, output: "", errorOutput: "execution error: User canceled. (-128)") }
        let service = FileTrashService(move: { _ in throw FileServiceError.unreadable },
                                       delete: { _ in throw CocoaError(.fileWriteNoPermission) }, administrator: admin)
        let results = await service.remove([try request(file, root: root)], mode: .deletePermanently, administratorPrompt: "p")
        XCTAssertFalse(results[0].succeeded)
        XCTAssertEqual(results[0].error, FileRemovalError.administratorDeclined.localizedDescription)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAdministratorScriptQuotesHostilePaths() {
        let hostile = "/tmp/it's \"x\"; rm -rf ~ #\\"
        let script = AdministratorRemover.script(paths: [hostile], launchdLabels: ["com.a.b", "bad label; x"], prompt: "Say \"hi\"")
        XCTAssertTrue(script.hasPrefix("do shell script \""))
        XCTAssertTrue(script.hasSuffix("with administrator privileges"))
        XCTAssertTrue(script.contains("launchctl bootout 'system/com.a.b'"))
        XCTAssertFalse(script.contains("bad label"), "Invalid launchd labels are dropped")
        XCTAssertEqual(AdministratorRemover.shellQuoted("a'b"), "'a'\\''b'")
        XCTAssertEqual(AdministratorRemover.appleScriptQuoted("a\"b\\"), "\"a\\\"b\\\\\"")
        XCTAssertTrue(script.contains("with prompt \"Say \\\"hi\\\"\""))
    }

    func testTrashModeNeverFallsBackToAnAdministratorDelete() async throws {
        let root = try fixture()
        let file = root.appendingPathComponent("a"); try Data("a".utf8).write(to: file)
        let service = FileTrashService(move: { _ in throw CocoaError(.fileWriteNoPermission) }, delete: { _ in XCTFail("no delete"); },
                                       administrator: AdministratorRemover { _ in
            XCTFail("a recoverable removal must never become a root delete"); return .init(status: 0, output: "", errorOutput: "") })
        let results = await service.remove([try request(file, root: root)], mode: .moveToTrash, administratorPrompt: "p")
        XCTAssertFalse(results[0].succeeded)
        XCTAssertTrue(results[0].permissionDenied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPartialAdministratorRunCountsOnlyTheItemsThatAreReallyGone() async throws {
        let root = try fixture()
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b"), c = root.appendingPathComponent("c")
        for url in [a, b, c] { try Data("x".utf8).write(to: url) }
        // rm removes a and c, fails on b and exits 1.
        let admin = AdministratorRemover { _ in
            for name in ["a", "c"] { try? FileManager.default.removeItem(at: root.appendingPathComponent(name)) }
            return .init(status: 1, output: "", errorOutput: "rm: b: Operation not permitted")
        }
        let service = FileTrashService(move: { _ in throw FileServiceError.unreadable },
                                       delete: { _ in throw CocoaError(.fileWriteNoPermission) }, administrator: admin)
        let results = await service.remove([try request(a, root: root), try request(b, root: root), try request(c, root: root)],
                                           mode: .deletePermanently, administratorPrompt: "p")
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.source.lastPathComponent, $0) })
        XCTAssertTrue(byName["a"]?.succeeded == true)
        XCTAssertTrue(byName["c"]?.succeeded == true)
        XCTAssertTrue(byName["b"]?.succeeded == false)
        XCTAssertTrue(byName["b"]?.error?.contains("Operation not permitted") == true)
    }

    func testOnlyRealPermissionErrorsCountAsPermissionFailures() {
        XCTAssertTrue(FileRemovalClassifier.isPermissionFailure(CocoaError(.fileWriteNoPermission)))
        XCTAssertTrue(FileRemovalClassifier.isPermissionFailure(POSIXError(.EACCES)))
        XCTAssertTrue(FileRemovalClassifier.isPermissionFailure(POSIXError(.EPERM)))
        XCTAssertFalse(FileRemovalClassifier.isPermissionFailure(POSIXError(.ENOENT)))
        // Code 1 outside the POSIX domain (FileServiceError.unreadable) is not EPERM.
        XCTAssertFalse(FileRemovalClassifier.isPermissionFailure(FileServiceError.unreadable))
        XCTAssertFalse(FileRemovalClassifier.isPermissionFailure(NSError(domain: "Other", code: Int(EPERM))))
    }

    func testPathContainingTheCancelCodeIsNotMistakenForADeclinedPrompt() async throws {
        let root = try fixture()
        let file = root.appendingPathComponent("foo-128"); try Data("a".utf8).write(to: file)
        let admin = AdministratorRemover { _ in .init(status: 1, output: "", errorOutput: "rm: \(file.path): Permission denied") }
        let service = FileTrashService(move: { _ in throw FileServiceError.unreadable },
                                       delete: { _ in throw CocoaError(.fileWriteNoPermission) }, administrator: admin)
        let results = await service.remove([try request(file, root: root)], mode: .deletePermanently, administratorPrompt: "p")
        XCTAssertFalse(results[0].succeeded)
        XCTAssertNotEqual(results[0].error, FileRemovalError.administratorDeclined.localizedDescription)
    }

    func testAdministratorRefusesNonCanonicalAndRelativePaths() async {
        let admin = AdministratorRemover { _ in XCTFail("must not run"); return .init(status: 0, output: "", errorOutput: "") }
        for path in ["/", "relative/path", "/tmp/../etc/passwd"] {
            do { _ = try await admin.remove([URL(fileURLWithPath: path)], prompt: "p"); XCTFail(path) }
            catch { XCTAssertEqual(error as? FileServiceError, .protectedItem) }
        }
    }

    func testRemovalModePreferenceDefaultsToPermanent() {
        let defaults = UserDefaults(suiteName: "removal-" + UUID().uuidString)!
        XCTAssertEqual(RemovalModePreference.load(defaults), .deletePermanently)
        RemovalModePreference.save(.moveToTrash, defaults)
        XCTAssertEqual(RemovalModePreference.load(defaults), .moveToTrash)
    }
}

private actor Calls {
    private(set) var all: [[String]] = []
    func record(_ arguments: [String]) { all.append(arguments) }
}

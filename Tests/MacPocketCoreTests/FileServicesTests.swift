import XCTest
@testable import MacPocketCore

final class FileServicesTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-tests-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try canonicalFileURL(root)
    }
    private func file(_ url: URL, _ contents: String) throws { try Data(contents.utf8).write(to: url) }

    func testTraversalDoesNotFollowLinksOrDoubleCountHardLinks() async throws {
        let root = try fixture()
        let data = root.appendingPathComponent("data")
        try file(data, "unique")
        try FileManager.default.linkItem(at: data, to: root.appendingPathComponent("hard-link"))
        let outside = try fixture()
        try file(outside.appendingPathComponent("outside"), "should not count")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside-link"), withDestinationURL: outside)
        let report = try await FileScanner().scan(root)
        XCTAssertEqual(report.fileCount, 1)
        XCTAssertEqual(report.bytes, 6)
        XCTAssertEqual(report.skippedLinks, 1)
    }

    func testLimitsAreExplicitAndLargestFilesAreRetained() async throws {
        let root = try fixture()
        try file(root.appendingPathComponent("small"), "a")
        try file(root.appendingPathComponent("large"), "abcdef")
        var options = FileScanOptions()
        options.maximumRetainedFiles = 1
        let report = try await FileScanner().scan(root, options: options)
        XCTAssertEqual(report.bytes, 7)
        XCTAssertEqual(report.files.first?.url.lastPathComponent, "large")
        XCTAssertFalse(report.retainedAllFiles)
        options.maximumEntries = 1
        let limited = try await FileScanner().scan(root, options: options)
        XCTAssertTrue(limited.limitReached)
    }

    func testFolderRollupMatchesUniqueBytes() async throws {
        let root = try fixture()
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file(folder.appendingPathComponent("one"), "12345")
        let report = try await FileScanner().scan(root)
        XCTAssertEqual(report.folders.first?.bytes, 5, "Root \(report.root.path) files \(report.files.map { $0.url.path }) issues \(report.issues)")
        XCTAssertEqual(report.folders.first?.fileCount, 1)
    }

    func testContentComparisonDistinguishesSameSizeFiles() async throws {
        let root = try fixture()
        try file(root.appendingPathComponent("a"), "same")
        try file(root.appendingPathComponent("b"), "same")
        try file(root.appendingPathComponent("c"), "else")
        let report = try await FileScanner().scan(root)
        let groups = try await DuplicateFinder().groups(in: report.files)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map { $0.url.lastPathComponent }), ["a", "b"])
        XCTAssertEqual(groups[0].duplicateBytes, 4)
    }

    func testTrashRejectsChangedFilesAndOutOfScopeItems() throws {
        let root = try fixture()
        let url = root.appendingPathComponent("item")
        try file(url, "old")
        let identity = try FileIdentity.read(url)
        try file(url, "new value")
        XCTAssertThrowsError(try FileTrashRequest(url: url, identity: identity, root: root).validate())
        let other = try fixture()
        XCTAssertThrowsError(try FileTrashRequest(url: url, identity: .read(url), root: other).validate())
    }

    func testReplacedParentSymlinkCannotEscapeApprovedScope() throws {
        let root = try fixture()
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let item = folder.appendingPathComponent("item")
        try file(item, "owned")
        let request = FileTrashRequest(url: item, identity: try .read(item), root: root)
        try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("original"))
        let outside = try fixture()
        try file(outside.appendingPathComponent("item"), "outside")
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        XCTAssertThrowsError(try request.validate())
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("item"), encoding: .utf8), "outside")
    }

    func testProtectedRootsCannotBeTrashed() throws {
        let root = URL(fileURLWithPath: "/")
        XCTAssertThrowsError(try FileTrashRequest(url: root, identity: .read(root), root: root).validate())
    }

    func testPartialTrashResultRetainsPerItemFailure() async throws {
        let root = try fixture()
        let first = root.appendingPathComponent("a"), second = root.appendingPathComponent("b")
        try file(first, "a"); try file(second, "b")
        let service = FileTrashService { url in
            if url.lastPathComponent == "b" { throw FileServiceError.unreadable }
            let target = url.appendingPathExtension("moved")
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        let result = await service.trash([.init(url: first, identity: try .read(first), root: root),
                                          .init(url: second, identity: try .read(second), root: root)])
        XCTAssertNotNil(result[0].trashURL)
        XCTAssertNotNil(result[1].error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}

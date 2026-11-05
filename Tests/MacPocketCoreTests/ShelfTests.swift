import Foundation
import XCTest
@testable import MacPocketCore

final class ShelfTests: XCTestCase {
    func testCapacityNeverEvictsAndPendingTransfersReserveSlots() {
        var shelf = ShelfCollection()
        let contents = (0..<105).map { ShelfContent.text("item \($0)") }
        let reserved = shelf.insert(contents, reserving: 3)
        XCTAssertEqual(reserved.added.count, 97)
        XCTAssertEqual(reserved.rejected, 8)
        let originalIDs = shelf.items.map(\.id)
        let rest = shelf.insert([.text("a"), .text("b"), .text("c"), .text("d")])
        XCTAssertEqual(rest.added.count, 3)
        XCTAssertEqual(rest.rejected, 1)
        XCTAssertEqual(Array(shelf.items.prefix(97)).map(\.id), originalIDs)
    }

    func testDeduplicationAndPinsSurviveArchive() throws {
        var shelf = ShelfCollection()
        let result = shelf.insert([.text("Merhaba 👋"), .text("Merhaba 👋"), .fromText("https://example.com/a")])
        XCTAssertEqual(result.duplicates, 1)
        shelf.togglePins([result.added[0].id])
        let data = try JSONEncoder().encode(ShelfArchive(items: shelf.items))
        var restored = try ShelfArchive.decode(data)
        XCTAssertEqual(restored, shelf)
        XCTAssertEqual(restored.clearUnpinned().count, 1)
        XCTAssertEqual(restored.items.map(\.content), [.text("Merhaba 👋")])
        XCTAssertTrue(restored.items[0].pinned)
        restored.remove([restored.items[0].id])
        XCTAssertTrue(restored.items.isEmpty)
    }

    func testTextAndLinksAreBoundedAndNeverBecomeExecutableURLs() {
        XCTAssertEqual(ShelfContent.fromText(" https://example.com/a \n"), .link(URL(string: "https://example.com/a")!))
        for text in ["file:///tmp/private.txt", "javascript:alert(1)", "https://example.com\nmore", "mailto:a@example.com"] {
            XCTAssertEqual(ShelfContent.fromText(text), .text(text))
        }
        var shelf = ShelfCollection()
        let result = shelf.insert([.text(" \n"), .text(String(repeating: "ü", count: ShelfCollection.maximumTextBytes)),
                                   .link(URL(string: "file:///tmp/a")!), .text("line one\nline two")])
        XCTAssertEqual(result.rejected, 3)
        XCTAssertEqual(result.added.first?.content.title, "line one")
        XCTAssertEqual(result.added.first?.content.plainText, "line one\nline two")
    }

    func testBookmarkFollowsRenameAndDoesNotFollowReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.txt")
        let moved = folder.appendingPathComponent("renamed.txt")
        try Data("original".utf8).write(to: original)
        let reference = try ShelfFileReference(url: original)
        try FileManager.default.moveItem(at: original, to: moved)
        try Data("replacement".utf8).write(to: original)
        XCTAssertEqual(reference.resolvedURL()?.standardizedFileURL.resolvingSymlinksInPath(), moved.standardizedFileURL.resolvingSymlinksInPath())
        // Edits keep file identity and must remain usable.
        let handle = try FileHandle(forWritingTo: moved)
        try handle.seekToEnd(); try handle.write(contentsOf: Data(" edited".utf8)); try handle.close()
        XCTAssertNotNil(reference.resolvedURL())
        let data = try JSONEncoder().encode(ShelfArchive(items: [.init(content: .file(reference))]))
        let restored = try ShelfArchive.decode(data)
        guard case .file(let saved) = restored.items[0].content else { return XCTFail("Expected a file reference") }
        XCTAssertEqual(saved.resolvedURL(), reference.resolvedURL())
        try FileManager.default.removeItem(at: moved)
        XCTAssertNil(reference.resolvedURL())
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "replacement")
    }

    func testRemovingFileReferencesNeverChangesSourceFilesAndHardLinksDeduplicate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("source")
        let link = folder.appendingPathComponent("hardlink")
        try Data("untouched".utf8).write(to: file)
        try FileManager.default.linkItem(at: file, to: link)
        var shelf = ShelfCollection()
        let result = shelf.insert([.file(try ShelfFileReference(url: file)), .file(try ShelfFileReference(url: link))])
        XCTAssertEqual(result.duplicates, 1)
        shelf.clearUnpinned()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "untouched")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "untouched")
    }

    func testInvalidArchiveFailsAndDuplicateIDsAreSanitized() throws {
        XCTAssertThrowsError(try ShelfArchive.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try ShelfArchive.decode(Data("{\"version\":2,\"items\":[]}".utf8)))
        let id = UUID()
        let collection = ShelfCollection(items: [.init(id: id, content: .text("one")), .init(id: id, content: .text("two")),
                                                  .init(content: .text("one")), .init(content: .text(""))])
        XCTAssertEqual(collection.items.count, 1)
    }
}

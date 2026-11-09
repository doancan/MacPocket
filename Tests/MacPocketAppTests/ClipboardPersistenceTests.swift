import AppKit
import XCTest
import MacPocketCore
@testable import MacPocketApp

@MainActor final class ClipboardPersistenceTests: XCTestCase {
    private func fixture(history: ClipboardHistory = ClipboardHistory()) throws -> (ClipboardService, ClipboardArchive) {
        let suite = "MacPocket.ClipboardPersistence." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let archive = ClipboardArchive(directory: directory)
        try archive.save(history)
        let defaults = UserDefaults(suiteName: suite)!
        var settings = ClipboardSettings(); settings.enabled = true
        settings.save(to: defaults)
        let pasteboard = NSPasteboard(name: .init(suite))
        addTeardownBlock {
            await MainActor.run { NSPasteboard(name: .init(suite)).releaseGlobally() }
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return (ClipboardService(defaults: defaults, archive: archive, pasteboard: pasteboard), archive)
    }

    private func item(_ content: ClipboardContent = .text("fixture"), pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(content: content, copiedAt: Date(timeIntervalSince1970: 1_800_000_000), pinned: pinned)
    }

    func testUnloadedServiceDoesNotOverwriteExistingArchiveOnFlush() throws {
        let history = ClipboardHistory(items: [item()])
        let (service, archive) = try fixture(history: history)
        let identity = try FileIdentity.read(archive.historyFile)
        service.flushSave()
        XCTAssertEqual(try FileIdentity.read(archive.historyFile), identity)
        XCTAssertEqual(try archive.load(), history)
    }

    func testRepeatedUnchangedFlushesAvoidThePreviousFourAtomicWrites() throws {
        let history = ClipboardHistory(items: (0..<200).map { item(.text("Fixture \($0)")) })
        let (service, archive) = try fixture(history: history)
        var identity = try FileIdentity.read(archive.historyFile)
        var legacyWrites = 0
        for _ in 0..<4 {
            try archive.save(history) // Previous flush implementation, reference only.
            let next = try FileIdentity.read(archive.historyFile)
            if next != identity { legacyWrites += 1 }
            identity = next
        }
        service.loadStoredHistory()
        var currentWrites = 0
        for _ in 0..<4 {
            service.flushSave()
            let next = try FileIdentity.read(archive.historyFile)
            if next != identity { currentWrites += 1 }
            identity = next
        }
        XCTAssertEqual(legacyWrites, 4); XCTAssertEqual(currentWrites, 0)
        XCTAssertEqual(try archive.load(), history)
        print("Clipboard unchanged flush comparison: legacy=\(legacyWrites), current=\(currentWrites) atomic file replacements")
    }

    func testChangedHistorySavesOnceAndNoOpMutationsDoNotRewriteIt() throws {
        let entry = item(.link(URL(string: "https://example.com/?utm_source=fixture&keep=1")!))
        let (service, archive) = try fixture(history: ClipboardHistory(items: [entry]))
        service.loadStoredHistory()
        let initial = try FileIdentity.read(archive.historyFile)
        service.setPinned(true, entry)
        service.cleanLink(entry)
        service.flushSave()
        let saved = try FileIdentity.read(archive.historyFile)
        XCTAssertNotEqual(saved, initial)
        XCTAssertEqual(try archive.load(), service.history)
        XCTAssertTrue(service.history.items[0].pinned)
        XCTAssertEqual(service.history.items[0].content, .link(URL(string: "https://example.com/?keep=1")!))
        service.setPinned(true, entry)
        service.remove(item())
        service.clearHistory(includingPinned: false)
        service.flushSave()
        XCTAssertEqual(try FileIdentity.read(archive.historyFile), saved)
        service.remove(entry)
        service.flushSave()
        XCTAssertEqual(try archive.load().items.count, 0)
    }

    func testFailedSaveRemainsPendingForRetry() throws {
        let entry = item()
        let (service, archive) = try fixture(history: ClipboardHistory(items: [entry]))
        service.loadStoredHistory()
        service.setPinned(true, entry)
        let backup = archive.directory.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: archive.directory, to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        try Data([0]).write(to: archive.directory) // A file blocks directory creation; no permission changes.
        service.flushSave()
        XCTAssertNotNil(service.lastError)
        try FileManager.default.removeItem(at: archive.directory)
        try FileManager.default.moveItem(at: backup, to: archive.directory)
        service.flushSave()
        XCTAssertTrue(try archive.load().items[0].pinned)
        let saved = try FileIdentity.read(archive.historyFile)
        service.flushSave()
        XCTAssertEqual(try FileIdentity.read(archive.historyFile), saved)
    }

    func testMemoryOnlyChangesPersistWhenDiskStorageIsEnabledAgain() throws {
        let image = ClipboardImageReference(fileName: "0123456789abcdef.png", pixelWidth: 1, pixelHeight: 1, byteCount: 3)
        let entry = item(.image(image))
        let (service, archive) = try fixture(history: ClipboardHistory(items: [entry]))
        _ = try archive.storeImage(Data([1, 2, 3]), named: image.fileName)
        service.loadStoredHistory()
        service.settings.saveToDisk = false
        service.setPinned(true, entry)
        service.flushSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.directory.path))
        service.settings.saveToDisk = true
        XCTAssertTrue(try archive.load().items[0].pinned)
        XCTAssertEqual(try Data(contentsOf: archive.imageURL(image.fileName)), Data([1, 2, 3]))
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.historyFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testEraseDoesNotRecreateAnEmptyArchiveOnFlush() throws {
        let (service, archive) = try fixture(history: ClipboardHistory(items: [item()]))
        service.loadStoredHistory()
        service.eraseEverything()
        service.flushSave()
        XCTAssertTrue(service.history.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.directory.path))
    }
}

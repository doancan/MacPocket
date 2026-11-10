import AppKit
import XCTest
import MacPocketCore
@testable import MacPocketApp

@MainActor final class ClipboardSearchModelTests: XCTestCase {
    private func fixture() throws -> (ClipboardService, ClipboardItem) {
        let suite = "MacPocket.SearchTests." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let archive = ClipboardArchive(directory: directory)
        let item = ClipboardItem(content: .text("İstanbul"), copiedAt: Date(timeIntervalSince1970: 1_800_000_000), sourceName: "Notlar")
        try archive.save(ClipboardHistory(items: [item]))
        let defaults = UserDefaults(suiteName: suite)!
        var settings = ClipboardSettings(); settings.enabled = true; settings.retentionDays = nil; settings.save(to: defaults)
        let board = NSPasteboard(name: .init(suite))
        addTeardownBlock {
            await MainActor.run { NSPasteboard(name: .init(suite)).releaseGlobally() }
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let service = ClipboardService(defaults: defaults, archive: archive, pasteboard: board)
        service.loadStoredHistory()
        return (service, item)
    }

    private func settle(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }

    func testRapidTypingDebouncesAndPendingSearchCannotPastePreviousResults() async throws {
        let (service, item) = try fixture()
        var queries: [String] = []
        let model = ClipboardSearchModel(service: service, delay: .milliseconds(30)) { query, _ in
            queries.append(query); return [item]
        }
        XCTAssertEqual(model.selectedItem, item)
        model.query = "i"; model.query = "is"; model.query = "istanbul"
        XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.selectedItem); XCTAssertTrue(model.isSearching)
        model.move(by: 1)
        try await settle { !model.isSearching }
        XCTAssertEqual(queries, ["istanbul"]); XCTAssertEqual(model.selectedItem, item)
        model.query = "missing"; model.query = " "
        XCTAssertFalse(model.isSearching); XCTAssertEqual(model.items, [item])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(queries, ["istanbul"])
        model.stop()
    }

    func testLateCanceledResponseCannotReplaceNewerQuery() async throws {
        let (service, item) = try fixture()
        var pending: [String: CheckedContinuation<[ClipboardItem], Never>] = [:]
        let model = ClipboardSearchModel(service: service, delay: .zero) { query, _ in
            await withCheckedContinuation { pending[query] = $0 }
        }
        model.query = "old"
        try await settle { pending["old"] != nil }
        model.query = "new"
        try await settle { pending["new"] != nil }
        pending.removeValue(forKey: "new")?.resume(returning: [])
        try await settle { !model.isSearching }
        pending.removeValue(forKey: "old")?.resume(returning: [item])
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.selectedItem)
        model.stop()
    }

    func testRealIndexTracksHistoryMutationsFiltersAndRemount() async throws {
        let (service, item) = try fixture()
        let model = ClipboardSearchModel(service: service, delay: .zero)
        model.query = "ıstanbul"
        try await settle { !model.isSearching }
        XCTAssertEqual(model.items, [item])
        service.setPinned(true, item)
        try await settle { !model.isSearching }
        XCTAssertTrue(try XCTUnwrap(model.items.first).pinned)
        model.kind = .link
        try await settle { !model.isSearching }
        XCTAssertTrue(model.items.isEmpty)
        model.kind = nil
        try await settle { !model.isSearching }
        service.remove(item)
        XCTAssertNil(model.selectedItem)
        try await settle { !model.isSearching }
        XCTAssertTrue(model.items.isEmpty)
        model.stop(); model.query = "notlar"
        XCTAssertFalse(model.isSearching); XCTAssertTrue(model.items.isEmpty)
        model.start()
        try await settle { !model.isSearching }
        XCTAssertTrue(model.items.isEmpty)
        model.stop()
    }
}

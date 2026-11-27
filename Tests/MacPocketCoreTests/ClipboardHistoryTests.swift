import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class ClipboardHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings = ClipboardSettings()

    private func image(_ hash: String, bytes: Int = 1_000) -> ClipboardContent {
        .image(ClipboardImageReference(fileName: hash + ".png", pixelWidth: 10, pixelHeight: 10, byteCount: bytes))
    }

    func testRecordsNewestFirstAndRefreshesDuplicatesInsteadOfAddingThem() {
        var history = ClipboardHistory()
        _ = history.record(.text("bir"), at: start, settings: settings)
        _ = history.record(.text("iki"), at: start + 1, settings: settings)
        let again = history.record(.text("bir", sourceName: "Notes"), at: start + 2, settings: settings)
        guard case .refreshed = again.result else { return XCTFail("expected refresh, got \(again.result)") }
        XCTAssertEqual(history.items.map(\.title), ["bir", "iki"])
        XCTAssertEqual(history.items[0].useCount, 2)
        XCTAssertEqual(history.items[0].copiedAt, start + 2)
        XCTAssertEqual(history.items[0].sourceName, "Notes")
    }

    func testIgnoresConcealedExcludedEmptyAndOversizedContent() {
        var history = ClipboardHistory()
        settings.keepImages = false
        XCTAssertEqual(history.record(.text("p4ss", isConcealed: true), at: start, settings: settings).result, .ignored(.concealed))
        XCTAssertEqual(history.record(.text("x", sourceBundleID: "com.1password.1password"), at: start, settings: settings).result,
                       .ignored(.excludedApplication))
        XCTAssertEqual(history.record(.text("  \n\t"), at: start, settings: settings).result, .ignored(.empty))
        XCTAssertEqual(history.record(.text(String(repeating: "a", count: ClipboardSettings.maximumTextLength + 1)), at: start,
                                      settings: settings).result, .ignored(.tooLarge))
        XCTAssertEqual(history.record(ClipboardCapture(content: image("ab12cd34ef56ab78")), at: start, settings: settings).result,
                       .ignored(.imagesOff))
        settings.keepImages = true
        settings.maximumImageBytes = 500
        XCTAssertEqual(history.record(ClipboardCapture(content: image("ab12cd34ef56ab78")), at: start, settings: settings).result,
                       .ignored(.tooLarge))
        XCTAssertTrue(history.items.isEmpty)
    }

    func testCapacityDropsOldestUnpinnedAndReportsOrphanedImages() {
        var history = ClipboardHistory()
        settings.capacity = 2
        _ = history.record(ClipboardCapture(content: image("0000000000000001")), at: start, settings: settings)
        _ = history.record(.text("sabit"), at: start + 1, settings: settings)
        history.setPinned(true, for: history.items[0].id)
        _ = history.record(.text("a"), at: start + 2, settings: settings)
        let outcome = history.record(.text("b"), at: start + 3, settings: settings)
        // Unpinned: b, a, image → the image falls off; the pinned item doesn't count against capacity.
        XCTAssertEqual(history.items.map(\.title), ["b", "a", "sabit"])
        XCTAssertEqual(outcome.orphanedImages, ["0000000000000001.png"])
    }

    func testPruneRemovesOnlyOldUnpinnedItems() {
        var history = ClipboardHistory()
        _ = history.record(.text("eski"), at: start, settings: settings)
        _ = history.record(.text("eski sabit"), at: start, settings: settings)
        history.setPinned(true, for: history.items[0].id)
        _ = history.record(.text("yeni"), at: start + 6 * 86_400, settings: settings)
        _ = history.prune(olderThan: 7, now: start + 8 * 86_400)
        XCTAssertEqual(Set(history.items.map(\.title)), ["eski sabit", "yeni"])
        XCTAssertEqual(history.prune(olderThan: nil, now: start + 1_000 * 86_400), [])
        XCTAssertEqual(history.items.count, 2, "nil retention keeps everything")
    }

    func testClearKeepsPinnedUnlessAskedAndImagesAreOnlyOrphanedOnce() {
        var history = ClipboardHistory()
        _ = history.record(ClipboardCapture(content: image("00000000000000aa")), at: start, settings: settings)
        _ = history.record(.text("pin"), at: start + 1, settings: settings)
        history.setPinned(true, for: history.items[0].id)
        XCTAssertEqual(history.clear(includingPinned: false), ["00000000000000aa.png"])
        XCTAssertEqual(history.items.map(\.title), ["pin"])
        XCTAssertEqual(history.clear(includingPinned: true), [])
        XCTAssertTrue(history.items.isEmpty)
    }

    func testMarkUsedMovesToTop() {
        var history = ClipboardHistory()
        _ = history.record(.text("a"), at: start, settings: settings)
        _ = history.record(.text("b"), at: start + 1, settings: settings)
        let first = history.items[1].id
        history.markUsed(first, at: start + 5)
        XCTAssertEqual(history.items.map(\.title), ["a", "b"])
        XCTAssertEqual(history.items[0].useCount, 2)
    }

    func testSearchPutsPinnedFirstAndIgnoresCaseDiacriticsAndTurkishI() {
        var history = ClipboardHistory()
        _ = history.record(.text("İstanbul ofisi"), at: start, settings: settings)
        _ = history.record(.text("ISPARTA notu"), at: start + 1, settings: settings)
        _ = history.record(.text("Çalışma planı", sourceName: "Notlar"), at: start + 2, settings: settings)
        history.setPinned(true, for: history.items.last!.id)
        XCTAssertEqual(history.search("istanbul").map(\.title), ["İstanbul ofisi"])
        XCTAssertEqual(history.search("ısparta").map(\.title), ["ISPARTA notu"])
        XCTAssertEqual(history.search("calisma").map(\.title), ["Çalışma planı"])
        XCTAssertEqual(history.search("notlar").map(\.title), ["Çalışma planı"], "matches the source app")
        XCTAssertEqual(history.search("").first?.title, "İstanbul ofisi", "pinned first")
        XCTAssertEqual(history.search("", kind: .link), [])
    }

    func testTitleIsFirstNonEmptyLine() {
        let item = ClipboardItem(content: .text("\n\n  ilk satır  \nikinci"), copiedAt: start)
        XCTAssertEqual(item.title, "ilk satır")
        XCTAssertEqual(ClipboardItem(content: .files([URL(fileURLWithPath: "/tmp/a.txt")]), copiedAt: start).title, "a.txt")
    }
}

final class ClipboardCaptureTests: XCTestCase {
    func testSingleWebAddressBecomesALink() {
        XCTAssertEqual(ClipboardCapture.text("  https://example.com/a?b=1 \n").content, .link(URL(string: "https://example.com/a?b=1")!))
        XCTAssertEqual(ClipboardCapture.text("see https://example.com").content, .text("see https://example.com"))
        XCTAssertEqual(ClipboardCapture.text("ftp://example.com").content, .text("ftp://example.com"))
        XCTAssertEqual(ClipboardCapture.text("https://").content, .text("https://"))
    }
}

final class LinkCleanerTests: XCTestCase {
    private let cleaner = LinkCleaner()

    private func clean(_ text: String, _ cleaner: LinkCleaner? = nil) -> String? {
        (cleaner ?? self.cleaner).clean(URL(string: text)!)?.absoluteString
    }

    func testRemovesCommonTrackingAndKeepsEverythingElseInOrder() {
        XCTAssertEqual(clean("https://shop.example/item?id=42&utm_source=news&utm_medium=mail&color=red&fbclid=abc#reviews"),
                       "https://shop.example/item?id=42&color=red#reviews")
        XCTAssertEqual(clean("https://example.com/?gclid=1"), "https://example.com/")
        XCTAssertEqual(clean("https://example.com/?UTM_Campaign=x&q=1"), "https://example.com/?q=1", "names are case-insensitive")
    }

    func testSiteSpecificParametersApplyOnlyToThatSite() {
        XCTAssertEqual(clean("https://www.youtube.com/watch?v=abc&si=XYZ&t=30"), "https://www.youtube.com/watch?v=abc&t=30")
        XCTAssertEqual(clean("https://youtu.be/abc?si=XYZ"), "https://youtu.be/abc")
        XCTAssertNil(clean("https://example.com/search?si=keep&t=1"), "si and t mean something else elsewhere")
        XCTAssertEqual(clean("https://www.amazon.com.tr/dp/B0?ref_=nav&th=1"), "https://www.amazon.com.tr/dp/B0")
    }

    func testReturnsNilWhenNothingChangesOrNotAWebLink() {
        XCTAssertNil(clean("https://example.com/a?b=1"))
        XCTAssertNil(clean("https://example.com/a"))
        XCTAssertNil(clean("mailto:a@example.com?utm_source=x"))
    }

    func testPreservesPercentEncoding() {
        XCTAssertEqual(clean("https://example.com/ara?q=%C3%A7ay%20bah%C3%A7esi&utm_source=x"),
                       "https://example.com/ara?q=%C3%A7ay%20bah%C3%A7esi")
    }

    func testUserParametersExtendTheRules() {
        let custom = LinkCleaner(extraParameters: [" Partner ", ""])
        XCTAssertEqual(clean("https://example.com/?partner=7&id=1", custom), "https://example.com/?id=1")
    }
}

final class ClipboardSettingsTests: XCTestCase {
    func testDefaultsArePrivacyFirst() {
        let settings = ClipboardSettings()
        XCTAssertFalse(settings.enabled, "history is opt-in")
        XCTAssertEqual(settings.shortcut.displayName, "⇧⌘V")
        XCTAssertTrue(settings.excludedBundleIDs.contains("com.apple.Passwords"))
    }

    func testDecodingKeepsDefaultsForMissingFieldsAndHonoursNullRetention() throws {
        let partial = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"enabled":true,"capacity":3}"#.utf8))
        XCTAssertTrue(partial.enabled)
        XCTAssertEqual(partial.capacity, 10, "clamped to the minimum")
        XCTAssertEqual(partial.retentionDays, 30)
        let forever = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"retentionDays":null}"#.utf8))
        XCTAssertNil(forever.retentionDays)
    }

    func testInvalidStoredShortcutFallsBack() throws {
        let json = #"{"shortcut":{"keyCode":9,"modifiers":8}}"# // ⇧V alone
        XCTAssertEqual(try JSONDecoder().decode(ClipboardSettings.self, from: Data(json.utf8)).shortcut.displayName, "⇧⌘V")
    }

    func testRoundTripThroughUserDefaults() {
        let defaults = temporaryDefaults()
        var settings = ClipboardSettings()
        settings.enabled = true
        settings.retentionDays = nil
        settings.clearClipboardAfterMinutes = 5
        settings.extraTrackingParameters = ["partner"]
        settings.save(to: defaults)
        XCTAssertEqual(ClipboardSettings.load(from: defaults), settings)
    }

    func testKeyComboCarbonFlagsAndValidity() {
        XCTAssertEqual(KeyCombo(keyCode: 9, modifiers: [.command, .shift]).carbonFlags, 0x0300)
        XCTAssertFalse(KeyCombo(keyCode: 9, modifiers: [.shift]).isValidGlobalShortcut)
        XCTAssertTrue(KeyCombo(keyCode: 9, modifiers: [.control, .option]).isValidGlobalShortcut)
    }
}

final class ClipboardArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardArchiveTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripWithOwnerOnlyPermissions() throws {
        let archive = ClipboardArchive(directory: directory)
        var history = ClipboardHistory()
        _ = history.record(.text("gizli not"), at: Date(timeIntervalSince1970: 1_800_000_000), settings: ClipboardSettings())
        try archive.save(history)
        XCTAssertEqual(try archive.load(), history)
        let file = try FileManager.default.attributesOfItem(atPath: archive.historyFile.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testMissingFileIsAnEmptyHistory() throws {
        XCTAssertEqual(try ClipboardArchive(directory: directory).load(), ClipboardHistory())
    }

    func testImageNamesCannotEscapeTheFolder() {
        let archive = ClipboardArchive(directory: directory)
        XCTAssertEqual(archive.imageURL("../../etc/passwd").lastPathComponent, "invalid.png")
        XCTAssertEqual(archive.imageURL("0123456789abcdef.png").deletingLastPathComponent().lastPathComponent, "Images")
    }

    func testStoredImagesAreDeduplicatedAndDeletable() throws {
        let archive = ClipboardArchive(directory: directory)
        let url = try archive.storeImage(Data([1, 2, 3]), named: "0123456789abcdef.png")
        _ = try archive.storeImage(Data([9]), named: "0123456789abcdef.png")
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]), "same name means same image; not rewritten")
        archive.deleteImages(["0123456789abcdef.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

import XCTest
@testable import MacPocketCore

final class ClipboardSearchIndexTests: XCTestCase {
    private func item(_ text: String, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(content: .text(text), copiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                      sourceBundleID: "unsearchable.bundle", sourceName: "Notlar", pinned: pinned)
    }

    func testIndexedResultsMatchLegacyUnicodeFieldsFiltersAndOrder() async throws {
        let texts = ["İstanbul IĞDIR ısparta", "Çalışma résumé CAFÉ", "Straße ﬃ Æ Œ", "Σίσυφος σ ς",
                     "e\u{301} ß ẞ ﬁ K Å", "👩🏽‍💻 漢字 العربية", "soft\u{ad}hyphen zero\u{200b}width",
                     "\n  ilk satır\nikinci", "foo bar", "ςσΣ", "İIıi", "a\u{301}", "\u{301}", "क् क", "\u{fe0f}", "\u{200d}",
                     "ascii\0after-null\r\nnext", "Æ Œ Ø Ł Þ", "가 가", "abcdefghijklmnopqrstuvwxyz"]
        var items = texts.enumerated().map { item($0.element, pinned: $0.offset.isMultiple(of: 3)) }
        items += [ClipboardItem(content: .link(URL(string: "https://example.com/İstanbul")!), copiedAt: .now),
                  ClipboardItem(content: .files([URL(fileURLWithPath: "/tmp/Çalışma.txt")]), copiedAt: .now),
                  ClipboardItem(content: .image(.init(fileName: "x.png", pixelWidth: 10, pixelHeight: 20, byteCount: 2)),
                                copiedAt: .now, sourceName: "Görseller")]
        let history = ClipboardHistory(items: items), index = ClipboardSearchIndex()
        let queries = ["", "  ", "istanbul", "ıstanbul", "igdir", "calisma", "RESUME", "cafe", "ss", "ffi", "ae", "œ",
                       "σ", "ς", "ΣΙΣ", "e", "f", "k", "a", "👩", "漢", "الع", "softhyphen", "zerowidth",
                       "ikinci\nNotlar", "Notlar\nilk", "foo\nbar", "Notlar", "unsearchable.bundle", "gorsel", "10×20", "missing", "\u{301}", "\u{fe0f}", "\u{200d}", "\u{ad}", "\u{200b}", "\n", "\t", "🏽", "क", "्"]
        for kind in [nil] + ClipboardContent.Kind.allCases.map(Optional.some) {
            for query in queries + ["after-null", "\0", "\r\n", "ae", "oe", "o", "l", "th", "ᄀ", "가", "가", "ß", "ẞ", "ẚ", "ﬀ", "ﬁ", "ﬂ", "ﬃ", "ﬄ"] {
                let result = try await index.search(query, kind: kind, in: history, revision: 1)
                XCTAssertEqual(result, history.search(query, kind: kind), "query=\(query), kind=\(String(describing: kind))")
            }
        }
    }

    func testMetadataChangesReuseDocumentsAndRemovalPrunesThem() async throws {
        let first = item("ilk"), second = item("ikinci")
        let index = ClipboardSearchIndex()
        try await index.prepare(ClipboardHistory(items: [first, second]), revision: 1)
        var pinned = first
        pinned.pinned = true
        pinned.useCount += 1
        pinned.copiedAt += 10
        let changed = ClipboardHistory(items: [second, pinned])
        let result = try await index.search("notlar", in: changed, revision: 2)
        XCTAssertEqual(result, [pinned, second])
        let reusedCount = await index.preparedDocumentCount
        XCTAssertEqual(reusedCount, 2)
        var renamed = pinned
        renamed.sourceName = "Yeni uygulama"
        let updated = ClipboardHistory(items: [renamed])
        let renamedResult = try await index.search("yeni", in: updated, revision: 3)
        XCTAssertEqual(renamedResult, [renamed])
        let rebuiltCount = await index.preparedDocumentCount, retained = await index.documentCount
        XCTAssertEqual(rebuiltCount, 3)
        XCTAssertEqual(retained, 1)
        var edited = renamed
        edited.content = .text("yeni içerik")
        let editedResult = try await index.search("icerik", in: ClipboardHistory(items: [edited]), revision: 4)
        XCTAssertEqual(editedResult, [edited])
        let editedCount = await index.preparedDocumentCount
        XCTAssertEqual(editedCount, 4)
    }

    func testOlderSnapshotsCannotRestoreDeletedDocuments() async throws {
        let index = ClipboardSearchIndex(), old = ClipboardHistory(items: [item("eski")])
        try await index.prepare(ClipboardHistory(), revision: 2)
        do { _ = try await index.search("eski", in: old, revision: 1); XCTFail("old revision accepted") }
        catch is CancellationError {} catch { XCTFail("unexpected \(error)") }
        let retained = await index.documentCount
        XCTAssertEqual(retained, 0)
    }

    func testNewRevisionInterruptsInFlightPreparationWithoutRestoringDeletedEntries() async throws {
        let history = ClipboardHistory(items: (0..<100).map { item("İstanbul \($0) " + String(repeating: "x", count: 20_000)) })
        let index = ClipboardSearchIndex()
        let old = Task { try await index.search("istanbul", in: history, revision: 1) }
        while await index.documentCount == 0 { await Task.yield() }
        try await index.prepare(ClipboardHistory(), revision: 2)
        do { _ = try await old.value; XCTFail("superseded search accepted") }
        catch is CancellationError {} catch { XCTFail("unexpected \(error)") }
        let retained = await index.documentCount
        XCTAssertEqual(retained, 0)
    }

    func testConcurrentConsumersSharePreparationAndCancellationDoesNotPoisonIndex() async throws {
        let history = ClipboardHistory(items: (0..<80).map { item("İstanbul \($0) " + String(repeating: "x", count: 2000)) })
        let index = ClipboardSearchIndex()
        let canceled = Task { try await index.search("missing", in: history, revision: 1) }
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("cancellation ignored") }
        catch is CancellationError {} catch { XCTFail("unexpected \(error)") }
        async let first = index.search("istanbul", in: history, revision: 1)
        async let second = index.search("ıstanbul", in: history, revision: 1)
        let results = try await (first, second)
        XCTAssertEqual(results.0, history.search("istanbul"))
        XCTAssertEqual(results.1, results.0)
        let count = await index.preparedDocumentCount
        XCTAssertEqual(count, history.items.count)
    }
}

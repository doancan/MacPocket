import XCTest
@testable import MacPocketCore

final class CommandSearchTests: XCTestCase {
    func testTurkishKeyboardVariantsAndMultipleTerms() {
        let entries: [CommandSearchEntry] = [
            .init(id: "layout", title: "Pencere Yerleşimi", subtitle: "Ekranlar arasında taşı", kind: .tool),
            .init(id: "screenshot", title: "Ekran Görüntüsü", keywords: "screenshot capture", kind: .tool)
        ]
        XCTAssertEqual(CommandSearch.results(entries, query: "PENCERE YERLESIMI").map(\.id), ["layout"])
        XCTAssertEqual(CommandSearch.results(entries, query: "goruntusu ekran").map(\.id), ["screenshot"])
        XCTAssertEqual(CommandSearch.results(entries, query: "screenshot").map(\.id), ["screenshot"])
        XCTAssertEqual(CommandSearch.normalize("  İŞLEM\n  ışık  "), "islem isik")
        XCTAssertTrue(CommandSearch.results(entries, query: "ekran bilinmeyen").isEmpty)
    }

    func testRelevanceWinsOverHabitsAndTiesKeepCatalogOrder() {
        let entries: [CommandSearchEntry] = [
            .init(id: "a", title: "JSON Dönüştürücü", kind: .tool),
            .init(id: "b", title: "JSON", kind: .tool),
            .init(id: "c", title: "JSON Notları", kind: .clipboard)
        ]
        XCTAssertEqual(CommandSearch.results(entries, query: "json", recent: ["a"], pinned: ["c"]).first?.id, "b")
        XCTAssertEqual(CommandSearch.results(entries, query: "").map(\.id), ["a", "b", "c"])
        XCTAssertEqual(CommandSearch.results(entries, query: "", recent: ["c", "c", "a"], pinned: ["b"]).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(CommandSearch.results(entries, query: "json", kind: .clipboard).map(\.id), ["c"])
    }

    func testBoundsAndDuplicateIdentities() {
        let entry = CommandSearchEntry(id: "a", title: "Test", kind: .tool)
        XCTAssertEqual(CommandSearch.results([entry, entry], query: "", limit: 500).count, 1)
        XCTAssertTrue(CommandSearch.results([entry], query: "", limit: -1).isEmpty)
        XCTAssertEqual(CommandSearch.results((0..<250).map { .init(id: "\($0)", title: "Test", kind: .tool) }, query: "", limit: 1000).count, 200)
    }

    func testOnlyCompleteBoundedParameterCommandsExecute() {
        XCTAssertEqual(ParameterCommand.parse("Parlaklık 40%"), .brightness(40))
        XCTAssertEqual(ParameterCommand.parse("brightness 100"), .brightness(100))
        XCTAssertEqual(ParameterCommand.parse("uyanık tut 30 dk"), .keepAwake(minutes: 30))
        XCTAssertEqual(ParameterCommand.parse("keep awake 1440 minutes"), .keepAwake(minutes: 1440))
        for text in ["brightness", "brightness -1", "brightness 101", "brightness 1.5", "awake 0", "awake 1441",
                     "awake 999999999999999999999999999999", "brightness 20; rm -rf", "awake 5 now"] {
            XCTAssertNil(ParameterCommand.parse(text), text)
        }
    }
}

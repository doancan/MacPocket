import XCTest
@testable import MacPocketCore

final class SnippetTests: XCTestCase {
    private let date = Snippet(abbreviation: ";tarih", expansion: "{date}")
    private let dateTime = Snippet(abbreviation: ";tarihsaat", expansion: "{datetime}")

    private func feed(_ text: String, _ snippets: [Snippet], matcher: inout SnippetMatcher) -> Snippet? {
        var last: Snippet?
        for character in text { if let match = matcher.type(character, snippets: snippets) { last = match } }
        return last
    }

    func testCompletesAnAbbreviationAtTheEndOfTyping() {
        var matcher = SnippetMatcher()
        XCTAssertEqual(feed("bugün ;tarih", [date], matcher: &matcher), date)
        XCTAssertNil(feed("abc", [date], matcher: &matcher), "the buffer resets after a match")
    }

    func testLongestAbbreviationWins() {
        var matcher = SnippetMatcher()
        // ";tarih" completes first, then the longer one: whichever ends the input and is longest is reported.
        var results: [Snippet] = []
        for character in ";tarihsaat" { if let match = matcher.type(character, snippets: [dateTime]) { results.append(match) } }
        XCTAssertEqual(results, [dateTime])
    }

    func testBackspaceAndResetChangeTheBuffer() {
        var matcher = SnippetMatcher()
        for character in ";tarx" { _ = matcher.type(character, snippets: [date]) }
        matcher.deleteBackward()
        XCTAssertEqual(feed("ih", [date], matcher: &matcher), date, "a typo fixed with backspace still matches")
        for character in ";tar" { _ = matcher.type(character, snippets: [date]) }
        matcher.reset()
        XCTAssertNil(feed("ih", [date], matcher: &matcher))
    }

    func testDisabledInvalidAndDuplicateSnippets() {
        var matcher = SnippetMatcher()
        let off = Snippet(abbreviation: ";x", expansion: "y", enabled: false)
        let tooShort = Snippet(abbreviation: "a", expansion: "b")
        XCTAssertNil(feed(";x a", [off, tooShort], matcher: &matcher))
        var settings = SnippetSettings()
        settings.snippets = [date, Snippet(abbreviation: ";tarih", expansion: "x")]
        XCTAssertEqual(settings.duplicates, [";tarih"])
    }

    func testVariablesExpandInTheAppLanguage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 15 Jan 2027, 08:00 UTC
        let istanbul = TimeZone(identifier: "Europe/Istanbul")!
        let text = SnippetExpander.expand("{date} {time} {weekday} [{clipboard}] {unknown}", now: now, clipboard: "pano",
                                          locale: Locale(identifier: "tr"), timeZone: istanbul)
        XCTAssertEqual(text, "15.01.2027 11:00 Cuma [pano] {unknown}")
        XCTAssertEqual(SnippetExpander.expand("{clipboard}", now: now, clipboard: nil, locale: Locale(identifier: "tr")), "")
    }
}

import XCTest
@testable import MacPocketCore

final class ClipboardTextPreviewTests: XCTestCase {
    private func legacy(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return String((line.map(String.init) ?? text).trimmingCharacters(in: .whitespaces).prefix(200))
    }

    func testBlankLinesWhitespaceAndUnicodeNewlinesMatchPreviousTitles() {
        for text in ["", "   ", "\t\n \r\n", "\n   \n", " başlık \nsonraki", "\r\n\t\r\n Başlık\t\r\nsonraki",
                     "\u{85}\u{2028}Başlık\u{2029}sonraki", "\u{a0}\u{2003}Başlık\u{2003}", "\u{feff}Başlık\nsonraki"] {
            XCTAssertEqual(ClipboardTextPreview.title(text), legacy(text), text.debugDescription)
        }
    }

    func testGeneratedLineCombinationsMatchPreviousImplementation() {
        let lines = ["", " ", "\t", "\u{a0}", "Başlık", "   iki kelime  ", "e\u{301}", "👩🏽‍💻 aile 👨‍👩‍👧‍👦", "\u{feff}"]
        for first in lines {
            for second in lines {
                for separator in ["\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}"] {
                    let text = first + separator + second + separator + " son satır "
                    XCTAssertEqual(ClipboardTextPreview.title(text), legacy(text), text.debugDescription)
                }
            }
        }
    }

    func testTwoHundredCharacterLimitKeepsWholeGraphemesAndTrimmingSemantics() {
        let grapheme = "👩🏽‍💻e\u{301}"
        for text in [String(repeating: grapheme, count: 300), " a" + String(repeating: " ", count: 500),
                     " a" + String(repeating: " ", count: 500) + "b\nignored", "\n\t " + String(repeating: grapheme, count: 300) + "  \nignored"] {
            let title = ClipboardTextPreview.title(text)
            XCTAssertEqual(title, legacy(text))
            XCTAssertLessThanOrEqual(title.count, 200)
        }
    }

    func testClipboardItemUsesSamePreviewForLargeLogEntries() {
        let text = "\n\t\n  İlk hata satırı  \r\n" + String(repeating: "Sonraki günlük satırı\n", count: 30_000)
        let item = ClipboardItem(content: .text(text), copiedAt: Date())
        XCTAssertEqual(item.title, "İlk hata satırı")
        XCTAssertEqual(item.title, legacy(text))
    }
}

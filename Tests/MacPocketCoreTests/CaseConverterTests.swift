import XCTest
@testable import MacPocketCore

final class CaseConverterTests: XCTestCase {
    private let english = CaseOptions(language: .english)
    private let turkish = CaseOptions(language: .turkish)

    func testAllIdentifierStylesSplitInitialismsAndExistingDelimiters() throws {
        let text = "HTTPServer2Response user_profile-name"
        let cases: [(CaseFormat, String)] = [
            (.camel, "httpServer2ResponseUserProfileName"), (.pascal, "HttpServer2ResponseUserProfileName"),
            (.snake, "http_server2_response_user_profile_name"), (.constant, "HTTP_SERVER2_RESPONSE_USER_PROFILE_NAME"),
            (.kebab, "http-server2-response-user-profile-name"), (.train, "Http-Server2-Response-User-Profile-Name"),
            (.dot, "http.server2.response.user.profile.name"), (.path, "http/server2/response/user/profile/name"),
        ]
        for (format, expected) in cases { XCTAssertEqual(try CaseConverter.convert(text, to: format, options: english), expected) }
        XCTAssertEqual(try CaseConverter.convert("XMLHttpRequest JSONParserID", to: .camel, options: english), "xmlHttpRequestJsonParserId")
    }

    func testTurkishAndEnglishCasingAreExplicit() throws {
        XCTAssertEqual(try CaseConverter.convert("I İ ı i", to: .lower, options: turkish), "ı i ı i")
        XCTAssertEqual(try CaseConverter.convert("ı i", to: .upper, options: turkish), "I İ")
        XCTAssertEqual(try CaseConverter.convert("i", to: .upper, options: english), "I")
        XCTAssertEqual(try CaseConverter.convert("istanbul izmir ışık", to: .title, options: turkish), "İstanbul İzmir Işık")
        XCTAssertEqual(try CaseConverter.convert("İzmir Şehir Rehberi", to: .camel, options: turkish), "izmirŞehirRehberi")
    }

    func testSentenceCaseKeepsPunctuationAndDecimalPoints() throws {
        let input = "“MERHABA!” NASILSIN? 3.14 DEĞERİ. 🙂 YENİ SATIR\nSON CÜMLE."
        XCTAssertEqual(try CaseConverter.convert(input, to: .sentence, options: turkish),
                       "“Merhaba!” Nasılsın? 3.14 değeri. 🙂 Yeni satır\nSon cümle.")
    }

    func testToggleAndAlternatingDoNotSplitEmojiOrLoseExpandedLetters() throws {
        XCTAssertEqual(try CaseConverter.convert("Abİı🙂", to: .toggle, options: turkish), "aBiI🙂")
        XCTAssertEqual(try CaseConverter.convert("mac pocket 2 🙂", to: .alternating, options: english), "mAc PoCkEt 2 🙂")
        XCTAssertEqual(try CaseConverter.convert("straße", to: .upper, options: english), "STRASSE")
        XCTAssertEqual(try CaseConverter.convert("👨‍👩‍👧‍👦 e\u{301}", to: .upper, options: english), "👨‍👩‍👧‍👦 É")
    }

    func testLineBatchPreservesEmptyLinesAndMixedLineEndings() throws {
        let input = "FirstName\r\n\r\nHTTPServer\rlast_name\n"
        XCTAssertEqual(try CaseConverter.convert(input, to: .snake, options: english), "first_name\r\n\r\nhttp_server\rlast_name\n")
        var options = english
        options.keepBlankLines = false
        XCTAssertEqual(try CaseConverter.convert(input, to: .snake, options: options), "first_name\r\nhttp_server\rlast_name\n")
        options.lineByLine = false
        XCTAssertEqual(try CaseConverter.convert(input, to: .camel, options: options), "firstNameHttpServerLastName")
    }

    func testAcronymAndNumberOptionsDoWhatTheySay() throws {
        var options = english
        options.preserveAcronyms = true
        XCTAssertEqual(try CaseConverter.convert("HTTPServerID", to: .pascal, options: options), "HTTPServerID")
        XCTAssertEqual(try CaseConverter.convert("HTTPServerID", to: .camel, options: options), "httpServerID")
        options.preserveAcronyms = false
        options.separateNumbers = true
        XCTAssertEqual(try CaseConverter.convert("version2Value", to: .snake, options: options), "version_2_value")
        options.splitAcronyms = false
        XCTAssertEqual(try CaseConverter.convert("HTTPServer", to: .snake, options: options), "httpserver")
    }

    func testLatinSimplificationHappensAfterLocaleCaseMapping() throws {
        var options = turkish
        options.simplifyLatin = true
        XCTAssertEqual(try CaseConverter.convert("İZMİR IŞIK ÇĞÖŞÜ", to: .lower, options: options), "izmir isik cgosu")
        XCTAssertEqual(try CaseConverter.convert("İzmir Şehir Rehberi", to: .camel, options: options), "izmirSehirRehberi")
        XCTAssertEqual(try CaseConverter.convert("œuvre Straße", to: .kebab, options: options), "oeuvre-strasse")
    }

    func testNumericPrefixOnlyAppliesToVariableStylesAndIsOptional() throws {
        XCTAssertEqual(try CaseConverter.convert("123 value", to: .camel, options: english), "_123Value")
        XCTAssertEqual(try CaseConverter.convert("123 value", to: .kebab, options: english), "123-value")
        var options = english
        options.prefixNumericIdentifiers = false
        XCTAssertEqual(try CaseConverter.convert("123 value", to: .snake, options: options), "123_value")
        XCTAssertEqual(try CaseConverter.convert("🙂 --", to: .camel, options: options), "")
    }

    func testPreviewsAreCompleteAndStatisticsCountGraphemes() throws {
        let previews = try CaseConverter.previews("helloWorld\n🙂 café", options: english)
        XCTAssertEqual(previews.map(\.format), CaseFormat.allCases)
        XCTAssertEqual(Set(previews.map(\.format)).count, 14)
        XCTAssertEqual(previews.first { $0.format == .snake }?.text, "hello_world\ncafé")
        let stats = CaseConverter.statistics("👨‍👩‍👧‍👦 e\u{301}\r\nx")
        XCTAssertEqual(stats.characters, 5)
        XCTAssertEqual(stats.lines, 2)
        XCTAssertEqual(stats.words, 2)
    }

    func testWhitespaceUnicodeAndPunctuationStayInNaturalTextFormats() throws {
        let text = "  Merhaba,\t世界!  🙂\n"
        XCTAssertEqual(try CaseConverter.convert(text, to: .upper, options: turkish), "  MERHABA,\t世界!  🙂\n")
        XCTAssertEqual(try CaseConverter.convert("  alpha...beta / gamma  ", to: .snake, options: english), "alpha_beta_gamma")
    }

    func testLimitsAndEmptyInputAreRecoverableErrors() {
        XCTAssertThrowsError(try CaseConverter.previews(""))
        XCTAssertThrowsError(try CaseConverter.previews(String(repeating: "ş", count: 32_769))) {
            XCTAssertEqual($0 as? CaseConverterError, .size)
        }
    }

    func testEveryFormatHandlesBoundedLargeInput() throws {
        let input = String(repeating: "HTTPServer2Response\n", count: 1_000)
        let previews = try CaseConverter.previews(input, options: english)
        XCTAssertEqual(previews.count, 14)
        XCTAssertTrue(previews.allSatisfy { !$0.text.isEmpty })
    }
}

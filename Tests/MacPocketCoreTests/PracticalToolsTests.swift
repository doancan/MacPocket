import XCTest
import ImageIO
@testable import MacPocketCore

final class PracticalToolsTests: XCTestCase {
    func testJSONPreservesNumbersOrderEscapesAndEmptyContainers() throws {
        let input = #" { "z": 9007199254740993, "a": [ {}, [], "a \"quoted\" ş" ], "d": 1.234567890123456789 } "#
        let output = try PracticalTools.json(input)
        XCTAssertTrue(output.contains("9007199254740993"))
        XCTAssertTrue(output.contains("1.234567890123456789"))
        XCTAssertLessThan(try XCTUnwrap(output.range(of: #""z""#)).lowerBound, try XCTUnwrap(output.range(of: #""a""#)).lowerBound)
        XCTAssertTrue(output.contains("{}"))
        XCTAssertTrue(output.contains("[]"))
        XCTAssertEqual(try PracticalTools.json(output, compact: true), #"{"z":9007199254740993,"a":[{},[],"a \"quoted\" ş"],"d":1.234567890123456789}"#)
        XCTAssertEqual(try PracticalTools.json("null"), "null")
        for invalid in [#"{"missing":}"#, "[1,]", #"{"a":1,}"#] { XCTAssertThrowsError(try PracticalTools.json(invalid)) }
    }

    func testBase64RoundTripsUnicodeAndBothAlphabets() throws {
        for value in ["İzmir 🌤️", "hello?", "", "a\nb"] {
            for urlSafe in [true, false] {
                let encoded = try PracticalTools.base64(value, decode: false, urlSafe: urlSafe)
                XCTAssertEqual(try PracticalTools.base64(encoded, decode: true, urlSafe: urlSafe), value)
            }
        }
        XCTAssertEqual(try PracticalTools.base64(" TQ==\n", decode: true), "M")
        for malformed in ["TQ=", "TQ===", "TW==", "@@@@", "a"] {
            XCTAssertThrowsError(try PracticalTools.base64(malformed, decode: true))
        }
        XCTAssertThrowsError(try PracticalTools.base64("/w==", decode: true)) { XCTAssertEqual($0 as? PracticalToolError, .utf8) }
    }

    func testURLParameterEscapingDoesNotTreatPlusAsSpace() throws {
        let value = "İzmir & a+b/?#="
        let encoded = try PracticalTools.url(value, decode: false)
        XCTAssertFalse(encoded.contains("&"))
        XCTAssertEqual(try PracticalTools.url(encoded, decode: true), value)
        XCTAssertEqual(try PracticalTools.url("a+b", decode: true), "a+b")
        for invalid in ["%", "%GG", "%A", "%FF"] { XCTAssertThrowsError(try PracticalTools.url(invalid, decode: true)) }
    }

    private func jwt(_ payload: String, header: String = #"{"alg":"none","typ":"JWT"}"#) throws -> String {
        try PracticalTools.base64(header, decode: false, urlSafe: true) + "." +
            PracticalTools.base64(payload, decode: false, urlSafe: true) + "."
    }

    func testJWTTimeClaimsUseNumericDatesAndExpirationBoundary() throws {
        let token = try jwt(#"{"sub":"demo","exp":1000,"nbf":900,"iat":800}"#)
        let result = try PracticalTools.jwt(token, at: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(result.expiration?.timeIntervalSince1970, 1000)
        XCTAssertEqual(result.notBefore?.timeIntervalSince1970, 900)
        XCTAssertTrue(result.payload.contains("demo"))
        XCTAssertNotEqual(result.timeDescription, try PracticalTools.jwt(token, at: Date(timeIntervalSince1970: 950)).timeDescription)
        XCTAssertThrowsError(try PracticalTools.jwt(jwt(#"{"exp":true}"#)))
        XCTAssertThrowsError(try PracticalTools.jwt(jwt(#"{"exp":"1000"}"#)))
        XCTAssertThrowsError(try PracticalTools.jwt("a.b.c.d.e")) { XCTAssertEqual($0 as? PracticalToolError, .encryptedJWT) }
        XCTAssertThrowsError(try PracticalTools.jwt("a.b.c"))
    }

    func testDigestsMatchPublishedVectorsIncludingEmptyInput() throws {
        XCTAssertEqual(try PracticalTools.hash("abc", algorithm: .sha256), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try PracticalTools.hash("", algorithm: .sha256), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(try PracticalTools.hash("abc", algorithm: .sha512), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    }

    func testUUIDBatchIsUniqueAndVersionFour() throws {
        let values = try PracticalTools.uuids(count: 100).split(separator: "\n").map(String.init)
        XCTAssertEqual(Set(values).count, 100)
        for value in values {
            XCTAssertNotNil(UUID(uuidString: value))
            XCTAssertEqual(value[value.index(value.startIndex, offsetBy: 14)], "4")
            XCTAssertTrue("89ab".contains(value[value.index(value.startIndex, offsetBy: 19)]))
        }
        XCTAssertThrowsError(try PracticalTools.uuids(count: 101))
        XCTAssertThrowsError(try PracticalTools.uuids(count: 0))
    }

    func testPasswordsHonorEverySelectedGroupAndLimits() throws {
        for length in [8, 24, 128] {
            let value = try PracticalTools.password(length: length)
            XCTAssertEqual(value.count, length)
            XCTAssertTrue(value.contains(where: \.isUppercase))
            XCTAssertTrue(value.contains(where: \.isLowercase))
            XCTAssertTrue(value.contains(where: \.isNumber))
            XCTAssertTrue(value.contains { !$0.isLetter && !$0.isNumber })
        }
        let digits = try PracticalTools.password(length: 32, uppercase: false, lowercase: false, digits: true, symbols: false)
        XCTAssertTrue(digits.allSatisfy(\.isNumber))
        XCTAssertThrowsError(try PracticalTools.password(length: 7))
        XCTAssertThrowsError(try PracticalTools.password(length: 24, uppercase: false, lowercase: false, digits: false, symbols: false))
    }

    func testTimestampsSecondsMillisecondsOffsetsAndNegativeFractions() throws {
        let date = try PracticalTools.timestamp("1000", milliseconds: true)
        XCTAssertEqual(date.timeIntervalSince1970, 1)
        XCTAssertEqual(try PracticalTools.unix(date, milliseconds: false), "1")
        XCTAssertEqual(try PracticalTools.unix(Date(timeIntervalSince1970: -0.5), milliseconds: false), "-1")
        XCTAssertEqual(try PracticalTools.unix(Date(timeIntervalSince1970: -0.5), milliseconds: true), "-500")
        XCTAssertEqual(try PracticalTools.isoDate("1970-01-01T03:00:00+03:00").timeIntervalSince1970, 0)
        XCTAssertEqual(try PracticalTools.isoDate("1970-01-01T00:00:00.125Z").timeIntervalSince1970, 0.125, accuracy: 0.001)
        for invalid in ["NaN", "Infinity", "999999999999999999999999"] { XCTAssertThrowsError(try PracticalTools.timestamp(invalid, milliseconds: false)) }
        for invalid in ["not a date", "2026-02-30T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T12:00:00+00:99"] {
            XCTAssertThrowsError(try PracticalTools.isoDate(invalid))
        }
        XCTAssertNoThrow(try PracticalTools.isoDate("2024-02-29T23:59:59Z"))
    }

    func testLineDiffReconstructsBothInputsIncludingDuplicateAndBlankLines() throws {
        for (before, after) in [("a\nb\nc", "a\nx\nc"), ("", "a"), ("a\n", ""), ("a\na\nb", "a\nb\na"), ("", ""), ("ş\n\n🙂", "ş\n🙂\n")] {
            let rows = try PracticalTools.diff(before, after)
            let old = rows.filter { $0.kind != .added }.map(\.text).joined(separator: "\n")
            let new = rows.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n")
            XCTAssertEqual(old, before)
            XCTAssertEqual(new, after)
        }
        XCTAssertThrowsError(try PracticalTools.diff(String(repeating: "a\n", count: 2001), "a"))
    }

    func testQRPNGCanBeDecodedAndWiFiEscapesReservedCharacters() throws {
        let text = "MacPocket: İzmir 🌤️"
        let png = try PracticalTools.qrPNG(text)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertTrue(try ScreenTextReader.codes(in: image).contains(text))
        let wifi = try PracticalTools.wifiPayload(ssid: "Office;A", password: #"p:a\ss"#, hidden: true, open: false)
        XCTAssertEqual(wifi, #"WIFI:T:WPA;S:Office\;A;P:p\:a\\ss;H:true;;"#)
        let wifiPNG = try PracticalTools.qrPNG(wifi)
        let wifiSource = try XCTUnwrap(CGImageSourceCreateWithData(wifiPNG as CFData, nil))
        let wifiImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(wifiSource, 0, nil))
        XCTAssertTrue(try ScreenTextReader.codes(in: wifiImage).contains(wifi))
        XCTAssertThrowsError(try PracticalTools.wifiPayload(ssid: "", password: "", hidden: false, open: true))
        XCTAssertThrowsError(try PracticalTools.qrPNG(String(repeating: "x", count: 2049)))
    }

    func testDeepPrettyPrintingCannotExpandWithoutABound() {
        let input = String(repeating: "[", count: 200) + Array(repeating: "0", count: 12_000).joined(separator: ",") + String(repeating: "]", count: 200)
        XCTAssertThrowsError(try PracticalTools.json(input)) { XCTAssertEqual($0 as? PracticalToolError, .expandedJSON) }
        XCTAssertNoThrow(try PracticalTools.json(input, compact: true))
    }

    func testOversizeInputsAreRejectedBeforeProcessing() {
        let huge = String(repeating: "a", count: PracticalTools.maximumInputBytes + 1)
        XCTAssertThrowsError(try PracticalTools.json(huge))
        XCTAssertThrowsError(try PracticalTools.hash(huge, algorithm: .sha256))
        XCTAssertThrowsError(try PracticalTools.base64(huge, decode: false))
        XCTAssertThrowsError(try PracticalTools.diff(huge, ""))
    }
}

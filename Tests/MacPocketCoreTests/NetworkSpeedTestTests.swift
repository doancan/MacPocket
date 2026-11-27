import XCTest
@testable import MacPocketCore

final class SpeedTestOptionsTests: XCTestCase {
    func testDefaultRunsParallelWithMachineReadableOutput() {
        XCTAssertEqual(SpeedTestOptions().arguments, ["-c"])
    }

    func testModesMapToTheToolsFlags() {
        var options = SpeedTestOptions()
        options.mode = .sequential
        XCTAssertEqual(options.arguments, ["-c", "-s"])
        options.mode = .downloadOnly
        XCTAssertEqual(options.arguments, ["-c", "-u"], "download only = skip the upload test")
        options.mode = .uploadOnly
        XCTAssertEqual(options.arguments, ["-c", "-d"])
    }

    func testInterfaceDurationAndRelay() {
        var options = SpeedTestOptions()
        options.interface = "en1"
        options.maximumSeconds = 2
        options.usePrivateRelay = true
        XCTAssertEqual(options.arguments, ["-c", "-I", "en1", "-M", "5", "-p"], "duration clamped to at least 5 s")
    }

    func testInterfaceNamesAreValidatedBeforeReachingTheProcess() {
        XCTAssertTrue(SpeedTestOptions.isValidInterface("en0"))
        XCTAssertTrue(SpeedTestOptions.isValidInterface("pdp_ip0"))
        XCTAssertFalse(SpeedTestOptions.isValidInterface("en0 -C file:///etc"))
        XCTAssertFalse(SpeedTestOptions.isValidInterface("-v"))
        var options = SpeedTestOptions()
        options.interface = "en0; rm"
        XCTAssertEqual(options.arguments, ["-c"])
    }
}

final class SpeedTestParserTests: XCTestCase {
    /// Trimmed from a real `networkQuality -c -M 10` run on macOS 27.2.
    private let real = """
    {"base_rtt":59.892913818359375,"dl_bytes_transferred":223663002,"dl_flows":9,"dl_throughput":215286080,
     "interface_name":"en1","responsiveness":355.74725341796875,"test_endpoint":"deber5-edge-bx-028.aaplimg.com",
     "ul_bytes_transferred":51052541,"ul_flows":10,"ul_throughput":47958200,"os_version":"Version 27.2 (Build 26B123)"}
    """

    func testParsesRealOutput() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try SpeedTestParser.parse(Data(real.utf8), mode: .parallel, now: date)
        XCTAssertEqual(result.downloadBitsPerSecond, 215_286_080)
        XCTAssertEqual(result.uploadBitsPerSecond, 47_958_200)
        XCTAssertEqual(try XCTUnwrap(result.responsivenessRPM), 355.747, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.baseRTTMilliseconds), 59.89, accuracy: 0.01)
        XCTAssertEqual(result.interface, "en1")
        XCTAssertEqual(result.transferredBytes, 274_715_543)
        XCTAssertEqual(result.responsiveness, .medium)
        XCTAssertEqual(result.date, date)
    }

    func testSkippedDirectionIsNil() throws {
        let result = try SpeedTestParser.parse(Data(#"{"dl_throughput":1000000,"ul_throughput":0}"#.utf8), mode: .downloadOnly)
        XCTAssertNil(result.uploadBitsPerSecond)
        XCTAssertEqual(result.downloadBitsPerSecond, 1_000_000)
    }

    func testErrorsAndGarbage() {
        XCTAssertThrowsError(try SpeedTestParser.parse(Data("Downlink: 200 Mbps".utf8), mode: .parallel)) {
            XCTAssertEqual($0 as? SpeedTestParseError, .notJSON)
        }
        XCTAssertThrowsError(try SpeedTestParser.parse(Data(#"{"error_code":-1009}"#.utf8), mode: .parallel))
        XCTAssertThrowsError(try SpeedTestParser.parse(Data(#"{"dl_throughput":0,"ul_throughput":0}"#.utf8), mode: .parallel))
    }

    func testResponsivenessBands() {
        func band(_ rpm: Double) -> SpeedTestResult.Responsiveness? {
            SpeedTestResult(date: Date(), downloadBitsPerSecond: 1, uploadBitsPerSecond: 1, responsivenessRPM: rpm,
                            baseRTTMilliseconds: nil, interface: nil, endpoint: nil, transferredBytes: 0, mode: .parallel).responsiveness
        }
        XCTAssertEqual(band(120), .low)
        XCTAssertEqual(band(300), .medium)
        XCTAssertEqual(band(1500), .high)
    }
}

final class SpeedTestHistoryTests: XCTestCase {
    private func result(_ download: Double?, at seconds: TimeInterval) -> SpeedTestResult {
        SpeedTestResult(date: Date(timeIntervalSince1970: seconds), downloadBitsPerSecond: download, uploadBitsPerSecond: nil,
                        responsivenessRPM: nil, baseRTTMilliseconds: nil, interface: nil, endpoint: nil, transferredBytes: 0, mode: .parallel)
    }

    func testNewestFirstBoundedBestAndMedian() {
        var history = SpeedTestHistory()
        for index in 0..<35 { history.add(result(Double(index), at: Double(index))) }
        XCTAssertEqual(history.results.count, SpeedTestHistory.limit)
        XCTAssertEqual(history.results.first?.downloadBitsPerSecond, 34)
        XCTAssertEqual(history.best(\.downloadBitsPerSecond), 34)
        XCTAssertEqual(history.median(\.downloadBitsPerSecond), 19.5, "median of 5…34")
        XCTAssertNil(history.median(\.uploadBitsPerSecond))
    }

    func testRoundTrip() throws {
        var history = SpeedTestHistory()
        history.add(result(5e7, at: 1_800_000_000))
        let decoded = try JSONDecoder().decode(SpeedTestHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
    }

    func testBitRateFormatting() {
        XCTAssertEqual(SpeedFormatter.bitRate(215_286_080), "215 Mbps")
        XCTAssertEqual(SpeedFormatter.bitRate(47_958_200), "48,0 Mbps")
        XCTAssertEqual(SpeedFormatter.bitRate(1_200_000_000), "1,2 Gbps")
        XCTAssertEqual(SpeedFormatter.bitRate(850_000), "850 kbps")
        XCTAssertEqual(SpeedFormatter.bitRate(nil), "—")
    }
}

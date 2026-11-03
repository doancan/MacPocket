import XCTest
@testable import MacPocketCore

final class NetworkTrafficTests: XCTestCase {
    func testParsesNettopCSVWithDottedNames() {
        let output = """
        ,bytes_in,bytes_out,
        launchd.1,0,0,
        apsd.389,6597788,3273957,
        2.1.316.6777,31435,17364,
        com.docker.back.36335,0,0,
        broken line
        noPid,1,2,
        """
        let samples = NetworkTraffic.parse(output)
        XCTAssertEqual(samples.map(\.pid), [1, 389, 6777, 36335])
        XCTAssertEqual(samples[1], NetworkTrafficSample(pid: 389, name: "apsd", bytesIn: 6_597_788, bytesOut: 3_273_957))
        XCTAssertEqual(samples[2].name, "2.1.316")
        XCTAssertEqual(samples[3].name, "com.docker.back")
    }

    func testRatesAndSessionTotals() {
        var tracker = NetworkTrafficTracker()
        let start = Date(timeIntervalSince1970: 0)
        let first = tracker.update([.init(pid: 10, name: "Safari", bytesIn: 5_000, bytesOut: 1_000)], at: start)
        XCTAssertEqual(first[0].downloadRate, 0)
        XCTAssertEqual(first[0].sessionDownload, 0, "Traffic before watching isn't counted")

        let second = tracker.update([.init(pid: 10, name: "Safari", bytesIn: 9_000, bytesOut: 2_000),
                                     .init(pid: 20, name: "Mail", bytesIn: 700, bytesOut: 0)], at: start.addingTimeInterval(2))
        XCTAssertEqual(second.map(\.pid), [10, 20], "Busiest first")
        XCTAssertEqual(second[0].downloadRate, 2_000)
        XCTAssertEqual(second[0].uploadRate, 500)
        XCTAssertEqual(second[0].sessionDownload, 4_000)
        XCTAssertEqual(second[1].sessionDownload, 0, "New process starts at zero")
        XCTAssertFalse(second[1].isActive)
    }

    func testReusedPIDStartsOver() {
        var tracker = NetworkTrafficTracker()
        let start = Date(timeIntervalSince1970: 0)
        _ = tracker.update([.init(pid: 10, name: "old", bytesIn: 9_000, bytesOut: 9_000)], at: start)
        let rows = tracker.update([.init(pid: 10, name: "new", bytesIn: 100, bytesOut: 50)], at: start.addingTimeInterval(2))
        XCTAssertEqual(rows[0].name, "new")
        XCTAssertEqual(rows[0].downloadRate, 0)
        XCTAssertEqual(rows[0].sessionTotal, 0)
    }

    func testExitedProcessesDropOut() {
        var tracker = NetworkTrafficTracker()
        let start = Date(timeIntervalSince1970: 0)
        _ = tracker.update([.init(pid: 10, name: "a", bytesIn: 1, bytesOut: 1)], at: start)
        XCTAssertTrue(tracker.update([], at: start.addingTimeInterval(2)).isEmpty)
    }
}

final class NetworkTrafficGroupingTests: XCTestCase {
    func testHelpersSumIntoTheirApp() {
        let rows = [
            NetworkTrafficRow(pid: 1, name: "Google Chrome", downloadRate: 100, uploadRate: 10, sessionDownload: 1_000, sessionUpload: 100),
            NetworkTrafficRow(pid: 2, name: "Google Chrome He", downloadRate: 400, uploadRate: 0, sessionDownload: 5_000, sessionUpload: 0),
            NetworkTrafficRow(pid: 3, name: "mDNSResponder", downloadRate: 600, uploadRate: 0, sessionDownload: 10, sessionUpload: 0),
        ]
        let groups = NetworkTraffic.group(rows) { $0.pid == 3 ? nil : ("/Applications/Google Chrome.app", "Google Chrome") }
        XCTAssertEqual(groups.map(\.name), ["mDNSResponder", "Google Chrome"], "600 B/s beats 510 B/s")
        let chrome = groups.first { $0.name == "Google Chrome" }
        XCTAssertEqual(chrome?.downloadRate, 500)
        XCTAssertEqual(chrome?.sessionTotal, 6_100)
        XCTAssertEqual(chrome?.rows.count, 2)
    }
}

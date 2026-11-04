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
    func testLargeHelperGroupsPreserveTotalsAndOrdering() {
        let rows: [NetworkTrafficRow] = (1...24_000).map { (index: Int) -> NetworkTrafficRow in
            NetworkTrafficRow(pid: Int32(index), name: "helper", downloadRate: Double(index % 17),
                              uploadRate: Double(index % 7), sessionDownload: UInt64(index), sessionUpload: 1)
        }
        let start = ContinuousClock.now
        var groups: [NetworkTrafficGroup] = []
        for _ in 0..<20 {
            groups = NetworkTraffic.group(rows) { row in
                let app = row.pid % 240
                return ("app:\(app)", "App \(app)")
            }
        }
        print("TRAFFIC_GROUPING_20_ITERATIONS: \(start.duration(to: .now))")
        XCTAssertEqual(groups.count, 240)
        XCTAssertTrue(groups.allSatisfy { $0.rows.count == 100 })
        XCTAssertEqual(groups.reduce(0) { $0 + $1.downloadRate }, rows.reduce(0) { $0 + $1.downloadRate })
        XCTAssertEqual(groups.reduce(UInt64(0)) { $0 + $1.sessionTotal }, rows.reduce(UInt64(0)) { $0 + $1.sessionTotal })
        XCTAssertTrue(zip(groups, groups.dropFirst()).allSatisfy { $0.totalRate >= $1.totalRate })
    }

    func testIdleGroupsSortBySessionTotalsThenName() {
        let rows = [NetworkTrafficRow(pid: 1, name: "A", downloadRate: 0, uploadRate: 0, sessionDownload: 40, sessionUpload: 10),
                    NetworkTrafficRow(pid: 2, name: "Z", downloadRate: 0, uploadRate: 0, sessionDownload: 90, sessionUpload: 10),
                    NetworkTrafficRow(pid: 3, name: "B", downloadRate: 0, uploadRate: 0, sessionDownload: 20, sessionUpload: 30)]
        let groups = NetworkTraffic.group(rows) { _ in nil }
        XCTAssertEqual(groups.map(\.name), ["Z", "A", "B"])
        XCTAssertTrue(groups.allSatisfy { !$0.isActive })
        XCTAssertEqual(groups.first?.sessionDownload, 90)
        XCTAssertEqual(groups.first?.sessionUpload, 10)
    }

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

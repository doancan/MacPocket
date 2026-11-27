import XCTest
@testable import MacPocketCore

final class ConnectionOutageLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testOfflineThenOnlineRecordsOneOutage() {
        var log = ConnectionOutageLog()
        XCTAssertNil(log.update(online: true, at: t0), "the first reading only sets the baseline")
        XCTAssertEqual(log.update(online: false, at: t0 + 10), .wentOffline)
        XCTAssertNil(log.update(online: false, at: t0 + 20), "repeated readings change nothing")
        XCTAssertEqual(log.update(online: true, at: t0 + 70), .cameBack(duration: 60))
        XCTAssertEqual(log.outages, [ConnectionOutage(start: t0 + 10, end: t0 + 70)])
        XCTAssertNil(log.ongoingSince)
    }

    func testOngoingOutageIsReportedAndStartingOfflineCounts() {
        var log = ConnectionOutageLog()
        XCTAssertEqual(log.update(online: false, at: t0), .wentOffline)
        XCTAssertEqual(log.ongoingSince, t0)
        XCTAssertTrue(log.outages.isEmpty)
    }

    func testFlapsShorterThanTheMinimumAreNotKept() {
        var log = ConnectionOutageLog()
        _ = log.update(online: true, at: t0)
        _ = log.update(online: false, at: t0 + 1)
        XCTAssertEqual(log.update(online: true, at: t0 + 2), .cameBack(duration: 1))
        XCTAssertTrue(log.outages.isEmpty, "a one-second blip (Wi-Fi roaming) is not an outage")
    }

    func testHistoryIsCappedNewestFirstAndCodable() throws {
        var log = ConnectionOutageLog()
        _ = log.update(online: true, at: t0)
        for index in 0..<(ConnectionOutageLog.limit + 5) {
            let start = t0 + Double(index) * 100
            _ = log.update(online: false, at: start)
            _ = log.update(online: true, at: start + 30)
        }
        XCTAssertEqual(log.outages.count, ConnectionOutageLog.limit)
        XCTAssertGreaterThan(log.outages[0].start, log.outages[1].start)
        let decoded = try JSONDecoder().decode(ConnectionOutageLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
    }

    func testClockGoingBackwardsNeverMakesNegativeDurations() {
        var log = ConnectionOutageLog()
        _ = log.update(online: false, at: t0 + 100)
        XCTAssertEqual(log.update(online: true, at: t0), .cameBack(duration: 0))
        XCTAssertTrue(log.outages.isEmpty)
    }
}

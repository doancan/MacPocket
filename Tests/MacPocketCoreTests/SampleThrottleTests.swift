import XCTest
@testable import MacPocketCore

final class SampleThrottleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testReusesTheReadingUntilItIsStale() {
        var throttle = SampleThrottle<Int>(interval: 5)
        var reads = 0
        func read() -> Int { reads += 1; return reads }
        XCTAssertEqual(throttle.value(now: start, read: read), 1)
        XCTAssertEqual(throttle.value(now: start + 1, read: read), 1)
        XCTAssertEqual(throttle.value(now: start + 4.9, read: read), 1)
        XCTAssertEqual(throttle.value(now: start + 5, read: read), 2, "a reading exactly `interval` old is refreshed")
        XCTAssertEqual(reads, 2)
    }

    func testAClockThatGoesBackReadsAgain() {
        var throttle = SampleThrottle<Int>(interval: 5)
        var reads = 0
        _ = throttle.value(now: start) { reads += 1; return reads }
        // A wall-clock change must not pin an old reading for the size of the jump.
        XCTAssertEqual(throttle.value(now: start - 60) { reads += 1; return reads }, 2)
    }

    func testANilReadingIsCachedToo() {
        var throttle = SampleThrottle<Int?>(interval: 5)
        var reads = 0
        _ = throttle.value(now: start) { reads += 1; return nil }
        _ = throttle.value(now: start + 1) { reads += 1; return nil }
        XCTAssertEqual(reads, 1, "a Mac without sensors is not probed every tick")
    }
}

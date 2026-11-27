import XCTest
@testable import MacPocketCore

final class ProcessEnergySamplerTests: XCTestCase {
    /// Names are resolved only for the rows returned; the rows stay ranked, named and within the limit.
    func testSampleReturnsNamedRankedRowsWithinTheLimit() async throws {
        let sampler = ProcessEnergySampler()
        let primed = await sampler.sample()
        XCTAssertTrue(primed.processes.isEmpty, "the first call only primes the counters")
        // Some work so at least this process has CPU time in the interval.
        var sink = 0.0
        let end = Date().addingTimeInterval(0.3)
        while Date() < end { sink += sin(sink + 1) }
        XCTAssertFalse(sink.isNaN)
        let sample = await sampler.sample(limit: 5)
        XCTAssertLessThanOrEqual(sample.processes.count, 5)
        XCTAssertFalse(sample.processes.isEmpty)
        XCTAssertTrue(sample.processes.allSatisfy { !$0.name.isEmpty }, "\(sample.processes.map(\.name))")
        let order = sample.processes.map(\.milliwatts)
        XCTAssertEqual(order, order.sorted(by: >), "most power first")
    }
}

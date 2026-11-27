import XCTest
@testable import MacPocketApp
@testable import MacPocketCore
import MacPocketTestSupport

@MainActor
final class ConnectionWatchServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var posted: [String] = []
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() async throws {
        try await super.setUp()
        defaults = temporaryDefaults()
        defaults.set(true, forKey: ConnectionWatchService.alertsKey)
        posted = []
    }


    private func makeService() -> ConnectionWatchService {
        ConnectionWatchService(defaults: defaults, announceDelay: .milliseconds(50)) { [weak self] _, _, id in self?.posted.append(id) }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    func testLongOutageAnnouncesDropAndRecoveryAndIsKept() async {
        let service = makeService()
        service.record(online: true, at: t0)
        service.record(online: false, at: t0 + 1)
        await settle()
        service.record(online: true, at: t0 + 61)
        await settle()
        XCTAssertEqual(posted, ["down", "up"])
        XCTAssertEqual(service.log.outages.count, 1)
        // Persisted: a new service on the same defaults sees the history.
        XCTAssertEqual(ConnectionWatchService(defaults: defaults).log.outages.count, 1)
    }

    func testFlapShorterThanTheDelayStaysSilent() async {
        let service = makeService()
        service.record(online: true, at: t0)
        service.record(online: false, at: t0)
        service.record(online: true, at: t0 + 0.01)
        await settle()
        XCTAssertTrue(posted.isEmpty)
    }

    func testStartingOfflineIsNotNewsAndAlertsOffStaysSilent() async {
        let service = makeService()
        service.record(online: false, at: t0)
        await settle()
        XCTAssertTrue(posted.isEmpty, "the first reading after launch is only the baseline")

        defaults.set(false, forKey: ConnectionWatchService.alertsKey)
        let quiet = makeService()
        quiet.record(online: true, at: t0)
        quiet.record(online: false, at: t0 + 1)
        await settle()
        quiet.record(online: true, at: t0 + 100)
        await settle()
        XCTAssertTrue(posted.isEmpty)
        XCTAssertEqual(quiet.log.outages.count, 1, "outages are still recorded with notifications off")
    }

    func testClearingHistoryPersists() {
        let service = makeService()
        service.record(online: true, at: t0)
        service.record(online: false, at: t0 + 1)
        service.record(online: true, at: t0 + 30)
        service.clearHistory()
        XCTAssertTrue(ConnectionWatchService(defaults: defaults).log.outages.isEmpty)
    }
}

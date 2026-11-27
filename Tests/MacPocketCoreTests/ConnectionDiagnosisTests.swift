import XCTest
@testable import MacPocketCore

final class ConnectionDiagnosisTests: XCTestCase {
    private func probe(_ milliseconds: Double?, loss: Double = 0) -> ConnectionProbe {
        ConnectionProbe(milliseconds: milliseconds, loss: milliseconds == nil ? 1 : loss)
    }

    private func measurement(link: Bool = true, router: ConnectionProbe? = nil, internet: ConnectionProbe,
                             dns: ConnectionProbe, rssi: Int? = nil) -> ConnectionMeasurement {
        ConnectionMeasurement(hasLink: link, gateway: router == nil ? nil : "192.168.1.1", router: router,
                              internet: internet, dns: dns, wifiRSSI: rssi)
    }

    func testNoLinkWinsOverEverythingElse() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(link: false, internet: probe(nil), dns: probe(nil))), .noLink)
    }

    func testRouterIsBlamedOnlyWhenTheInternetIsAlsoUnreachable() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(nil), internet: probe(nil), dns: probe(nil))),
                       .routerUnreachable)
        // Many routers ignore ping; a working internet path means the router is fine.
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(nil), internet: probe(12), dns: probe(20))), .healthy)
    }

    func testRouterUpButNoInternetIsTheProvider() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(3), internet: probe(nil), dns: probe(nil))), .noInternet)
    }

    func testBlockedPingWithWorkingDNSIsNotAnOutage() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(3), internet: probe(nil), dns: probe(25))), .healthy)
    }

    func testInternetUpButNamesFailingIsDNS() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(3), internet: probe(14), dns: probe(nil))), .dnsFailing)
    }

    func testWeakWiFiNeedsBothAWeakSignalAndASlowOrLossyRouter() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(45), internet: probe(60), dns: probe(30), rssi: -80)), .weakWiFi)
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(4), internet: probe(15), dns: probe(20), rssi: -80)), .healthy)
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(5, loss: 1.0 / 3), internet: probe(15), dns: probe(20), rssi: -78)), .weakWiFi)
    }

    func testSlowLatencyLossOrDNS() {
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(3), internet: probe(220), dns: probe(20))), .slow)
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(3), internet: probe(20, loss: 1.0 / 3), dns: probe(20))), .slow)
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(router: probe(3), internet: probe(20), dns: probe(900))), .slow)
        XCTAssertEqual(ConnectionDiagnosis.verdict(measurement(internet: probe(20), dns: probe(30))), .healthy)
    }

    func testOneSpikeDoesNotMakeAFastLinkLookSlow() {
        // Wi-Fi power saving or a busy moment delays one echo; the median of three ignores it.
        let output = """
        3 packets transmitted, 3 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 4.000/340.000/1010.000/474.000 ms
        """
        XCTAssertEqual(ConnectionProbe.parsePing(output).milliseconds ?? 0, 6, accuracy: 0.001)
    }

    func testPingSummaryParsing() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes

        --- 1.1.1.1 ping statistics ---
        3 packets transmitted, 2 packets received, 33.3% packet loss
        round-trip min/avg/max/stddev = 14.112/15.650/17.188/1.538 ms
        """
        let probe = ConnectionProbe.parsePing(output)
        XCTAssertEqual(probe.milliseconds ?? 0, 15.65, accuracy: 0.001)
        XCTAssertEqual(probe.loss, 0.333, accuracy: 0.001)
        XCTAssertTrue(probe.reachable)

        let lost = ConnectionProbe.parsePing("3 packets transmitted, 0 packets received, 100.0% packet loss")
        XCTAssertNil(lost.milliseconds)
        XCTAssertEqual(lost.loss, 1)
        XCTAssertFalse(lost.reachable)
        XCTAssertFalse(ConnectionProbe.parsePing("").reachable, "no output means unreachable, never a crash")
    }
}

import XCTest
@testable import MacPocketCore

final class ListeningPortsTests: XCTestCase {
    /// Shape of real `lsof -nP -a -u <uid> -iTCP -sTCP:LISTEN -iUDP -F pcPtn` output on macOS 27.
    private let output = """
    p953
    crapportd
    f13
    tIPv4
    PTCP
    n*:50609
    f16
    tIPv6
    PTCP
    n*:50609
    p1264
    cControlCenter
    f10
    tIPv4
    PTCP
    n*:7000
    f11
    tIPv6
    PTCP
    n*:7000
    p2001
    cpostgres
    f7
    tIPv6
    PTCP
    n[::1]:5432
    f8
    tIPv4
    PTCP
    n127.0.0.1:5432
    p941
    cidentityservicesd
    f10
    tIPv4
    PUDP
    n*:*
    f12
    tIPv4
    PUDP
    n192.168.1.5:61000->17.57.0.1:443
    p3000
    cnode
    f22
    tIPv4
    PTCP
    n*:3000
    f23
    tIPv4
    PUDP
    n*:5353
    """

    func testGroupsByProcessMergesIPv4AndIPv6AndSortsByPort() {
        let owners = ListeningPorts.parse(output)
        XCTAssertEqual(owners.map(\.command), ["node", "postgres", "ControlCenter", "rapportd"])
        XCTAssertEqual(owners.first { $0.command == "ControlCenter" }?.sockets.count, 1, "IPv4 + IPv6 on *:7000 is one entry")
        XCTAssertEqual(owners.first { $0.command == "node" }?.ports, [3000, 5353])
    }

    func testSkipsUnboundAndConnectedUDPSockets() {
        XCTAssertNil(ListeningPorts.parse(output).first { $0.command == "identityservicesd" })
    }

    func testDistinguishesLocalOnlyFromExposed() throws {
        let owners = ListeningPorts.parse(output)
        let postgres = try XCTUnwrap(owners.first { $0.command == "postgres" })
        XCTAssertFalse(postgres.isExposed)
        XCTAssertEqual(postgres.sockets.first?.serviceName, "PostgreSQL")
        XCTAssertTrue(try XCTUnwrap(owners.first { $0.command == "node" }).isExposed)
    }

    func testSocketNameParsing() {
        XCTAssertEqual(ListeningPorts.socket("[::1]:8080", transport: .tcp, isIPv6: true)?.address, "::1")
        XCTAssertEqual(ListeningPorts.socket("[::1]:8080", transport: .tcp, isIPv6: true)?.isLocalOnly, true)
        XCTAssertNil(ListeningPorts.socket("*:*", transport: .udp, isIPv6: false))
        XCTAssertNil(ListeningPorts.socket("a:1->b:2", transport: .tcp, isIPv6: false))
        XCTAssertEqual(ListeningPorts.socket("fe80::1%lo0:631", transport: .tcp, isIPv6: true)?.port, 631)
    }

    func testArguments() {
        XCTAssertEqual(ListeningPorts.arguments(includeUDP: false, userID: 501),
                       ["-nP", "-a", "-u", "501", "-iTCP", "-sTCP:LISTEN", "-F", "pcPtn"])
        XCTAssertTrue(ListeningPorts.arguments(includeUDP: true, userID: 501).contains("-iUDP"))
    }

    func testEmptyOrGarbageInput() {
        XCTAssertEqual(ListeningPorts.parse(""), [])
        XCTAssertEqual(ListeningPorts.parse("lsof: WARNING\nxyz"), [])
    }
}

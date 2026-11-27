import XCTest
@testable import MacPocketCore

final class OpenConnectionTests: XCTestCase {
    func testParsesLsofFieldOutputIntoConnectionsPerProcess() {
        let output = """
        p627
        cidentityservicesd
        n[fe80:1f::474c]:1025->[fe80:1f::8a3b]:1027
        n*:5353
        p1463
        cGoogle Chrome
        n192.168.50.231:52100->142.250.187.110:443
        n192.168.50.231:52101->142.250.187.110:443
        """
        let connections = OpenConnection.parseLsof(output)
        XCTAssertEqual(connections.count, 3, "listening sockets without a peer are left out")
        XCTAssertEqual(connections[0], OpenConnection(process: "identityservicesd", pid: 627,
                                                      local: "[fe80:1f::474c]:1025", remote: "[fe80:1f::8a3b]:1027"))
        XCTAssertEqual(connections[1].process, "Google Chrome")
        XCTAssertEqual(connections[1].remote, "142.250.187.110:443")
        XCTAssertEqual(connections[1].remotePort, 443)
        XCTAssertEqual(connections[0].remotePort, 1027)
    }

    func testGroupsByProcessBusiestFirst() {
        let rows = [OpenConnection(process: "a", pid: 1, local: "x:1", remote: "y:1"),
                    OpenConnection(process: "b", pid: 2, local: "x:2", remote: "y:2"),
                    OpenConnection(process: "b", pid: 2, local: "x:3", remote: "y:3")]
        let groups = OpenConnection.grouped(rows)
        XCTAssertEqual(groups.map(\.process), ["b", "a"])
        XCTAssertEqual(groups.first?.connections.count, 2)
    }

    func testGarbageAndEmptyOutputAreHarmless() {
        XCTAssertTrue(OpenConnection.parseLsof("").isEmpty)
        XCTAssertTrue(OpenConnection.parseLsof("n1.2.3.4:5->6.7.8.9:10").allSatisfy { $0.pid == 0 })
        XCTAssertNil(OpenConnection(process: "x", pid: 1, local: "a", remote: "no-port").remotePort)
    }
}

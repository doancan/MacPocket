import XCTest
@testable import MacPocketCore

final class LANHelperDiscoveryTests: XCTestCase {
    func testWizardHelperInstallationIdentityRemainsStable() throws {
        XCTAssertEqual(NSStringFromProtocol(MacPocketHelperXPC.self), "FanHelperXPC")
        XCTAssertEqual(MacPocketHelperConstants.machServiceName, "com.doancan.MacPocket.FanHelper")
        XCTAssertEqual(MacPocketHelperConstants.daemonPlistName, "com.doancan.MacPocket.FanHelper.plist")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Daemons/" + MacPocketHelperConstants.daemonPlistName))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, MacPocketHelperConstants.machServiceName)
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/MacPocketFanHelper")
        XCTAssertEqual((plist["MachServices"] as? [String: Bool])?[MacPocketHelperConstants.machServiceName], true)
    }

    func testHelperValidatesItsOwnRequest() throws {
        XCTAssertEqual(try LANHelperScanRequest(cidr: "192.168.2.7/24", interface: "en1").subnet.description, "192.168.2.0/24")
        for cidr in ["192.168.2.0/16", "192.168.2.0/24; id", "invalid"] {
            XCTAssertThrowsError(try LANHelperScanRequest(cidr: cidr, interface: "en1"))
        }
        for interface in ["", "en1;id", "en1\n", "é1", String(repeating: "e", count: 16)] {
            XCTAssertThrowsError(try LANHelperScanRequest(cidr: "192.168.2.0/24", interface: interface))
        }
    }

    func testOrdinaryScanAutomaticallyCompletesEveryRoutedNetwork() async throws {
        let local = LANNetworkInfo(interface: "en1", address: "192.168.0.45", subnet: LANSubnet.parse(cidr: "192.168.0.0/24")!, gateway: nil)
        var routed = LANNetworkInfo(interface: "", address: local.address, subnet: LANSubnet.parse(cidr: "192.168.2.0/24")!, gateway: nil, isLocal: false)
        routed.viaInterface = "en1"
        var second = routed
        second = LANNetworkInfo(interface: "", address: local.address, subnet: LANSubnet.parse(cidr: "192.168.3.0/24")!, gateway: nil, isLocal: false)
        second.viaInterface = "en1"
        let reports = [LANScanResult(network: local, devices: [], date: .distantPast),
                       LANScanResult(network: routed, devices: [], date: .distantPast),
                       LANScanResult(network: second, devices: [], date: .distantPast)]
        let completed = try await LANHelperDiscovery.complete(reports) { network in
            XCTAssertFalse(network.isLocal, "Attached networks already have normal ARP discovery")
            if network.subnet.description == "192.168.2.0/24" {
                return ["192.168.2.12": "3C:52:A1:3E:DA:A8", "192.168.4.1": "00:1B:21:00:00:01"]
            }
            return ["192.168.3.9": "18:A6:F7:DF:8F:5C"]
        }
        XCTAssertTrue(completed[0].devices.isEmpty)
        XCTAssertEqual(completed[1].devices.map(\.ip), ["192.168.2.12"], "Discover hosts absent from the ordinary ICMP scan")
        XCTAssertEqual(completed[1].devices.first?.macSource, .arp)
        XCTAssertEqual(completed[2].devices.first?.ip, "192.168.3.9")
    }

    func testHelperErrorIsNotReportedAsAnEmptySuccessfulScan() async {
        let network = LANNetworkInfo(interface: "", address: "", subnet: LANSubnet.parse(cidr: "192.168.2.0/24")!, gateway: nil, isLocal: false)
        do {
            _ = try await LANHelperDiscovery.complete([LANScanResult(network: network, devices: [], date: .distantPast)]) { _ in
                throw LANHelperError.scanFailed
            }
            XCTFail("The application must display the helper error and keep the ordinary scan results")
        } catch { XCTAssertEqual(error as? LANHelperError, .scanFailed) }
    }
}

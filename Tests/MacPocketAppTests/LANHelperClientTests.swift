import XCTest
@testable import MacPocketApp
@testable import MacPocketCore

@MainActor final class LANHelperClientTests: XCTestCase {
    /// NSXPC reports an unreachable service through the proxy's error handler on its own queue. A handler
    /// inferred as main-actor isolated traps there and takes the app down; the scan must fail with the error
    /// instead.
    func testUnreachableHelperFailsTheScanInsteadOfCrashing() async {
        var network = LANNetworkInfo(interface: "en1", address: "192.168.0.45",
                                     subnet: LANSubnet.parse(cidr: "192.168.0.0/24")!, gateway: nil)
        network.viaInterface = "en1"
        let client = LANHelperClient(machServiceName: "com.doancan.MacPocket.tests.unreachable." + UUID().uuidString,
                                     verifiesInstallation: false)
        do {
            _ = try await client.discover(network)
            XCTFail("an unreachable helper can't return addresses")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }
}

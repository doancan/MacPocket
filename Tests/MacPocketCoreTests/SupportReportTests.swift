import XCTest
@testable import MacPocketCore

final class SupportReportTests: XCTestCase {
    private func input() -> SupportReport.Input {
        var snapshot = SystemSnapshot(
            capturedAt: Date(), hardwareModel: "Mac13,1", logicalCPUCount: 10, cpuUserPercent: 10, cpuSystemPercent: 5, cpuIdlePercent: 85,
            physicalMemoryBytes: 32 << 30, freeMemoryBytes: 1 << 30, wiredMemoryBytes: 2 << 30, compressedMemoryBytes: 1 << 30,
            appMemoryBytes: 8 << 30, swapUsedBytes: 0, uptimeSeconds: 7200, thermalState: "nominal",
            volumes: [VolumeSnapshot(name: "Macintosh HD", path: "/", totalBytes: 500 << 30, availableBytes: 125 << 30),
                      VolumeSnapshot(name: "Yedek", path: "/Users/dogancan/Yedek", totalBytes: 100, availableBytes: 50)],
            power: PowerSnapshot(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil, lowPowerMode: false))
        snapshot.network = NetworkSnapshot(receivedBytesPerSecond: 0, sentBytesPerSecond: 0, primaryInterface: "en1",
                                           localIPv4: "192.168.50.201", totalReceivedBytes: 0, totalSentBytes: 0)
        return SupportReport.Input(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), appVersion: "0.3.0", osVersion: "macOS 27.2",
            computerName: "Doğancan’s Mac Studio", userName: "dogancan", snapshot: snapshot,
            processes: [.init(name: "/Users/dogancan/bin/tool|x", cpuPercent: 12.34, memoryBytes: 1 << 30)],
            ports: [PortOwner(pid: 1, command: "node", sockets: [ListeningSocket(transport: .tcp, address: "*", port: 3000, isIPv6: false)]),
                    PortOwner(pid: 2, command: "postgres", sockets: [ListeningSocket(transport: .tcp, address: "127.0.0.1", port: 5432, isIPv6: false)])],
            attention: ["Disk alanı azaldı"])
    }

    private func report(_ options: SupportReport.Options = .init()) -> String {
        SupportReport.markdown(input(), options: options) { "\($0 >> 30) GB" }
    }

    func testMasksPrivateDetailsByDefault() {
        let text = report()
        XCTAssertFalse(text.contains("Doğancan’s Mac Studio"))
        XCTAssertFalse(text.contains("dogancan"))
        XCTAssertFalse(text.contains("192.168.50.201"))
        XCTAssertTrue(text.contains("192.168.x.x"), "the network part stays for diagnosis")
        XCTAssertTrue(text.contains("`~/Yedek`"))
    }

    func testCanIncludeEverythingWhenAsked() {
        var options = SupportReport.Options()
        options.maskPrivateDetails = false
        let text = report(options)
        XCTAssertTrue(text.contains("Doğancan’s Mac Studio"))
        XCTAssertTrue(text.contains("192.168.50.201"))
    }

    func testListsOnlyExposedPortsAndEscapesTableCells() {
        let text = report()
        XCTAssertTrue(text.contains("- node: 3000"))
        XCTAssertFalse(text.contains("postgres"), "loopback-only listeners aren't a concern")
        XCTAssertTrue(text.contains("~/bin/tool\\|x"), "a pipe in a name can't break the table")
        XCTAssertTrue(text.contains("- Disk alanı azaldı"))
    }

    func testSectionsCanBeLeftOut() {
        var options = SupportReport.Options()
        options.includeProcesses = false
        options.includePorts = false
        let text = report(options)
        XCTAssertFalse(text.contains("| CPU |"))
        XCTAssertFalse(text.contains("node"))
    }

    func testMaskHelpers() {
        XCTAssertEqual(SupportReport.mask("/Users/ali/Desktop", user: "ali"), "~/Desktop")
        XCTAssertEqual(SupportReport.mask("anything", user: ""), "anything")
        XCTAssertEqual(SupportReport.maskAddress("10.0.0.7"), "10.0.x.x")
        XCTAssertTrue(SupportReport.maskAddress("fe80::1").hasPrefix("‹"))
    }
}

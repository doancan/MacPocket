import XCTest
@testable import MacPocketCore

final class StartupItemsTests: StorageFixtureCase {
    private func plist(_ entries: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
    }

    func testParsesProgramArgumentsAndFlags() throws {
        let data = try plist(["Label": "com.example.sync", "ProgramArguments": ["/Applications/Sync Tool.app/Contents/MacOS/sync", "--quiet"],
                              "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false]])
        let item = try XCTUnwrap(StartupItems.parse(data, url: URL(fileURLWithPath: "/u/LaunchAgents/com.example.sync.plist"),
                                                    scope: .userAgent, disabledLabels: []))
        XCTAssertEqual(item.label, "com.example.sync")
        XCTAssertEqual(item.program, "/Applications/Sync Tool.app/Contents/MacOS/sync")
        XCTAssertEqual(item.appName, "Sync Tool")
        XCTAssertTrue(item.runsAtLoad)
        XCTAssertTrue(item.keepsAlive, "A KeepAlive dictionary also keeps the job running")
        XCTAssertEqual(item.kind, .direct)
        XCTAssertTrue(item.isEnabled)
    }

    func testProgramKeyAndDefaultsWhenFlagsAreMissing() throws {
        let item = try XCTUnwrap(StartupItems.parse(try plist(["Label": "org.tool.helper", "Program": "/usr/local/bin/helper"]),
                                                    url: URL(fileURLWithPath: "/x.plist"), scope: .userAgent, disabledLabels: []))
        XCTAssertEqual(item.program, "/usr/local/bin/helper")
        XCTAssertNil(item.appName)
        XCTAssertFalse(item.runsAtLoad)
        XCTAssertFalse(item.keepsAlive)
    }

    func testClassesFollowScopeAndOwner() throws {
        func kind(_ label: String, _ scope: StartupScope) throws -> StartupClass {
            try XCTUnwrap(StartupItems.parse(try plist(["Label": label]), url: URL(fileURLWithPath: "/x.plist"),
                                             scope: scope, disabledLabels: [])).kind
        }
        XCTAssertEqual(try kind("com.example.a", .userAgent), .direct)
        XCTAssertEqual(try kind("com.example.a", .globalAgent), .systemManaged, "Needs an administrator")
        XCTAssertEqual(try kind("com.example.a", .globalDaemon), .systemManaged)
        XCTAssertEqual(try kind("com.apple.something", .userAgent), .readOnly, "Apple's items are never offered for change")
    }

    func testDisabledByLaunchctlOrByThePlist() throws {
        let url = URL(fileURLWithPath: "/x.plist")
        XCTAssertFalse(try XCTUnwrap(StartupItems.parse(try plist(["Label": "a.b"]), url: url, scope: .userAgent, disabledLabels: ["a.b"])).isEnabled)
        XCTAssertFalse(try XCTUnwrap(StartupItems.parse(try plist(["Label": "a.b", "Disabled": true]), url: url, scope: .userAgent,
                                                        disabledLabels: [])).isEnabled)
    }

    func testRejectsMalformedAndLabelessPlists() throws {
        let url = URL(fileURLWithPath: "/x.plist")
        XCTAssertNil(StartupItems.parse(Data("not a plist".utf8), url: url, scope: .userAgent, disabledLabels: []))
        XCTAssertNil(StartupItems.parse(try plist(["Program": "/bin/true"]), url: url, scope: .userAgent, disabledLabels: []))
        XCTAssertNil(StartupItems.parse(try plist(["Label": ""]), url: url, scope: .userAgent, disabledLabels: []))
    }

    func testParsesLaunchctlDisabledList() {
        let output = """
        disabled services = {
        \t"com.example.off" => disabled
        \t"com.example.on" => enabled
        \t"com.example.also-off" => true
        }
        """
        XCTAssertEqual(StartupItems.parseDisabled(output), ["com.example.off", "com.example.also-off"])
        XCTAssertTrue(StartupItems.parseDisabled("").isEmpty)
    }

    func testScanReadsEveryFolderAndSortsDirectItemsFirst() throws {
        let user = try directory(try fixture().appendingPathComponent("user"))
        let global = try directory(try fixture().appendingPathComponent("global"))
        try plist(["Label": "com.zeta.agent"]).write(to: user.appendingPathComponent("com.zeta.agent.plist"))
        try plist(["Label": "com.alpha.daemon"]).write(to: global.appendingPathComponent("com.alpha.daemon.plist"))
        try Data("junk".utf8).write(to: user.appendingPathComponent("broken.plist"))
        try Data("x".utf8).write(to: user.appendingPathComponent("readme.txt"))
        let items = StartupItems.scan(directories: [(user, .userAgent), (global, .globalDaemon)], disabledLabels: [])
        XCTAssertEqual(items.map(\.label), ["com.zeta.agent", "com.alpha.daemon"], "Direct before system-managed, then by label")
        XCTAssertEqual(StartupItems.scan(directories: [(user.appendingPathComponent("missing"), .userAgent)], disabledLabels: []), [])
    }
}

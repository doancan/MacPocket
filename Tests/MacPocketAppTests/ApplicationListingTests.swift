import XCTest
@testable import MacPocketApp
@testable import MacPocketCore

@MainActor final class ApplicationListingTests: XCTestCase {
    private func app(_ name: String, _ bundleID: String, _ channel: ApplicationChannel, at directory: String = "/Applications",
                     sipProtected: Bool = false) throws -> InstalledApplication {
        InstalledApplication(url: URL(fileURLWithPath: "\(directory)/\(name).app"), name: name, bundleID: bundleID,
                             version: "1.0", build: "1", channel: channel,
                             identity: try FileIdentity.read(URL(fileURLWithPath: NSTemporaryDirectory())), sipProtected: sipProtected)
    }

    func testBuiltInMacOSAppsAreNotListedButAppStoreAndOtherInstallsAre() throws {
        let model = ApplicationWorkspaceModel()
        model.applications = [
            try app("Activity Monitor", "com.apple.ActivityMonitor", .system, at: "/System/Applications/Utilities"),
            try app("Xcode", "com.apple.dt.Xcode", .appStore),
            try app("Bitwarden", "com.bitwarden.desktop", .appStore),
            try app("Claude", "com.anthropic.claudefordesktop", .unknown),
            try app("Caffeine", "com.intelliscapesolutions.caffeine", .sparkle),
            // A SIP-protected Apple app outside /System (as Safari once lived in /Applications) is built in
            // too.
            try app("Safari", "com.apple.Safari", .unknown, sipProtected: true),
        ]
        XCTAssertEqual(model.listedApplications.map(\.name), ["Xcode", "Bitwarden", "Claude", "Caffeine"],
                       "an Apple app from the App Store can be removed, so it stays")
        XCTAssertEqual(model.filtered.map(\.name), ["Xcode", "Bitwarden", "Claude", "Caffeine"])
        model.search = "activity"
        XCTAssertTrue(model.filtered.isEmpty, "search doesn't bring hidden system apps back")
        model.search = ""
        model.selection = "/System/Applications/Utilities/Activity Monitor.app"
        XCTAssertNil(model.selectedApplication)
    }

    func testEmptyInventoryAndOnlySystemAppsListNothing() throws {
        let model = ApplicationWorkspaceModel()
        XCTAssertTrue(model.listedApplications.isEmpty)
        model.applications = [try app("Safari", "com.apple.Safari", .system, at: "/System/Applications")]
        XCTAssertTrue(model.listedApplications.isEmpty)
        XCTAssertEqual(model.applications.count, 1, "the full inventory is kept; leftover detection relies on it")
    }
}

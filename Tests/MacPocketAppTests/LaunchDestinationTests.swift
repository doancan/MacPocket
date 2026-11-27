import XCTest
@testable import MacPocketApp
import MacPocketTestSupport

@MainActor
final class LaunchDestinationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = temporaryDefaults()
    }


    func testFixedPageIgnoresTheRememberedOne() {
        defaults.set(PocketPage.power.rawValue, forKey: PocketPreferenceKey.launchPage)
        LaunchDestination(page: .tools, tool: .clipboard, networkTab: .wifi).remember(in: defaults)
        XCTAssertEqual(LaunchDestination.atLaunch(from: defaults), LaunchDestination(page: .power, tool: nil, networkTab: nil))
    }

    func testLastVisitedRestoresPageToolAndNetworkTab() {
        defaults.set(LaunchDestination.lastVisitedSetting, forKey: PocketPreferenceKey.launchPage)
        LaunchDestination(page: .tools, tool: .clipboard, networkTab: .wifi).remember(in: defaults)
        XCTAssertEqual(LaunchDestination.atLaunch(from: defaults), LaunchDestination(page: .tools, tool: .clipboard, networkTab: .wifi))
    }

    func testMissingRemovedOrUnknownValuesFallBackToOverview() {
        XCTAssertEqual(LaunchDestination.atLaunch(from: defaults).page, .overview)
        defaults.set(LaunchDestination.lastVisitedSetting, forKey: PocketPreferenceKey.launchPage)
        XCTAssertEqual(LaunchDestination.atLaunch(from: defaults).page, .overview, "nothing remembered yet")
        defaults.set("Pratik Araçlar", forKey: LaunchDestination.lastPageKey)   // a page that no longer exists
        defaults.set("Makrolar", forKey: LaunchDestination.lastToolKey)
        XCTAssertEqual(LaunchDestination.atLaunch(from: defaults), LaunchDestination(page: .overview, tool: nil, networkTab: nil))
        defaults.set("Pratik Araçlar", forKey: PocketPreferenceKey.launchPage)
        XCTAssertEqual(LaunchDestination.atLaunch(from: defaults).page, .overview)
    }

    func testToolIsOnlyRestoredOnTheToolsPage() {
        defaults.set(LaunchDestination.lastVisitedSetting, forKey: PocketPreferenceKey.launchPage)
        defaults.set(PocketPage.power.rawValue, forKey: LaunchDestination.lastPageKey)
        defaults.set(PocketTool.clipboard.rawValue, forKey: LaunchDestination.lastToolKey)
        XCTAssertNil(LaunchDestination.atLaunch(from: defaults).tool)
    }
}

import XCTest
@testable import MacPocketCore

final class PrivacyChangeTrackerTests: XCTestCase {
    private let zoom = PrivacyActivity(device: .microphone, bundleID: "us.zoom.xos", appName: "Zoom")
    private let camera = PrivacyActivity(device: .camera, bundleID: nil, appName: nil)
    private let start = Date(timeIntervalSince1970: 1_000)

    func testReportsOnlyActivitiesThatJustStarted() {
        var tracker = PrivacyChangeTracker()
        XCTAssertEqual(tracker.update(current: [zoom], ignoredApps: [], now: start), [zoom])
        XCTAssertEqual(tracker.update(current: [zoom], ignoredApps: [], now: start + 2), [], "still running: no repeat")
        XCTAssertEqual(tracker.update(current: [zoom, camera], ignoredApps: [], now: start + 4), [camera])
    }

    func testIgnoredAppsAreNotReportedButOthersAre() {
        var tracker = PrivacyChangeTracker()
        let other = PrivacyActivity(device: .microphone, bundleID: "com.other", appName: "Other")
        let started = tracker.update(current: [zoom, other], ignoredApps: ["us.zoom.xos"], now: start)
        XCTAssertEqual(started, [other])
    }

    func testIgnoringNeverHidesAnActivityWithoutAnOwner() {
        var tracker = PrivacyChangeTracker()
        XCTAssertEqual(tracker.update(current: [camera], ignoredApps: [""], now: start), [camera])
    }

    func testStartingAgainRightAwayIsSuppressedThenAllowedAfterTheCooldown() {
        var tracker = PrivacyChangeTracker(cooldown: 30)
        XCTAssertEqual(tracker.update(current: [zoom], ignoredApps: [], now: start), [zoom])
        _ = tracker.update(current: [], ignoredApps: [], now: start + 5)
        XCTAssertEqual(tracker.update(current: [zoom], ignoredApps: [], now: start + 10), [], "flapping within the cooldown")
        _ = tracker.update(current: [], ignoredApps: [], now: start + 12)
        XCTAssertEqual(tracker.update(current: [zoom], ignoredApps: [], now: start + 60), [zoom])
    }

    func testClockMovingBackwardsDoesNotSwallowAlerts() {
        var tracker = PrivacyChangeTracker(cooldown: 30)
        _ = tracker.update(current: [zoom], ignoredApps: [], now: start)
        _ = tracker.update(current: [], ignoredApps: [], now: start + 1)
        XCTAssertEqual(tracker.update(current: [zoom], ignoredApps: [], now: start - 500), [zoom])
    }

    func testActivityIdentityIgnoresTheDisplayName() {
        let renamed = PrivacyActivity(device: .microphone, bundleID: "us.zoom.xos", appName: "zoom.us")
        XCTAssertEqual(zoom, renamed)
        XCTAssertEqual(Set([zoom, renamed]).count, 1)
    }
}

final class PrivacyAppOwnerTests: XCTestCase {
    private let apps = [
        RunningAppInfo(pid: 10, bundleID: "com.google.Chrome", name: "Chrome"),
        RunningAppInfo(pid: 20, bundleID: "com.google", name: "Google Short"),
        RunningAppInfo(pid: 30, bundleID: "us.zoom.xos", name: "Zoom"),
    ]

    func testMatchesByProcessID() {
        XCTAssertEqual(PrivacyAppOwner.resolve(pid: 30, processBundleID: "anything", apps: apps)?.bundleID, "us.zoom.xos")
    }

    func testHelperProcessBelongsToTheAppWithTheLongestMatchingPrefix() {
        let owner = PrivacyAppOwner.resolve(pid: 999, processBundleID: "com.google.Chrome.helper.Renderer", apps: apps)
        XCTAssertEqual(owner?.bundleID, "com.google.Chrome")
    }

    func testSimilarlyNamedBundleIsNotAHelper() {
        let withoutShortPrefix = apps.filter { $0.bundleID != "com.google" }
        XCTAssertNil(PrivacyAppOwner.resolve(pid: 999, processBundleID: "com.google.Chromium", apps: withoutShortPrefix))
        XCTAssertNil(PrivacyAppOwner.resolve(pid: 999, processBundleID: "", apps: apps))
    }
}

final class PrivacySettingsTests: XCTestCase {
    func testDefaultsAreOffAndRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PrivacySettingsTests-\(UUID().uuidString)"))
        var settings = PrivacySettings.load(from: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.ignoredApps.isEmpty)
        settings.isEnabled = true
        settings.ignoredApps["us.zoom.xos"] = "Zoom"
        settings.save(to: defaults)
        XCTAssertEqual(PrivacySettings.load(from: defaults), settings)
    }

    func testCorruptStoredDataFallsBackToDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PrivacySettingsTests-\(UUID().uuidString)"))
        defaults.set(Data("not json".utf8), forKey: PrivacySettings.storageKey)
        XCTAssertEqual(PrivacySettings.load(from: defaults), PrivacySettings())
    }
}

import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class CleanupScanPlanTests: XCTestCase {
    private let targets = CleanupCatalog.targets(home: URL(fileURLWithPath: "/Users/test", isDirectory: true))

    private func defaults() -> UserDefaults {
        temporaryDefaults()
    }

    func testRecommendedScansSafeNonDeveloperLocationsAndTrash() throws {
        let ids = try XCTUnwrap(CleanupProfile.recommended.targetIDs(in: targets))
        XCTAssertEqual(ids, [.userCaches, .userLogs, .mailDownloads, .communicationCaches, .designCaches, .trash])
    }

    func testDeveloperAddsSafeDeveloperAndPackageLocationsButNotArchives() throws {
        let ids = try XCTUnwrap(CleanupProfile.developer.targetIDs(in: targets))
        let recommended = try XCTUnwrap(CleanupProfile.recommended.targetIDs(in: targets))
        XCTAssertTrue(recommended.isSubset(of: ids))
        XCTAssertTrue(ids.isSuperset(of: [.derivedData, .deviceSupport, .simulatorCaches, .editorCaches,
                                          .homebrew, .npm, .pip, .yarn, .cocoapods, .gradle]))
        XCTAssertFalse(ids.contains(.xcodeArchives))
        XCTAssertFalse(ids.contains(.oldDownloads))
        XCTAssertFalse(ids.contains(.phoneBackups))
    }

    func testAllCoversEveryLocationAndCustomHasNoFixedSet() {
        XCTAssertEqual(CleanupProfile.all.targetIDs(in: targets), Set(CleanupTargetID.allCases))
        XCTAssertNil(CleanupProfile.custom.targetIDs(in: targets))
    }

    func testProfileIsDerivedFromSelectionAndManualEditBecomesCustom() {
        var selection = CleanupScanSelection(profile: .developer, targets: targets)
        XCTAssertEqual(selection.profile(in: targets), .developer)
        selection.set(.npm, included: false)
        XCTAssertEqual(selection.profile(in: targets), .custom)
        selection.set(.npm, included: true)
        XCTAssertEqual(selection.profile(in: targets), .developer)
        selection.apply(.all, targets: targets)
        XCTAssertEqual(selection.profile(in: targets), .all)
        selection.apply(.custom, targets: targets)
        XCTAssertEqual(selection.profile(in: targets), .all, "Choosing Özel keeps the current locations")
    }

    func testGroupToggleIncludesAndExcludesEveryMember() {
        var selection = CleanupScanSelection(ids: [])
        selection.set(.downloads, included: true, targets: targets)
        XCTAssertEqual(selection.ids, [.oldDownloads, .installers])
        selection.set(.downloads, included: false, targets: targets)
        XCTAssertTrue(selection.ids.isEmpty)
    }

    func testFirstLaunchStartsRecommendedAndSelectionPersists() {
        let defaults = defaults()
        let first = CleanupScanSelection.load(from: defaults, targets: targets)
        XCTAssertEqual(first.profile(in: targets), .recommended)

        var edited = first
        edited.set(.derivedData, included: true)
        edited.save(to: defaults)
        XCTAssertEqual(CleanupScanSelection.load(from: defaults, targets: targets), edited)

        CleanupScanSelection(ids: []).save(to: defaults)
        XCTAssertTrue(CleanupScanSelection.load(from: defaults, targets: targets).ids.isEmpty, "An empty choice is remembered")
    }

    func testUnknownStoredLocationsAreDropped() {
        let defaults = defaults()
        defaults.set(["userLogs", "removedLocation"], forKey: CleanupScanSelection.storageKey)
        XCTAssertEqual(CleanupScanSelection.load(from: defaults, targets: targets).ids, [.userLogs])
    }

    func testLastScanSizesKeepUnscannedLocationsAndForgetMissingOnes() throws {
        let caches = try XCTUnwrap(targets.first { $0.id == .userCaches })
        let logs = try XCTUnwrap(targets.first { $0.id == .userLogs })
        var sizes = CleanupLastScanSizes(bytes: [.npm: 500, .userLogs: 70])
        sizes.record(CleanupReport(scannedAt: Date(), duration: 1, targets: [
            CleanupTargetReport(target: caches, items: [], state: .ready, complete: true),
            CleanupTargetReport(target: logs, items: [], state: .missing, complete: true),
        ], limitReached: false))
        XCTAssertEqual(sizes.bytes, [.npm: 500, .userCaches: 0])
        XCTAssertEqual(sizes.total(of: [.npm, .userCaches, .gradle]), 500)
        XCTAssertNil(sizes.total(of: [.gradle]))

        let defaults = defaults()
        sizes.save(to: defaults)
        XCTAssertEqual(CleanupLastScanSizes.load(from: defaults), sizes)
    }
}

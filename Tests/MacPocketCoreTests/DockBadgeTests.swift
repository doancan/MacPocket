import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class DockBadgeTests: XCTestCase {
    func testNumericZeroAndTextLabelsRemainApplicationLabels() throws {
        for label in ["0","42","!","99+","تحديث","🙂"] {
            let badge = try XCTUnwrap(DockApplicationBadge(label))
            XCTAssertEqual(badge.label,label)
            XCTAssertTrue(badge.localizedDescription.contains(label))
        }
    }
    func testEmptyWhitespaceControlAndOversizedLabelsAreNotBadges() {
        for label: String? in [nil,""," \n\t","\u{0000}","a\u{202E}b",String(repeating: "a",count: 257)] { XCTAssertNil(DockApplicationBadge(label)) }
        XCTAssertEqual(DockApplicationBadge("  12\n ")?.label,"12")
    }
    func testLongLabelsUseGraphemeSafeCompactTextAndPreserveFullDescription() throws {
        let value = try XCTUnwrap(DockApplicationBadge("1234567890123456789012345"))
        XCTAssertEqual(value.displayText,"123…")
        XCTAssertTrue(value.localizedDescription.contains(value.label))
        let emoji = try XCTUnwrap(DockApplicationBadge("👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦"))
        XCTAssertEqual(emoji.displayText.count,4)
    }
    func testTargetRequiresKnownProcessLaunchAndLocalApplicationURL() {
        let date = Date(timeIntervalSince1970: 1),url = URL(fileURLWithPath: "/Applications/A.app")
        XCTAssertNil(DockBadgeTarget(processID: 0,launchedAt: date,applicationURL: url))
        XCTAssertNil(DockBadgeTarget(processID: 1,launchedAt: nil,applicationURL: url))
        XCTAssertNil(DockBadgeTarget(processID: 1,launchedAt: Date(timeIntervalSince1970: .infinity),applicationURL: url))
        XCTAssertNil(DockBadgeTarget(processID: 1,launchedAt: date,applicationURL: URL(string: "https://a.test/A.app")))
        XCTAssertNil(DockBadgeTarget(processID: 1,launchedAt: date,applicationURL: URL(fileURLWithPath: "/Applications/A")))
        XCTAssertNotNil(DockBadgeTarget(processID: 1,launchedAt: date,applicationURL: url))
    }
    func testProcessReuseAndDifferentInstallationsHaveSeparateKeys() throws {
        let url = URL(fileURLWithPath: "/Applications/A.app"),date = Date(timeIntervalSince1970: 1)
        let first = try XCTUnwrap(DockBadgeTarget(processID: 1,launchedAt: date,applicationURL: url))
        XCTAssertNotEqual(first,DockBadgeTarget(processID: 1,launchedAt: date.addingTimeInterval(1),applicationURL: url))
        XCTAssertNotEqual(first,DockBadgeTarget(processID: 2,launchedAt: date,applicationURL: url))
        XCTAssertNotEqual(first,DockBadgeTarget(processID: 1,launchedAt: date,applicationURL: URL(fileURLWithPath: "/Volumes/B/A.app")))
    }
    func testMappingUsesExactStandardizedURLsInsteadOfNameOrPrefix() {
        let url = URL(fileURLWithPath: "/Applications/A.app"),other = URL(fileURLWithPath: "/Volumes/B/A.app")
        let result = DockBadgeMapping.labels([(url,"2"),(other,"!")])
        XCTAssertEqual(result[url]?.label,"2")
        XCTAssertEqual(result[other]?.label,"!")
        XCTAssertNil(result[URL(fileURLWithPath: "/Applications/A.app.copy.app")])
        XCTAssertEqual(DockBadgeMapping.labels([(URL(fileURLWithPath: "/Applications/../Applications/A.app"),"2")])[url]?.label,"2")
    }
    func testConflictingDuplicateTilesIncludingAbsentLabelAreSuppressed() {
        let url = URL(fileURLWithPath: "/Applications/A.app")
        XCTAssertTrue(DockBadgeMapping.labels([(url,"2"),(url,"3")]).isEmpty)
        XCTAssertTrue(DockBadgeMapping.labels([(url,"2"),(url,nil)]).isEmpty)
        XCTAssertEqual(DockBadgeMapping.labels([(url,"2"),(url,"2")])[url]?.label,"2")
    }
    func testMissingBadgesDoNotInventZeroOrRetainPriorValue() {
        let url = URL(fileURLWithPath: "/Applications/A.app")
        XCTAssertTrue(DockBadgeMapping.labels([(url,nil)]).isEmpty)
        XCTAssertTrue(DockBadgeMapping.labels([]).isEmpty)
    }
    func testBadgePreferenceDefaultsOnWithoutWritingAndCanBeDisabled() {
        let d = temporaryDefaults()
        XCTAssertTrue(SwitcherPresentation.load(d).showBadges)
        XCTAssertNil(d.object(forKey: "switcher.showBadges"))
        d.set(false,forKey: "switcher.showBadges")
        XCTAssertFalse(SwitcherPresentation.load(d).showBadges)
    }
    func testPerShortcutBadgeChoiceFollowsGlobalOrOverridesIndependently() throws {
        var global = SwitcherPresentation(),override = SwitcherPresentationOverrides()
        XCTAssertTrue(override.resolve(over: global).showBadges)
        global.showBadges = false
        XCTAssertFalse(override.resolve(over: global).showBadges)
        override.showBadges = true
        XCTAssertTrue(override.resolve(over: global).showBadges)
        let data = try JSONEncoder().encode(override),decoded = try JSONDecoder().decode(SwitcherPresentationOverrides.self,from: data)
        XCTAssertEqual(decoded.showBadges,true)
        XCTAssertNil(try JSONDecoder().decode(SwitcherPresentationOverrides.self,from: Data("{}".utf8)).showBadges)
    }
    func testRemoteFileURLDoesNotBecomeALocalApplicationTarget() {
        XCTAssertNil(DockBadgeTarget.applicationURL(URL(string: "file://server/Applications/A.app")!))
    }
    func testLiveReaderDoesNotReadForEmptyTargetsOrAnAlreadyCancelledTask() async {
        let reader = DockApplicationBadgeReader()
        let empty = await reader.badges(for: [])
        XCTAssertTrue(empty.isEmpty)
        let task = Task { () -> [DockBadgeTarget:DockApplicationBadge] in
            withUnsafeCurrentTask { $0?.cancel() }
            let target = DockBadgeTarget(processID: 1,launchedAt: Date(timeIntervalSince1970: 1),applicationURL: URL(fileURLWithPath: "/Applications/A.app"))!
            return await reader.badges(for: [target])
        }
        let result = await task.value
        XCTAssertTrue(result.isEmpty)
    }
}

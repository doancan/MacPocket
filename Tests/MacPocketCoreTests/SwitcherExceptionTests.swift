import XCTest
@testable import MacPocketCore

final class SwitcherExceptionTests: XCTestCase {
    private func window(_ title: String = "Report", real: Bool = true, bundle: String? = "com.example.Editor") -> SwitchableWindow {
        .init(id: title, processID: 1, application: "Editor", title: title,
              applicationURL: URL(fileURLWithPath: "/Applications/Editor.app"), minimized: true, hidden: true,
              fullScreen: false, frontmost: true, windowAccessible: false, canClose: false, canMinimize: false, canFullScreen: false,
              launchedAt: nil, lastFocusedAt: nil, windowID: real ? 1 : nil, bundleIdentifier: bundle)
    }
    private func defaults() -> UserDefaults {
        let name = "SwitcherExceptionTests." + UUID().uuidString
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return value
    }
    func testLegacyListsAreReadWithoutWritesAndKeepExactMatches() {
        let d = defaults()
        d.set("/Applications/Editor.app\n/Applications/Editor.app", forKey: "switcher.excludedPaths")
        d.set("com.example.Editor", forKey: "switcher.disabledApps")
        let loaded = SwitcherExceptionStore.load(d)
        XCTAssertNil(loaded.error); XCTAssertEqual(loaded.rules.count, 2); XCTAssertNil(d.data(forKey: SwitcherExceptionStore.key))
        XCTAssertEqual(loaded.rules, SwitcherExceptionStore.load(d).rules, "Legacy IDs must remain stable before migration")
        XCTAssertTrue(loaded.rules[0].hides(window()))
        XCTAssertFalse(loaded.rules[1].disablesShortcuts(bundleIdentifier: "com.example.Editor.Helper", applicationPath: nil, fullscreen: true))
        XCTAssertTrue(loaded.rules[1].disablesShortcuts(bundleIdentifier: "com.example.Editor", applicationPath: nil, fullscreen: nil))
    }
    func testThreeTargetKindsDoNotConfuseExactIdentityWithPrefix() {
        for (kind, value, expected) in [(SwitcherExceptionTarget.applicationPath,"/Applications/Editor.app",true),
                                      (.applicationPath,"/Applications/Other.app",false),
                                      (.bundleIdentifier,"com.example",false),(.bundleIdentifier,"com.example.Editor",true),
                                      (.bundlePrefix,"com.example.",true),(.bundlePrefix,"org.example",false)] {
            XCTAssertEqual(SwitcherExceptionRule(target: kind, value: value, visibility: .alwaysHide).hides(window()), expected)
        }
        XCTAssertFalse(SwitcherExceptionRule(target: .bundlePrefix, value: "", visibility: .alwaysHide).hides(window()))
        XCTAssertFalse(SwitcherExceptionRule(target: .bundlePrefix, value: "com.", visibility: .alwaysHide).hides(window(bundle: nil)))
    }
    func testDisabledRulesAndIndependentPoliciesDoNotHideOrSuspendAccidentally() {
        let rule = SwitcherExceptionRule(enabled: false, target: .bundlePrefix, value: "com.example", visibility: .alwaysHide, shortcuts: .alwaysDisable)
        XCTAssertFalse(rule.hides(window()))
        XCTAssertFalse(rule.disablesShortcuts(bundleIdentifier: "com.example.Editor", applicationPath: nil, fullscreen: true))
        let shortcutOnly = SwitcherExceptionRule(target: .bundleIdentifier, value: "com.example.Editor", shortcuts: .alwaysDisable)
        XCTAssertFalse(shortcutOnly.hides(window()))
        let visibilityOnly = SwitcherExceptionRule(target: .bundleIdentifier, value: "com.example.Editor", visibility: .alwaysHide)
        XCTAssertFalse(visibilityOnly.disablesShortcuts(bundleIdentifier: "com.example.Editor", applicationPath: nil, fullscreen: true))
    }
    func testWindowlessRuleKeepsMinimizedAndHiddenPhysicalWindowsAndVerifiedNativeTabs() {
        let rule = SwitcherExceptionRule(target: .bundlePrefix, value: "com.example", visibility: .windowless)
        XCTAssertTrue(rule.hides(window(real: false)))
        XCTAssertFalse(rule.hides(window()))
        var tab = window(real: false)
        tab.nativeTab = .init(groupID: "g", controlID: "c", ordinal: 2, count: 2, selected: false)
        XCTAssertFalse(rule.hides(tab), "A background native tab without a CGWindowID is still an open window")
    }
    func testTitlePatternsAreLiteralCaseSensitiveAnyMatchAndNeverApplyToWindowlessAppLabel() {
        let rule = SwitcherExceptionRule(target: .bundlePrefix, value: "com.example", visibility: .titleContains,
                                        titlePatterns: ["", "Private", "[Draft]", "İş"])
        XCTAssertTrue(rule.hides(window("Document [Draft]"))); XCTAssertTrue(rule.hides(window("Private Plan")))
        XCTAssertTrue(rule.hides(window("İş notları"))); XCTAssertFalse(rule.hides(window("private Plan")))
        XCTAssertFalse(rule.hides(window("Report"))); XCTAssertFalse(rule.hides(window("Private", real: false)))
    }
    func testFullscreenShortcutRuleFailsOpenForUnknownAndOnlyMatchesItsApplication() {
        let rule = SwitcherExceptionRule(target: .bundlePrefix, value: "com.example", shortcuts: .fullscreen)
        for flag: Bool? in [nil,false,true] {
            XCTAssertEqual(rule.disablesShortcuts(bundleIdentifier: "com.example.Editor", applicationPath: nil, fullscreen: flag), flag == true)
        }
        XCTAssertFalse(rule.disablesShortcuts(bundleIdentifier: "org.example.Editor", applicationPath: nil, fullscreen: true))
    }
    func testRulesComposeBeforeGroupingAndSearchWithoutDiscardingAnEligibleSibling() {
        let input = [window("Private"),window("Report")]
        let rule = SwitcherExceptionRule(target: .bundlePrefix, value: "com.example", visibility: .titleContains, titlePatterns: ["Private"])
        var filter = WindowListFilter(); filter.grouping = .onePerApplication
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, exceptions: [rule]).map(\.title), ["Report"])
        filter.applicationScope = .frontmost
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter, context: .init(foregroundPID: 1), exceptions: [rule]).map(\.title), ["Report"])
        XCTAssertTrue(WindowFiltering.apply(input, search: "Private", exceptions: [rule]).isEmpty)
    }
    func testSaveRoundTripsPoliciesAndKeepsOnlyExactUnconditionalSubsetForOlderBuilds() {
        let d = defaults()
        let rules: [SwitcherExceptionRule] = [
            .init(target: .applicationPath, value: "/Applications/Editor.app", visibility: .alwaysHide),
            .init(target: .bundleIdentifier, value: "com.example.Editor", shortcuts: .alwaysDisable),
            .init(target: .bundlePrefix, value: "com.example", visibility: .titleContains, titlePatterns: ["Secret"], shortcuts: .fullscreen),
            .init(enabled: false, target: .applicationPath, value: "/Applications/Other.app", visibility: .alwaysHide)]
        XCTAssertTrue(SwitcherExceptionStore.save(rules,d)); XCTAssertEqual(SwitcherExceptionStore.load(d).rules,rules)
        XCTAssertEqual(d.string(forKey: "switcher.excludedPaths"), "/Applications/Editor.app")
        XCTAssertEqual(d.string(forKey: "switcher.disabledApps"), "com.example.Editor")
        XCTAssertTrue(SwitcherExceptionStore.save([],d)); XCTAssertTrue(SwitcherExceptionStore.load(d).rules.isEmpty)
        XCTAssertEqual(d.string(forKey: "switcher.excludedPaths"), "")
    }
    func testMalformedOrFutureDataRemainsUntouchedAndUsesLegacySubset() {
        for data in [Data("broken".utf8),Data(#"[{"id":"x","enabled":true,"target":"future","value":"com.example","visibility":"show","titlePatterns":[],"shortcuts":"alwaysDisable"}]"#.utf8)] {
            let d = defaults(); d.set("com.example.Editor", forKey: "switcher.disabledApps");d.set(data, forKey: SwitcherExceptionStore.key)
            let result = SwitcherExceptionStore.load(d)
            XCTAssertNotNil(result.error); XCTAssertEqual(result.rules.count,1)
            XCTAssertEqual(d.data(forKey: SwitcherExceptionStore.key),data)
        }
    }
    func testNonDataPreferenceRecordIsReportedAndPreserved() {
        let d = defaults();d.set("unreadable record",forKey: SwitcherExceptionStore.key)
        XCTAssertNotNil(SwitcherExceptionStore.load(d).error)
        XCTAssertEqual(d.string(forKey: SwitcherExceptionStore.key),"unreadable record")
        XCTAssertNil(SwitcherExceptionRule(target: .applicationPath,value: "/Applications/Example.App",visibility: .alwaysHide).validationMessage)
    }
    func testInvalidDraftsAndDuplicateIDsCannotOverwriteWorkingRules() {
        let d = defaults(), valid = SwitcherExceptionRule(target: .bundlePrefix,value: "com.example",visibility: .alwaysHide)
        XCTAssertTrue(SwitcherExceptionStore.save([valid],d));let before = d.data(forKey: SwitcherExceptionStore.key)
        var invalid = valid;invalid.value = ""
        XCTAssertFalse(SwitcherExceptionStore.save([invalid],d));XCTAssertFalse(SwitcherExceptionStore.save([valid,valid],d))
        XCTAssertEqual(d.data(forKey: SwitcherExceptionStore.key),before)
        invalid = valid; invalid.visibility = .titleContains;invalid.titlePatterns = [""]
        XCTAssertNotNil(invalid.validationMessage)
        invalid.titlePatterns = Array(repeating: "title",count: 33);XCTAssertNotNil(invalid.validationMessage)
        invalid.titlePatterns = [String(repeating: "x",count: 513)];XCTAssertNotNil(invalid.validationMessage)
    }
    func testRuleLimitRejectsOversizedSaveWithoutTruncation() {
        let d = defaults()
        let rules = (0..<SwitcherExceptionStore.maximumCount).map { SwitcherExceptionRule(target: .bundleIdentifier,value: "com.example.App\($0)",visibility: .alwaysHide) }
        XCTAssertTrue(SwitcherExceptionStore.save(rules,d))
        XCTAssertFalse(SwitcherExceptionStore.save(rules + [.init(target: .bundlePrefix,value: "com.",visibility: .alwaysHide)],d))
        XCTAssertEqual(SwitcherExceptionStore.load(d).rules,rules)
    }
}

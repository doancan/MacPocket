import Foundation
import Testing
@testable import MacPocketCore

@Suite struct SystemDataAutomationTests {
    private static let gb: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(freeGB: Int64, totalGB: Int64 = 500, safeGB: Int64 = 3, at date: Date? = nil) -> SystemDataReport {
        let item = SystemDataItem(id: "cache", group: .packages, title: "c", detail: "", safety: .safe, regeneration: .rebuildsLocally,
                                  paths: ["/x"], sizeBytes: safeGB * Self.gb, action: .removeContents)
        return SystemDataReport(scannedAt: date ?? now, items: [item], totalBytes: totalGB * Self.gb, freeBytes: freeGB * Self.gb, purgeableBytes: 0, complete: true)
    }

    private func settings(_ configure: (inout SystemDataAutomationSettings) -> Void) -> SystemDataAutomationSettings {
        var value = SystemDataAutomationSettings(); configure(&value); return value
    }

    @Test func everythingIsOffByDefaultAndPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        #expect(!SystemDataAutomationSettings.load(from: defaults).needsBackgroundScan)
        let saved = settings { $0.autoClean = true; $0.lowSpaceGigabytes = 20 }
        saved.save(to: defaults)
        #expect(SystemDataAutomationSettings.load(from: defaults) == saved)
        var state = SystemDataAutomationState(); state.lowSpaceFired = true; state.save(to: defaults)
        #expect(SystemDataAutomationState.load(from: defaults).lowSpaceFired)
    }

    @Test func aScanIsDueDailyOnlyWhenSomethingNeedsIt() {
        var state = SystemDataAutomationState()
        #expect(!SystemDataAutomationPolicy.isScanDue(SystemDataAutomationSettings(), state: state, now: now))
        let on = settings { $0.growthAlert = true }
        #expect(SystemDataAutomationPolicy.isScanDue(on, state: state, now: now))
        state.lastScan = now.addingTimeInterval(-3_600)
        #expect(!SystemDataAutomationPolicy.isScanDue(on, state: state, now: now))
        state.lastScan = now.addingTimeInterval(-86_400)
        #expect(SystemDataAutomationPolicy.isScanDue(on, state: state, now: now))
    }

    @Test func lowSpaceFiresOnTheWayDownAndStaysQuietUntilItRecovers() {
        let on = settings { $0.lowSpaceAlert = true; $0.lowSpaceGigabytes = 10 }
        var state = SystemDataAutomationState()
        let low = SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 8), history: .init(), watching: false, now: now)
        #expect(low == [.lowSpace(freeBytes: 8 * Self.gb, safeBytes: 3 * Self.gb)])
        #expect(SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 7), history: .init(), watching: false, now: now).isEmpty)
        _ = SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 30), history: .init(), watching: false, now: now)
        #expect(!state.lowSpaceFired)
        #expect(SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 9), history: .init(), watching: false, now: now).count == 1)
    }

    @Test func alertsAndCleanNeverRunForAScanTheUserIsWatching() {
        let all = settings { $0.lowSpaceAlert = true; $0.growthAlert = true; $0.weeklySummary = true; $0.autoClean = true }
        var state = SystemDataAutomationState()
        #expect(SystemDataAutomationPolicy.decide(settings: all, state: &state, report: report(freeGB: 1), history: .init(), watching: true, now: now).isEmpty)
        #expect(state.lastScan == now)
    }

    @Test func autoCleanRunsWeeklyAndOnlyWhenEnabled() {
        var state = SystemDataAutomationState()
        let on = settings { $0.autoClean = true }
        #expect(SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 100), history: .init(), watching: false, now: now) == [.autoClean])
        state.lastAutoClean = now.addingTimeInterval(-2 * 86_400)
        #expect(SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 100), history: .init(), watching: false, now: now).isEmpty)
        #expect(SystemDataAutomationPolicy.decide(settings: SystemDataAutomationSettings(), state: &state, report: report(freeGB: 100), history: .init(), watching: false, now: now.addingTimeInterval(9 * 86_400)).isEmpty)
    }

    @Test func weeklySummaryNeedsMoreThanTwoGigabytesOfGrowth() {
        var history = SystemDataHistory()
        history.record(report(freeGB: 100, safeGB: 10, at: now.addingTimeInterval(-8 * 86_400)))
        let on = settings { $0.weeklySummary = true }
        var state = SystemDataAutomationState()
        let grown = SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 100, safeGB: 15), history: history, watching: false, now: now)
        #expect(grown == [.weeklySummary(changeBytes: 5 * Self.gb, topGroup: .packages)])
        #expect(state.lastWeeklySummary == now)
        var quiet = SystemDataAutomationState()
        #expect(SystemDataAutomationPolicy.decide(settings: on, state: &quiet, report: report(freeGB: 100, safeGB: 11), history: history, watching: false, now: now).isEmpty)
        #expect(SystemDataAutomationPolicy.decide(settings: on, state: &state, report: report(freeGB: 100, safeGB: 15), history: history, watching: false, now: now.addingTimeInterval(86_400)).isEmpty)
    }
}

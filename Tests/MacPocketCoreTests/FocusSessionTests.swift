import XCTest
@testable import MacPocketCore

final class FocusPlannerTests: XCTestCase {
    private let environment = FocusEnvironment(desktopIconsVisible: true, quitGuardOff: true,
                                               displayLevels: [1: 0.9, 2: 0.8, 3: 0.2], activeDisplay: 1)

    func testStartsEverythingThatIsntAlreadyInPlace() {
        var settings = FocusSettings()
        let macro = UUID()
        settings.startMacro = macro
        XCTAssertEqual(FocusPlanner.start(settings, environment: environment), [
            .keepAwake(minutes: 50),
            .hideDesktopIcons,
            .dimDisplay(2, to: 0.35, from: 0.8),
            .guardQuit,
            .runMacro(macro),
        ])
    }

    func testNeverTouchesTheActiveDisplayOrOnesAlreadyDimmer() {
        let changes = FocusPlanner.start(FocusSettings(), environment: environment)
        XCTAssertFalse(changes.contains { if case .dimDisplay(1, _, _) = $0 { true } else { false } }, "the display in use")
        XCTAssertFalse(changes.contains { if case .dimDisplay(3, _, _) = $0 { true } else { false } }, "already below the level")
    }

    func testSkipsWhatTheUserAlreadySetSoEndingCantUndoIt() {
        let calm = FocusEnvironment(desktopIconsVisible: false, quitGuardOff: false, displayLevels: [:], activeDisplay: nil)
        XCTAssertEqual(FocusPlanner.start(FocusSettings(), environment: calm), [.keepAwake(minutes: 50)])
    }

    func testOptionsOff() {
        var settings = FocusSettings()
        settings.keepAwake = false
        settings.hideDesktopIcons = false
        settings.dimOtherDisplays = nil
        settings.guardQuit = false
        XCTAssertEqual(FocusPlanner.start(settings, environment: environment), [])
    }
}

final class FocusHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func record(dayOffset: Int, minutes: Int, planned: Int = 25) -> FocusSessionRecord {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10))!
        let start = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        return FocusSessionRecord(start: start, end: start.addingTimeInterval(Double(minutes) * 60), plannedMinutes: planned)
    }

    func testMinutesTodayAndStreak() {
        var history = FocusHistory()
        history.add(record(dayOffset: -3, minutes: 30))
        history.add(record(dayOffset: -1, minutes: 25))
        history.add(record(dayOffset: 0, minutes: 50, planned: 50))
        history.add(record(dayOffset: 0, minutes: 10)) // stopped early
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 18))!
        XCTAssertEqual(history.minutes(on: today, calendar: calendar), 60)
        XCTAssertEqual(history.streak(until: today, calendar: calendar), 2, "today and yesterday; the gap two days ago ends it")
        XCTAssertFalse(record(dayOffset: 0, minutes: 10).completed)
    }

    func testStreakCountsFromYesterdayWhenTodayIsEmpty() {
        var history = FocusHistory()
        history.add(record(dayOffset: -1, minutes: 25))
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9))!
        XCTAssertEqual(history.streak(until: today, calendar: calendar), 1)
    }
}

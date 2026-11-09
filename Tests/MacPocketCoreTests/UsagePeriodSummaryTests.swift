import XCTest
@testable import MacPocketCore

final class UsagePeriodSummaryTests: XCTestCase {
    func testEmptyAndInactivePeriodsKeepFiniteAverageAndTwentyFourHours() {
        for days: [UsageDay] in [[], [UsageDay()], [UsageDay(), UsageDay()]] {
            let summary = UsagePeriodSummary(days)
            XCTAssertEqual(summary.total, 0); XCTAssertEqual(summary.average, 0)
            XCTAssertEqual(summary.activeDayCount, 1); XCTAssertEqual(summary.maximumDayTotal, 0)
            XCTAssertEqual(summary.hourTotals, Array(repeating: 0, count: 24))
            XCTAssertEqual(summary.dayTotals, Array(repeating: 0, count: days.count))
        }
    }

    func testCardsAndChartReceiveSameTotalsAsPreviousCalculations() {
        let days = [UsageDay(apps: ["a": 60, "b": 120], hours: [9: 180]), UsageDay(),
                    UsageDay(apps: ["a": 90.5, "b": 29.5], hours: [9: 30, 23: 90])]
        let summary = UsagePeriodSummary(days)
        XCTAssertEqual(summary.dayTotals, [180, 0, 120])
        XCTAssertEqual(summary.total, days.reduce(0) { $0 + $1.total })
        XCTAssertEqual(summary.activeDayCount, max(1, days.filter { $0.total > 0 }.count))
        XCTAssertEqual(summary.average, 150)
        XCTAssertEqual(summary.maximumDayTotal, days.map(\.total).max())
        XCTAssertEqual(summary.hourTotals, UsageLedger.hourTotals(days))
        XCTAssertEqual(summary.hourTotals[9], 210); XCTAssertEqual(summary.hourTotals[23], 90)
    }

    func testSummaryIsRebuiltFromFreshDataWithoutChangingPreviousSnapshot() {
        var days = [UsageDay(apps: ["a": 10], hours: [8: 10])]
        let previous = UsagePeriodSummary(days)
        days[0].apps["a"] = 30; days[0].hours[8] = 30
        let latest = UsagePeriodSummary(days)
        XCTAssertEqual(previous.total, 10); XCTAssertEqual(previous.hourTotals[8], 10)
        XCTAssertEqual(latest.total, 30); XCTAssertEqual(latest.hourTotals[8], 30)
        XCTAssertNotEqual(previous, latest)
    }

    func testMonthSummaryPreservesOrderingFractionalValuesAndAverageDenominator() {
        let days = (0..<30).map { day in
            UsageDay(apps: day.isMultiple(of: 3) ? [:] : ["a": Double(day) + 0.25, "b": 0.5], hours: [day % 24: Double(day)])
        }
        let summary = UsagePeriodSummary(days)
        let totals = days.map(\.total)
        XCTAssertEqual(summary.dayTotals, totals)
        XCTAssertEqual(summary.total, totals.reduce(0, +))
        XCTAssertEqual(summary.average, totals.reduce(0, +) / Double(max(1, days.filter { $0.total > 0 }.count)))
        XCTAssertEqual(summary.hourTotals, UsageLedger.hourTotals(days))
    }
}

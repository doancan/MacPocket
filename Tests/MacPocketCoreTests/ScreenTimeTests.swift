import XCTest
@testable import MacPocketCore

final class ScreenTimeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testIntervalsSplitAcrossHoursAndMidnight() {
        var ledger = UsageLedger()
        ledger.record(app: "com.apple.Safari", name: "Safari", from: date(3, 23, 30), to: date(4, 0, 45), calendar: calendar)
        let yesterday = ledger.day(date(3, 12), calendar: calendar), today = ledger.day(date(4, 12), calendar: calendar)
        XCTAssertEqual(yesterday.apps["com.apple.Safari"], 30 * 60)
        XCTAssertEqual(yesterday.hours[23], 30 * 60)
        XCTAssertEqual(today.apps["com.apple.Safari"], 45 * 60)
        XCTAssertEqual(today.hours[0], 45 * 60)
        XCTAssertEqual(ledger.names["com.apple.Safari"], "Safari")
    }

    func testEmptyOrBackwardIntervalsAreIgnored() {
        var ledger = UsageLedger()
        ledger.record(app: "a", name: "A", from: date(4, 10), to: date(4, 10), calendar: calendar)
        ledger.record(app: "a", name: "A", from: date(4, 11), to: date(4, 10), calendar: calendar)
        ledger.record(app: "", name: "", from: date(4, 10), to: date(4, 11), calendar: calendar)
        XCTAssertTrue(ledger.days.isEmpty)
    }

    func testTotalsRangesAndHours() {
        var ledger = UsageLedger()
        ledger.record(app: "xcode", name: "Xcode", from: date(4, 9), to: date(4, 11), calendar: calendar)
        ledger.record(app: "safari", name: "Safari", from: date(4, 11), to: date(4, 11, 30), calendar: calendar)
        ledger.record(app: "safari", name: "Safari", from: date(2, 20), to: date(2, 23), calendar: calendar)
        ledger.countSwitch(at: date(4, 11), calendar: calendar)

        let week = ledger.range(endingAt: date(4, 18), count: 7, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.day.total, 2.5 * 3600)
        XCTAssertEqual(week.last?.day.switches, 1)
        let totals = UsageLedger.appTotals(week.map(\.day), names: ledger.names)
        XCTAssertEqual(totals.map(\.app), ["safari", "xcode"], "3.5 h Safari over the week beats 2 h Xcode")
        XCTAssertEqual(totals.first?.seconds, 3.5 * 3600)
        let hours = UsageLedger.hourTotals([ledger.day(date(4, 1), calendar: calendar)])
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[9], 3600)
        XCTAssertEqual(hours[11], 1800)
    }

    func testPruneKeepsThirtyDaysAndRemoveAppKeepsTotalsConsistent() {
        var ledger = UsageLedger()
        ledger.record(app: "old", name: "Old", from: date(1, 10), to: date(1, 11), calendar: calendar)
        ledger.record(app: "new", name: "New", from: date(4, 10), to: date(4, 11), calendar: calendar)
        ledger.record(app: "other", name: "Other", from: date(4, 10, 0), to: date(4, 10, 30), calendar: calendar)
        ledger.prune(keepingDays: 2, now: date(4, 12), calendar: calendar)
        XCTAssertEqual(Set(ledger.days.keys), ["2026-11-04"])
        XCTAssertNil(ledger.names["old"])

        ledger.remove(app: "new")
        let day = ledger.day(date(4, 1), calendar: calendar)
        XCTAssertNil(day.apps["new"])
        XCTAssertEqual(day.hours.values.reduce(0, +), day.total, accuracy: 0.001)
        XCTAssertNil(ledger.names["new"])
    }

    func testDurationText() {
        XCTAssertEqual(UsageFormatter.duration(0), "0 dk")
        XCTAssertEqual(UsageFormatter.duration(30), "< 1 dk")
        XCTAssertEqual(UsageFormatter.duration(45 * 60), "45 dk")
        XCTAssertEqual(UsageFormatter.duration(2 * 3600), "2 sa")
        XCTAssertEqual(UsageFormatter.duration(2 * 3600 + 5 * 60 + 59), "2 sa 5 dk")
    }

    func testStoreRoundTripsAndToleratesACorruptFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screen-time-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageStore(url: url)
        var ledger = UsageLedger()
        ledger.record(app: "a", name: "A", from: date(4, 10), to: date(4, 11), calendar: calendar)
        try await store.save(ledger)
        let loaded = await store.load()
        XCTAssertEqual(loaded, ledger)
        try Data("not json".utf8).write(to: url)
        let fallback = await store.load()
        XCTAssertEqual(fallback, UsageLedger())
    }
}

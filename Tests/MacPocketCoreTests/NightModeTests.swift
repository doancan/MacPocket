import XCTest
@testable import MacPocketCore

final class NightModeTests: XCTestCase {
    private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)
    private let tromso = Coordinate(latitude: 69.6492, longitude: 18.9553)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func minutes(_ date: Date, _ zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    private func assertNormal(_ day: SolarDay, sunrise: Int, sunset: Int, zone: TimeZone, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .normal(rise, set) = day else { return XCTFail("expected .normal, got \(day)", file: file, line: line) }
        XCTAssertEqual(Double(minutes(rise, zone)), Double(sunrise), accuracy: 2, file: file, line: line)
        XCTAssertEqual(Double(minutes(set, zone)), Double(sunset), accuracy: 2, file: file, line: line)
    }

    func testIstanbulSummerSolstice() {
        let zone = TimeZone(identifier: "Europe/Istanbul")!
        let day = SolarCalculator.day(containing: date(2026, 6, 21, zone), at: istanbul, timeZone: zone)
        assertNormal(day, sunrise: 5 * 60 + 32, sunset: 20 * 60 + 39, zone: zone)
    }

    func testIstanbulWinterSolstice() {
        let zone = TimeZone(identifier: "Europe/Istanbul")!
        let day = SolarCalculator.day(containing: date(2026, 12, 21, zone), at: istanbul, timeZone: zone)
        assertNormal(day, sunrise: 8 * 60 + 25, sunset: 17 * 60 + 38, zone: zone)
    }

    func testTromsoPolarNightAndMidnightSun() {
        let zone = TimeZone(identifier: "Europe/Oslo")!
        XCTAssertEqual(SolarCalculator.day(containing: date(2026, 12, 21, zone), at: tromso, timeZone: zone), .alwaysNight)
        XCTAssertEqual(SolarCalculator.day(containing: date(2026, 6, 21, zone), at: tromso, timeZone: zone), .alwaysDay)
    }
}

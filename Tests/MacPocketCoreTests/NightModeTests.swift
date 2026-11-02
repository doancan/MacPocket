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

    // MARK: Night curve

    func testDaylightIsNeutral() {
        let f = ColorTemperature.channelFactors(kelvin: 6500)
        XCTAssertEqual([f.red, f.green, f.blue], [1, 1, 1])
        let hot = ColorTemperature.channelFactors(kelvin: 9000)
        XCTAssertEqual([hot.red, hot.green, hot.blue], [1, 1, 1])
    }

    func testWarmCutsBlueMost() {
        let f = ColorTemperature.channelFactors(kelvin: 3400)
        XCTAssertEqual(f.red, 1)
        XCTAssertLessThan(f.blue, f.green)
        XCTAssertLessThan(f.green, 1)
        let low = ColorTemperature.channelFactors(kelvin: 500)
        let floor = ColorTemperature.channelFactors(kelvin: 1900)
        XCTAssertEqual(low.blue, floor.blue)
        for v in [low.red, low.green, low.blue] { XCTAssertTrue((0...1).contains(v)) }
    }

    private let zone = TimeZone(identifier: "Europe/Istanbul")!
    private func at(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: hour, minute: minute))!
    }
    private var normalDay: SolarDay { .normal(sunrise: at(6, 0), sunset: at(18, 0)) }

    func testCurveMidTransitionIsHalfway() {
        let t = NightCurve.target(at: at(18, 0), day: normalDay, settings: NightSettings())
        XCTAssertEqual(t.night, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.level, 0.8, accuracy: 1e-9)
        XCTAssertEqual(t.kelvin, 4950, accuracy: 1e-6)
    }

    func testCurveBeforeAndAfter() {
        let s = NightSettings()
        XCTAssertEqual(NightCurve.target(at: at(17, 29), day: normalDay, settings: s).night, 0)
        XCTAssertEqual(NightCurve.target(at: at(18, 31), day: normalDay, settings: s).night, 1)
        XCTAssertEqual(NightCurve.target(at: at(6, 16), day: normalDay, settings: s).night, 0)
        XCTAssertEqual(NightCurve.target(at: at(3, 0), day: normalDay, settings: s).night, 1)
        XCTAssertEqual(NightCurve.target(at: at(6, 0), day: normalDay, settings: s).night, 0.5, accuracy: 1e-9)
        XCTAssertEqual(NightCurve.target(at: at(12, 0), day: normalDay, settings: s).level, 1)
    }

    func testPolarDays() {
        let s = NightSettings()
        XCTAssertEqual(NightCurve.target(at: at(12, 0), day: .alwaysNight, settings: s).night, 1)
        XCTAssertEqual(NightCurve.target(at: at(0, 0), day: .alwaysDay, settings: s).night, 0)
    }

    func testOldScheduleDecodes() throws {
        let json = #"{"enabled":true,"points":[{"minute":420,"level":1},{"minute":1140,"level":0.8}]}"#
        let schedule = try JSONDecoder().decode(BrightnessSchedule.self, from: Data(json.utf8))
        XCTAssertTrue(schedule.enabled)
        XCTAssertNil(schedule.source)
        XCTAssertNil(schedule.night)
        XCTAssertEqual(schedule.points.count, 2)
    }

    func testPartialNightSettingsDecode() throws {
        let s = try JSONDecoder().decode(NightSettings.self, from: Data(#"{"nightLevel":0.5}"#.utf8))
        XCTAssertEqual(s.nightLevel, 0.5)
        XCTAssertEqual(s.nightKelvin, 3400)
        XCTAssertEqual(s.colorMethod, .macPocket)
    }

    func testComposeAppliesWarmthThenBrightness() {
        let result = GammaComposer.compose([1, 0.5], factor: 0.5, scale: 0.8)
        XCTAssertEqual(result[0], 0.4, accuracy: 1e-6)
        XCTAssertEqual(result[1], 0.2, accuracy: 1e-6)
        XCTAssertEqual(GammaComposer.compose([0.25, 1], factor: 1, scale: 1), [0.25, 1])
    }
    // MARK: Night Shift

    func testSessionRestoresPreviousNightShift() {
        let previous = NightShiftState(enabled: false, strength: 0.3, mode: 1)
        let fake = FakeNightShift(state: previous)
        var stored: NightShiftState?
        let session = NightShiftSession(client: fake, load: { stored }, save: { stored = $0 })
        session.activate(strength: 0.7)
        XCTAssertEqual(fake.state.enabled, true)
        XCTAssertEqual(fake.state.strength, 0.7, accuracy: 1e-9)
        session.deactivate()
        XCTAssertEqual(fake.restored, [previous])
        session.deactivate()
        XCTAssertEqual(fake.restored, [previous])
        XCTAssertNil(stored)
    }

    func testSessionPersistsSnapshotOnFirstActivate() {
        let previous = NightShiftState(enabled: true, strength: 0.5, mode: 2)
        let fake = FakeNightShift(state: previous)
        var stored: NightShiftState?
        let session = NightShiftSession(client: fake, load: { stored }, save: { stored = $0 })
        session.activate(strength: 0.4)
        XCTAssertEqual(stored, previous)
        session.activate(strength: 0.9)
        XCTAssertEqual(stored, previous)
        XCTAssertEqual(fake.snapshots, 1)
        XCTAssertEqual(fake.state.strength, 0.9, accuracy: 1e-9)
    }

    func testRecoverRestoresLeftoverSnapshot() {
        let leftover = NightShiftState(enabled: false, strength: 0.2, mode: 1)
        let fake = FakeNightShift(state: NightShiftState(enabled: true, strength: 0.8, mode: 0))
        var stored: NightShiftState? = leftover
        let session = NightShiftSession(client: fake, load: { stored }, save: { stored = $0 })
        session.recoverIfNeeded()
        XCTAssertEqual(fake.restored, [leftover])
        XCTAssertNil(stored)
        session.recoverIfNeeded()
        session.deactivate()
        XCTAssertEqual(fake.restored, [leftover])
    }

    func testActivateAfterLeftoverKeepsLeftoverAsPrevious() {
        let leftover = NightShiftState(enabled: false, strength: 0.2, mode: 1)
        let fake = FakeNightShift(state: NightShiftState(enabled: true, strength: 0.8, mode: 0))
        var stored: NightShiftState? = leftover
        let session = NightShiftSession(client: fake, load: { stored }, save: { stored = $0 })
        session.activate(strength: 0.6)
        XCTAssertEqual(stored, leftover)
        session.deactivate()
        XCTAssertEqual(fake.restored, [leftover])
        XCTAssertNil(stored)
    }

    func testNightShiftStrengthFromKelvin() {
        XCTAssertEqual(NightShiftStrength.from(kelvin: 6500), 0)
        XCTAssertEqual(NightShiftStrength.from(kelvin: 1900), 1)
        XCTAssertEqual(NightShiftStrength.from(kelvin: 4200), 0.5, accuracy: 1e-9)
        XCTAssertEqual(NightShiftStrength.from(kelvin: 9000), 0)
        XCTAssertEqual(NightShiftStrength.from(kelvin: 500), 1)
    }
}

private final class FakeNightShift: NightShiftControlling {
    var state: NightShiftState
    var restored: [NightShiftState] = []
    var snapshots = 0
    init(state: NightShiftState) { self.state = state }
    var isAvailable: Bool { true }
    func snapshot() -> NightShiftState? { snapshots += 1; return state }
    func apply(enabled: Bool, strength: Double) { state = NightShiftState(enabled: enabled, strength: strength, mode: 0) }
    func restore(_ state: NightShiftState) { restored.append(state); self.state = state }
}

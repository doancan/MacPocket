import XCTest
@testable import MacPocketCore

final class SystemInsightsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(at offset: TimeInterval = 0, load: Double = 1, pressure: Int = 1, thermal: String = "nominal",
                          online: Bool = true, free: Int64 = 400 << 30, swap: UInt64 = 0) -> SystemSnapshot {
        var snapshot = SystemSnapshot(
            capturedAt: start + offset, hardwareModel: "fixture", logicalCPUCount: 10,
            cpuUserPercent: 20, cpuSystemPercent: 5, cpuIdlePercent: 75, physicalMemoryBytes: 32 << 30,
            freeMemoryBytes: 8 << 30, wiredMemoryBytes: 4 << 30, compressedMemoryBytes: 1 << 30, appMemoryBytes: 10 << 30,
            swapUsedBytes: swap, uptimeSeconds: 100, thermalState: thermal,
            volumes: [VolumeSnapshot(name: "Macintosh HD", path: "/", totalBytes: 1_000 << 30, availableBytes: free)],
            power: PowerSnapshot(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil,
                                 lowPowerMode: false, minutesRemaining: nil))
        snapshot.loadAverages = [load, load, load]
        snapshot.memoryPressureLevel = pressure
        snapshot.connectivity = ConnectivitySnapshot(online: online, link: .wifi, vpnActive: false, wifiRSSI: -50, pingMilliseconds: 20)
        return snapshot
    }

    // MARK: History

    func testHistoryAveragesSamplesIntoBucketsAndStaysBounded() {
        var history = MetricHistory()
        for second in stride(from: 0, to: 7_200, by: 1) {
            history.record(MetricPoint(date: start + Double(second), cpu: second < 5 ? 10 : 30, diskFree: Double(second)))
        }
        let hour = history.points(.hour)
        XCTAssertLessThanOrEqual(hour.count, 361, "an hour of 10-s buckets")
        XCTAssertGreaterThanOrEqual(hour.first!.date, start + 3_600 - 10, "older points fall off")
        XCTAssertEqual(hour.last!.cpu!, 30, accuracy: 0.001)
        XCTAssertEqual(hour.last!.diskFree, 7_199, "free space keeps the latest reading, not an average")
        // Two hours of 2-minute buckets; the start need not sit on a bucket edge, which adds one.
        XCTAssertTrue((60...61).contains(history.points(.day).count))
    }

    func testHistoryMergesAMissingValueWithoutDraggingTheAverage() {
        var history = MetricHistory()
        history.record(MetricPoint(date: start, cpu: 40))
        history.record(MetricPoint(date: start + 1, cpu: nil))
        XCTAssertEqual(history.points(.hour).first?.cpu, 40)
    }

    func testHistoryStartsOverWhenTheClockGoesBack() {
        var history = MetricHistory()
        history.record(MetricPoint(date: start, cpu: 1))
        history.record(MetricPoint(date: start - 3_600, cpu: 2))
        XCTAssertEqual(history.points(.hour).map(\.cpu), [2])
    }

    func testHistoryRoundTripsThroughJSON() throws {
        var history = MetricHistory()
        history.record(MetricPoint(date: start, cpu: 12, memory: 0.5))
        let decoded = try JSONDecoder().decode(MetricHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
    }

    // MARK: Disk forecast

    func testForecastFollowsAShrinkingDisk() throws {
        // Losing 10 GB a day with 100 GB left: ten days.
        let perHour: Double = 10e9 / 24
        let points: [(date: Date, free: Double)] = (0..<24).map { hour in
            (date: start + Double(hour) * 3_600, free: 100e9 + perHour * Double(23 - hour))
        }
        XCTAssertEqual(try XCTUnwrap(DiskForecast.daysUntilFull(points)), 10, accuracy: 0.01)
    }

    func testForecastIsNilForAGrowingOrShortHistory() {
        let growing: [(date: Date, free: Double)] = (0..<24).map { hour in (date: start + Double(hour) * 3_600, free: 100e9 + Double(hour) * 1e9) }
        XCTAssertNil(DiskForecast.daysUntilFull(growing))
        let short: [(date: Date, free: Double)] = (0..<24).map { minute in (date: start + Double(minute) * 60, free: 100e9 - Double(minute) * 1e9) }
        XCTAssertNil(DiskForecast.daysUntilFull(short), "twenty minutes is noise, not a trend")
    }

    // MARK: Health

    func testAHealthyMacScoresFullMarks() {
        XCTAssertEqual(SystemHealth.evaluate(snapshot()), HealthReport(score: 100, issues: []))
    }

    func testIssuesLowerTheScoreAndComeMostSeriousFirst() {
        let report = SystemHealth.evaluate(snapshot(load: 12, pressure: 2, thermal: "serious", free: 30 << 30),
                                           busiestProcess: "node")
        XCTAssertEqual(Set(report.issues.map(\.kind)), [.thermal, .diskLow, .cpuBusy, .memoryPressure])
        let severities = report.issues.map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >), "most serious first")
        XCTAssertEqual(report.issues.first { $0.kind == .cpuBusy }?.subject, "node")
        // Thermal and the 3 % free disk are critical; a load of 1.2 per core and pressure level 2 are warnings.
        XCTAssertEqual(report.score, 100 - 2 * SystemHealth.criticalPenalty - 2 * SystemHealth.warningPenalty)
        XCTAssertEqual(report.issues.first?.severity, .critical)
    }

    func testAFillingDiskIsReportedOnlyWhileItIsNotAlreadyLow() {
        XCTAssertEqual(SystemHealth.evaluate(snapshot(), diskDaysLeft: 5).issues.map(\.kind), [.diskFillingSoon])
        XCTAssertEqual(SystemHealth.evaluate(snapshot(free: 20 << 30), diskDaysLeft: 5).issues.map(\.kind), [.diskLow])
    }

    // MARK: Events

    func testDetectorReportsOnlyChanges() {
        var detector = SystemEventDetector()
        XCTAssertEqual(detector.events(from: snapshot()), [])
        XCTAssertEqual(detector.events(from: snapshot(at: 1)), [])
        let lost = detector.events(from: snapshot(at: 2, online: false))
        XCTAssertEqual(lost.map(\.kind), [.networkLost])
        let changed = detector.events(from: snapshot(at: 3, pressure: 4, thermal: "fair", online: true))
        XCTAssertEqual(Set(changed.map(\.kind)), [.networkRestored, .thermalRaised, .memoryPressureCritical])
        XCTAssertEqual(detector.events(from: snapshot(at: 4, pressure: 4, thermal: "fair")), [])
    }

    func testLogDropsOldAndExcessEvents() {
        var log = SystemEventLog()
        log.append([SystemEvent(date: start - SystemEventLog.maximumAge - 1, kind: .wake)], now: start)
        XCTAssertTrue(log.events.isEmpty)
        log.append((0..<(SystemEventLog.maximumCount + 20)).map { SystemEvent(date: start + Double($0), kind: .sleep) }, now: start + 1_000)
        XCTAssertEqual(log.events.count, SystemEventLog.maximumCount)
        XCTAssertEqual(log.events.last?.date, start + Double(SystemEventLog.maximumCount + 19))
    }
}

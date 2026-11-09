import Foundation

@main enum ScreenTimeSummaryBenchmark {
    /// Previous month-view calculations, including the separately calculated chart values.
    @inline(never) static func legacy(_ days: [UsageDay]) -> [Double] {
        let total = days.reduce(0) { $0 + $1.total }
        let active = max(1, days.filter { $0.total > 0 }.count)
        let hours = UsageLedger.hourTotals(days)
        let trend = days.map(\.total)
        let peakHours = UsageLedger.hourTotals(days)
        let average = days.map(\.total).reduce(0, +) / Double(max(1, days.filter { $0.total > 0 }.count))
        let bars = days.map(\.total)
        let maximum = days.map(\.total).max() ?? 0
        return [total, Double(active), average, maximum] + trend + hours + peakHours + bars
    }

    @inline(never) static func shared(_ days: [UsageDay]) -> [Double] {
        let summary = UsagePeriodSummary(days)
        return [summary.total, Double(summary.activeDayCount), summary.average, summary.maximumDayTotal]
            + summary.dayTotals + summary.hourTotals + summary.hourTotals + summary.dayTotals
    }

    static func main() throws {
        let fixtures: [[UsageDay]] = (0..<8).map { seed in
            (0..<30).map { day in
                let apps = Dictionary(uniqueKeysWithValues: (0..<500).map { ("app\($0)", Double(($0 + day + seed) % 120) + 0.25) })
                let hours = Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, Double(($0 + day + seed) * 20)) })
                return UsageDay(apps: day.isMultiple(of: 6) ? [:] : apps, hours: hours)
            }
        }
        var timings: [String: [Double]] = ["repeated": [], "shared": []]
        var equivalent = true
        var checksum = 0.0
        for fixture in fixtures { equivalent = equivalent && legacy(fixture) == shared(fixture) }
        for pair in 0..<18 {
            for name in pair.isMultiple(of: 2) ? ["repeated", "shared"] : ["shared", "repeated"] {
                let start = ProcessInfo.processInfo.systemUptime
                for iteration in 0..<80 {
                    let days = fixtures[(pair + iteration) % fixtures.count]
                    let values = name == "repeated" ? legacy(days) : shared(days)
                    checksum += values.reduce(0, +)
                }
                let perSummaryMS = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 80
                if pair >= 3 { timings[name, default: []].append(perSummaryMS) }
            }
        }
        var rows: [[String: Any]] = []
        for name in ["repeated", "shared"] {
            let values = timings[name]!.sorted()
            let row: [String: Any] = ["method":name, "iterations":values.count, "medianMS":values[values.count / 2],
                "p95MS":values[Int(Double(values.count - 1) * 0.95)], "samplesMS":timings[name]!]
            rows.append(row)
            print(name, "medianMS", row["medianMS"]!, "p95MS", row["p95MS"]!)
        }
        let result: [String: Any] = ["passed":equivalent && checksum.isFinite && checksum > 0,
            "equivalent":equivalent,"checksum":checksum,"days":30,"appsPerActiveDay":500,"fixtures":8,
            "configuration":"swiftc -O", "ordering":"interleaved; 3 warmup pairs, 15 measured pairs; 80 summaries per batch",
            "boundary":"period/day/hour aggregation; excludes app ranking, live-segment recording and UI rendering", "measurements":rows]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        if !equivalent || !checksum.isFinite || checksum <= 0 { exit(1) }
    }
}

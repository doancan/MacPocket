import Foundation

/// Compiled together with the production Core sources by scripts/bench/clipboard-search.sh.
@main struct ClipboardSearchBenchmark {
    @MainActor private final class Heartbeat {
        var finished = false
        var delays: [Double] = []
    }
    @MainActor static func main() async throws {
        var rows: [[String: Any]] = []
        for (count, length) in [(200, 200), (1000, 200), (200, 20_000), (1000, 20_000)] {
            let history = ClipboardHistory(items: (0..<count).map {
                ClipboardItem(content: .text("İstanbul fixture \($0) " + String(repeating: "x", count: length)),
                              copiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                              sourceName: "FixtureApp", pinned: $0.isMultiple(of: 10))
            })
            let index = ClipboardSearchIndex()
            let heartbeat = Heartbeat()
            let pulse = Task { @MainActor in
                while !heartbeat.finished {
                    let started = ProcessInfo.processInfo.systemUptime
                    try await Task.sleep(for: .milliseconds(5))
                    heartbeat.delays.append(max(0, (ProcessInfo.processInfo.systemUptime - started) * 1000 - 5))
                }
            }
            await Task.yield()
            let started = ProcessInfo.processInfo.systemUptime
            try await index.prepare(history, revision: 1)
            let coldMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
            heartbeat.finished = true
            _ = try await pulse.value
            var queries: [[String: Any]] = []
            for query in ["", "fixture", "ıstanbul", "missing-token", "ß", "olmayan-öğe"] {
                var legacy: [Double] = [], indexed: [Double] = []
                for _ in 0..<3 {
                    let before = ProcessInfo.processInfo.systemUptime
                    let expected = history.search(query)
                    legacy.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
                    let searchStart = ProcessInfo.processInfo.systemUptime
                    let actual = try await index.search(query, in: history, revision: 1)
                    indexed.append((ProcessInfo.processInfo.systemUptime - searchStart) * 1000)
                    precondition(actual == expected, "Search mismatch: \(query)")
                }
                queries.append(["query": query, "legacyMedianMS": legacy.sorted()[1],
                                "indexedMedianMS": indexed.sorted()[1]])
            }
            var updated = history
            var settings = ClipboardSettings()
            settings.capacity = count
            settings.retentionDays = nil
            _ = updated.record(.text("Yeni İstanbul"), at: Date(timeIntervalSince1970: 1_800_000_001), settings: settings)
            let updateStart = ProcessInfo.processInfo.systemUptime
            try await index.prepare(updated, revision: 2)
            let updateMS = (ProcessInfo.processInfo.systemUptime - updateStart) * 1000
            rows.append(["items": count, "charactersPerItem": length, "coldPreparationMS": coldMS,
                         "mainActorHeartbeatMaxExtraDelayMS": heartbeat.delays.max() ?? 0,
                         "mainActorHeartbeatCount": heartbeat.delays.count, "singleRecordUpdateMS": updateMS, "queries": queries])
            print("Measured \(count) × \(length); cold preparation \(coldMS) ms")
        }
        let result: [String: Any] = ["configuration": "swiftc -O -whole-module-optimization; production sources; synthetic history; no pasteboard or user archive",
                                     "rows": rows]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

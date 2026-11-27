import Foundation

/// Compiled with production Core files by scripts/bench/clipboard-writes.sh.
@main struct ClipboardWriteBenchmark {
    private static func ms(since start: Double) -> Double { (ProcessInfo.processInfo.systemUptime - start) * 1000 }
    private static func stats(_ values: [Double]) -> [String: Any] {
        let sorted = values.sorted()
        return ["medianMS": sorted[sorted.count / 2], "p95MS": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1], "samplesMS": values]
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = root.appendingPathComponent("write-fixtures-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixtures) }
        var rows: [[String: Any]] = []
        for (count, length) in [(200, 200), (1000, 200), (200, 20_000), (1000, 20_000)] {
            var history = ClipboardHistory(items: (0..<count).map {
                ClipboardItem(content: .text("Fixture \($0) " + String(repeating: "x", count: length)),
                              copiedAt: Date(timeIntervalSince1970: 1_800_000_000))
            })
            let baseline = ClipboardArchive(directory: fixtures.appendingPathComponent("baseline"))
            let optimized = ClipboardArchive(directory: fixtures.appendingPathComponent("optimized"))
            let writer = ClipboardArchiveWriter(archive: optimized)
            var sync: [Double] = [], asyncTotal: [Double] = [], enqueue: [Double] = []
            var syncProbe: [Double] = [], asyncProbe: [Double] = []
            for round in 0..<11 {
                history.setPinned(round.isMultiple(of: 2), for: history.items[0].id)
                let beforeSync = ProcessInfo.processInfo.systemUptime
                let baselineProbe = Task { @MainActor in ms(since: beforeSync) }
                try baseline.save(history)
                let syncMS = ms(since: beforeSync)
                let baselineDelay = await baselineProbe.value

                let beforeAsync = ProcessInfo.processInfo.systemUptime
                let backgroundProbe = Task { @MainActor in ms(since: beforeAsync) }
                var enqueueMS: Double = 0
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    let beforeEnqueue = ProcessInfo.processInfo.systemUptime
                    writer.save(history, revision: UInt64(round)) { continuation.resume(with: $0) }
                    enqueueMS = ms(since: beforeEnqueue)
                }
                let totalMS = ms(since: beforeAsync)
                let backgroundDelay = await backgroundProbe.value
                let baselineHistory = try baseline.load(), optimizedHistory = try optimized.load()
                precondition(baselineHistory == history)
                precondition(optimizedHistory == history)
                if round > 0 {
                    sync.append(syncMS)
                    asyncTotal.append(totalMS)
                    enqueue.append(enqueueMS)
                    syncProbe.append(baselineDelay)
                    asyncProbe.append(backgroundDelay)
                }
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: optimized.historyFile.path)
            let mode = (attributes[.posixPermissions] as! NSNumber).intValue
            precondition(mode == 0o600)
            rows.append(["items": count, "charactersPerItem": length, "fileBytes": attributes[.size] as! NSNumber,
                         "legacyMainActorSave": stats(sync), "backgroundEnqueue": stats(enqueue),
                         "backgroundCompletion": stats(asyncTotal), "legacyMainActorProbe": stats(syncProbe),
                         "backgroundMainActorProbe": stats(asyncProbe), "fileMode": mode])
        }
        let data = try JSONSerialization.data(withJSONObject: ["configuration": "swiftc -O -whole-module-optimization; 1 warmup + 10 paired writes; private temporary archives; no user data",
                                                               "rows": rows], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("write-report.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}

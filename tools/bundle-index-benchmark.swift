import Foundation

@main enum BundleIndexBenchmark {
    static func legacy(_ candidates: [String], installedIDs: Set<String>) -> [Bool] {
        let installed = Set(installedIDs.map { $0.lowercased() })
        return candidates.map { candidate in
            let id = candidate.lowercased()
            return installed.contains { id == $0 || id.hasPrefix($0 + ".") || id.hasPrefix($0 + "-") }
        }
    }

    static func indexed(_ candidates: [String], installedIDs: Set<String>) -> [Bool] {
        let index = InstalledBundleIndex(installedIDs)
        return candidates.map { index.containsApplicationOrHelper($0) }
    }

    static func main() throws {
        let installed = Set((0..<500).map { "com.vendor\($0 % 53).app\($0)-desktop" })
        let candidates = installed.sorted().flatMap { id in
            [id, id.uppercased(), id + ".Helper", id + "-Helper", id + ".worker-extra",
             id + "2", id + "lication", "other." + id, "org.removed." + id, id + "X.Helper"]
        }
        var times: [String: [Double]] = ["linear": [], "indexed": []]
        var equivalent = true
        var matched = 0
        for pair in 0..<18 {
            var outputs: [String: [Bool]] = [:]
            for name in pair.isMultiple(of: 2) ? ["linear", "indexed"] : ["indexed", "linear"] {
                let start = ProcessInfo.processInfo.systemUptime
                let output = name == "linear" ? legacy(candidates, installedIDs: installed) : indexed(candidates, installedIDs: installed)
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                outputs[name] = output
                if pair >= 3 { times[name, default: []].append(elapsed) }
            }
            equivalent = equivalent && outputs["linear"] == outputs["indexed"]
            matched = outputs["indexed"]!.filter { $0 }.count
        }
        var rows: [[String: Any]] = []
        for name in ["linear", "indexed"] {
            let values = times[name]!.sorted()
            let row: [String: Any] = ["method": name, "iterations": values.count, "medianMS": values[values.count / 2],
                "p95MS": values[Int(Double(values.count - 1) * 0.95)], "samplesMS": times[name]!]
            rows.append(row)
            print(name, "medianMS", row["medianMS"]!, "p95MS", row["p95MS"]!)
        }
        let result: [String: Any] = ["passed": equivalent && matched == 2500, "equivalent": equivalent,
            "installedIDs": installed.count, "candidates": candidates.count, "matched": matched,
            "configuration": "swiftc -O", "ordering": "interleaved; 3 warmup pairs, 15 measured pairs",
            "boundary": "index construction, case folding and matching; synthetic identifiers; no file I/O", "measurements": rows]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        if !equivalent || matched != 2500 { exit(1) }
    }
}

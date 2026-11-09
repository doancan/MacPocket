import Foundation

@main enum ClipboardPreviewBenchmark {
    static func legacy(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return String((line.map(String.init) ?? text).trimmingCharacters(in: .whitespaces).prefix(200))
    }

    static func main() throws {
        let tail = String(repeating: "2026-11-09 12:00:00 [debug] another synthetic log entry\n", count: 16_000)
        let inputs = (0..<10).map { "\n\t\n  Synthetic log header \($0)  \r\n" + tail }
        var timings: [String: [Double]] = ["splitAll": [], "firstLine": []]
        var equivalent = true
        var checksum = 0
        for pair in 0..<18 {
            var outputs: [String: [String]] = [:]
            for name in pair.isMultiple(of: 2) ? ["splitAll", "firstLine"] : ["firstLine", "splitAll"] {
                let start = ProcessInfo.processInfo.systemUptime
                let titles = inputs.map { name == "splitAll" ? legacy($0) : ClipboardTextPreview.title($0) }
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                outputs[name] = titles
                checksum += titles.reduce(0) { $0 + $1.utf8.count }
                if pair >= 3 { timings[name, default: []].append(elapsed) }
            }
            equivalent = equivalent && outputs["splitAll"] == outputs["firstLine"]
        }
        var rows: [[String: Any]] = []
        for name in ["splitAll", "firstLine"] {
            let values = timings[name]!.sorted()
            let row: [String: Any] = ["method":name, "iterations":values.count, "medianMS":values[values.count / 2],
                "p95MS":values[Int(Double(values.count - 1) * 0.95)], "samplesMS":timings[name]!]
            rows.append(row)
            print(name, "medianMS", row["medianMS"]!, "p95MS", row["p95MS"]!)
        }
        let result: [String: Any] = ["passed":equivalent && checksum > 0, "equivalent":equivalent, "checksum":checksum,
            "entries":inputs.count, "charactersPerEntry":inputs[0].count, "bytesPerEntry":inputs[0].utf8.count,
            "configuration":"swiftc -O", "ordering":"interleaved; 3 warmup pairs, 15 measured pairs",
            "boundary":"preview title calculation for ten synthetic log entries; no UI rendering or pasteboard access", "measurements":rows]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        if !equivalent || checksum == 0 { exit(1) }
    }
}

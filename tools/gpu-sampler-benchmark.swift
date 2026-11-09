import Foundation
import IOKit

@main struct GPUSamplerBenchmark {
    /// Previous production implementation; comparison only, never linked into the app.
    static func legacySample() -> GPUSnapshot? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: GPUSnapshot?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var raw: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = raw?.takeRetainedValue() as? [String: Any], let value = GPUSnapshot(properties: properties) else { continue }
            if best == nil || value.utilizationPercent > best!.utilizationPercent { best = value }
        }
        return best
    }
    static func main() throws {
        var timings: [String: [Double]] = ["wholeTable":[], "targeted":[]]
        var checks = ["readableGPU":true, "metadataMatches":true, "valuesPlausible":true]
        let sampler = GPUSampler()
        for index in 0..<85 {
            var values: [String: GPUSnapshot] = [:]
            for name in index.isMultiple(of: 2) ? ["wholeTable", "targeted"] : ["targeted", "wholeTable"] {
                let start = ProcessInfo.processInfo.systemUptime
                let value = name == "wholeTable" ? legacySample() : sampler.sample()
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                guard let value else { checks["readableGPU"] = false; continue }
                values[name] = value
                checks["valuesPlausible"] = checks["valuesPlausible"] == true && value.utilizationPercent.isFinite && (0...100).contains(value.utilizationPercent)
                if index >= 5 { timings[name, default: []].append(elapsed) }
            }
            if let old = values["wholeTable"], let new = values["targeted"] {
                checks["metadataMatches"] = checks["metadataMatches"] == true && old.model == new.model && old.coreCount == new.coreCount
            }
        }
        var rows: [[String: Any]] = []
        for name in ["wholeTable", "targeted"] {
            let values = timings[name]!.sorted()
            guard !values.isEmpty else { continue }
            rows.append(["reader":name,"iterations":values.count,"medianMS":values[values.count/2],
                "p95MS":values[Int(Double(values.count-1)*0.95)],"samplesMS":timings[name]!])
        }
        let report: [String: Any] = ["passed":checks.values.allSatisfy { $0 },"checks":checks,"measurements":rows,
            "configuration":"swiftc -O","ordering":"interleaved; 5 warmup pairs, 80 measured pairs",
            "boundary":"accelerator enumeration, property copying and GPUSnapshot parsing",
            "cachedLiveValues":false,"networkRequests":false]
        if CommandLine.arguments.count > 1 {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        for row in rows { print(row["reader"]!, "medianMS", row["medianMS"]!, "p95MS", row["p95MS"]!) }
        if !checks.values.allSatisfy({ $0 }) { exit(1) }
    }
}

import Foundation
import IOKit

/// GPU load as the graphics driver publishes it in the I/O Registry (`IOAccelerator` → `PerformanceStatistics`).
/// Readable without privileges on Apple silicon and on Intel Macs with Apple's drivers.
public struct GPUSnapshot: Codable, Sendable, Equatable {
    /// "Device Utilization %": the share of time the GPU was busy.
    public let utilizationPercent: Double
    /// "Renderer Utilization %" (fragment work), when published.
    public let rendererPercent: Double?
    /// "Tiler Utilization %" (geometry work), when published.
    public let tilerPercent: Double?
    /// "In use system memory": unified memory the GPU currently holds.
    public let memoryInUseBytes: UInt64?
    public let model: String?
    public let coreCount: Int?

    public init(utilizationPercent: Double, rendererPercent: Double? = nil, tilerPercent: Double? = nil,
                memoryInUseBytes: UInt64? = nil, model: String? = nil, coreCount: Int? = nil) {
        self.utilizationPercent = utilizationPercent; self.rendererPercent = rendererPercent
        self.tilerPercent = tilerPercent; self.memoryInUseBytes = memoryInUseBytes
        self.model = model; self.coreCount = coreCount
    }

    /// Parses one accelerator's registry properties; nil when it publishes no utilization.
    public init?(properties: [String: Any]) {
        guard let statistics = properties["PerformanceStatistics"] as? [String: Any],
              let device = Self.number(statistics["Device Utilization %"]) ?? Self.number(statistics["GPU Activity(%)"]) else { return nil }
        self.init(utilizationPercent: min(100, max(0, device)),
                  rendererPercent: Self.number(statistics["Renderer Utilization %"]).map { min(100, max(0, $0)) },
                  tilerPercent: Self.number(statistics["Tiler Utilization %"]).map { min(100, max(0, $0)) },
                  memoryInUseBytes: Self.number(statistics["In use system memory"]).map { UInt64(max(0, $0)) },
                  model: properties["model"] as? String,
                  coreCount: Self.number(properties["gpu-core-count"]).map { Int($0) })
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let int as Int: Double(int)
        case let double as Double: double
        default: nil
        }
    }
}

struct GPUSampler {
    /// The busiest accelerator, so a Mac with several GPUs reports the one doing the work.
    func sample() -> GPUSnapshot? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: GPUSnapshot?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let snapshot = Self.snapshot(readProperty: { key in
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }) else { continue }
            if best == nil || snapshot.utilizationPercent > best!.utilizationPercent { best = snapshot }
        }
        return best
    }

    /// Read current statistics and metadata without serializing the driver's entire property table.
    static func snapshot(readProperty: (String) -> Any?) -> GPUSnapshot? {
        guard let statistics = readProperty("PerformanceStatistics") as? [String: Any] else { return nil }
        var properties: [String: Any] = ["PerformanceStatistics": statistics]
        for key in ["model", "gpu-core-count"] {
            if let value = readProperty(key) { properties[key] = value }
        }
        return GPUSnapshot(properties: properties)
    }
}

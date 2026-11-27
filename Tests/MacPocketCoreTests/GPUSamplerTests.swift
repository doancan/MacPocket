import XCTest
@testable import MacPocketCore

final class GPUSamplerTests: XCTestCase {
    func testTargetedPropertiesMatchWholeTableParsing() throws {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 28, "Renderer Utilization %": 27,
            "Tiler Utilization %": 14, "In use system memory": 1_073_741_824], "model":"Fixture GPU", "gpu-core-count":16,
            "UnrelatedDriverData": Data(repeating: 0, count: 100_000)]
        var requested: [String] = []
        let result = try XCTUnwrap(GPUSampler.snapshot { requested.append($0); return properties[$0] })
        XCTAssertEqual(result, GPUSnapshot(properties: properties))
        XCTAssertEqual(Set(requested), ["PerformanceStatistics", "model", "gpu-core-count"])
        XCTAssertEqual(requested.count, 3)
    }
    func testMissingOrMalformedStatisticsSkipMetadataAndDoNotInventZero() {
        for value in [nil, "unreadable"] as [Any?] {
            var requested: [String] = []
            XCTAssertNil(GPUSampler.snapshot { requested.append($0); return value })
            XCTAssertEqual(requested, ["PerformanceStatistics"])
        }
        XCTAssertNil(GPUSampler.snapshot { $0 == "PerformanceStatistics" ? ["Renderer Utilization %": 25] : nil })
    }
    func testOptionalMetadataCanBeMissingAndFallbackCounterStillWorks() throws {
        let result = try XCTUnwrap(GPUSampler.snapshot { $0 == "PerformanceStatistics" ? ["GPU Activity(%)": 0] : nil })
        XCTAssertEqual(result.utilizationPercent, 0)
        XCTAssertNil(result.model)
        XCTAssertNil(result.coreCount)
        XCTAssertNil(result.memoryInUseBytes)
    }
    func testEverySampleReadsFreshStatisticsAndMetadata() throws {
        var load = 10, cores = 8
        let read: (String) -> Any? = { key in
            switch key {
            case "PerformanceStatistics": ["Device Utilization %": load]
            case "gpu-core-count": cores
            case "model": "Fixture GPU"
            default: nil
            }
        }
        XCTAssertEqual(GPUSampler.snapshot(readProperty: read)?.utilizationPercent, 10)
        load = 80
        cores = 16
        let fresh = try XCTUnwrap(GPUSampler.snapshot(readProperty: read))
        XCTAssertEqual(fresh.utilizationPercent, 80)
        XCTAssertEqual(fresh.coreCount, 16)
    }
}

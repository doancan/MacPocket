import Darwin
import Foundation
import Testing
@testable import MacPocketCore

/// Measures the real scan of this Mac (read-only). Off unless `MACPOCKET_LIVE_SCAN=1`.
@Suite(.serialized) struct SystemDataLiveScanTests {
    private static func residentBytes() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : -1
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPOCKET_LIVE_SCAN"] == "1"))
    func theRealScanStreamsQuicklyAndDoesNotLeakAcrossRepeatedScans() async {
        var rows: [String] = []
        let baseline = Self.residentBytes()
        for round in 1...4 {
            let started = Date()
            var firstItem: TimeInterval?
            var phases: [String] = []
            var count = 0, unreadable = 0
            for await event in SystemDataScanner(environment: SystemDataEnvironment()).scan() {
                switch event {
                case .item: count += 1
                if firstItem == nil { firstItem = Date().timeIntervalSince(started) }
                case .phase: phases.append("\(Int(Date().timeIntervalSince(started)))s")
                case .progress: break
                case .finished(let report): unreadable = report.unreadablePlaces
                }
            }
            let total = Date().timeIntervalSince(started)
            rows.append(String(format: "round %d: first item %.2fs, total %.1fs, %d items, %d unreadable, phases at %@, rss %+.0f MB",
                               round, firstItem ?? -1, total, count, unreadable, phases.joined(separator: ","),
                               Double(Self.residentBytes() - baseline) / 1_048_576))
        }
        Issue.record(Comment(rawValue: rows.joined(separator: "\n")), severity: .warning)
        let growth = Self.residentBytes() - baseline
        #expect(growth < 400_000_000, "resident memory grew by \(growth / 1_048_576) MB over four scans")
    }
}

/// Read-only estimate of what compressing a real folder would save: `MACPOCKET_LIVE_SHRINK_FOLDER=/path swift
/// test --filter liveShrinkEstimate`.
@Suite struct SystemDataLiveShrinkEstimateTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPOCKET_LIVE_SHRINK_FOLDER"] != nil))
    func liveShrinkEstimate() async throws {
        let folder = try #require(ProcessInfo.processInfo.environment["MACPOCKET_LIVE_SHRINK_FOLDER"])
        let started = Date()
        let estimate = try await SystemDataShrinker().estimate(folder: folder)
        print("LIVE-ESTIMATE files=\(estimate.candidateFiles) candidate=\(estimate.candidateBytes) shared=\(estimate.sharedFiles) saved≈\(estimate.estimatedSavedBytes) ratio=\(estimate.sampleRatio) seconds≈\(Int(estimate.estimatedSeconds)) took=\(Int(Date().timeIntervalSince(started)))s")
    }
}

/// Really compresses a real folder in place: `MACPOCKET_LIVE_SHRINK_RUN=/path swift test --filter
/// liveShrinkRun`.
@Suite struct SystemDataLiveShrinkRunTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPOCKET_LIVE_SHRINK_RUN"] != nil))
    func liveShrinkRun() async throws {
        let folder = try #require(ProcessInfo.processInfo.environment["MACPOCKET_LIVE_SHRINK_RUN"])
        let started = Date()
        let result = try await SystemDataShrinker().shrink(folder: folder)
        print("LIVE-SHRINK before=\(result.beforeBytes) after=\(result.afterBytes) saved=\(result.savedBytes) compressed=\(result.filesCompressed) skipped=\(result.filesSkipped) took=\(Int(Date().timeIntervalSince(started)))s")
    }
}

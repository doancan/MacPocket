import XCTest
@testable import MacPocketCore

/// Read-only checks against the real home folder. Nothing is moved or deleted: only scanners run.
/// Skipped unless `MACPOCKET_REAL_SYSTEM_CHECK=1`, because results depend on the machine.
final class StorageRealSystemTests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["MACPOCKET_REAL_SYSTEM_CHECK"] == "1" }
    private let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

    private func line(_ text: String) { print("[real-system] " + text) }
    private func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    func testOverviewFinishesWithinBounds() async throws {
        try XCTSkipUnless(enabled)
        let options = StorageOverviewOptions(home: home)
        let control = StorageScanControl(maximumDuration: 60, maximumEntries: 5_000_000)
        let started = Date()
        let report = try await StorageOverviewScanner().scan(options, control: control)
        let elapsed = Date().timeIntervalSince(started)
        line("overview \(String(format: "%.1f", elapsed)) s, entries \(control.snapshot.visitedEntries), partial \(report.isPartial), limit \(report.limitReached)")
        line("volume used \(mb(report.volume.usedBytes)) of \(mb(report.volume.totalBytes)), purgeable \(mb(report.volume.purgeableBytes))")
        for usage in report.categories {
            line("  \(usage.category.title): \(mb(usage.bytes)), files \(usage.measurement.fileCount), inaccessible \(usage.measurement.inaccessibleCount), top \(usage.largestItems.prefix(3).map { ($0.path as NSString).lastPathComponent })")
        }
        line("  Sistem ve Diğer: \(mb(report.systemAndOtherBytes))")
        XCTAssertLessThan(elapsed, 75, "Bounded by the 60 s budget plus the walk in flight")
        XCTAssertGreaterThan(report.categories.first { $0.category == .applications }?.bytes ?? 0, 0)
        XCTAssertGreaterThan(report.volume.usedBytes, 0)
        XCTAssertLessThanOrEqual(report.measuredBytes, report.volume.totalBytes)
    }

    func testCleanupScanFinishesAndIsReadOnly() async throws {
        try XCTSkipUnless(enabled)
        let targets = CleanupCatalog.targets(home: home)
        let control = StorageScanControl(maximumDuration: 45, maximumEntries: 2_000_000)
        let started = Date()
        let report = try await CleanupScanner().scan(targets, running: [], control: control)
        let elapsed = Date().timeIntervalSince(started)
        line("cleanup \(String(format: "%.1f", elapsed)) s, items \(report.itemCount), total \(mb(report.bytes)), limit \(report.limitReached)")
        for target in report.targets {
            let preselected = target.items.filter(\.preselected).reduce(Int64(0)) { $0 + $1.bytes }
            line("  \(target.target.title): \(target.state), \(target.items.count) items, \(mb(target.bytes)), preselected \(mb(preselected)), review \(target.items.filter { $0.safety == .review }.count)")
        }
        XCTAssertLessThan(elapsed, 60)
        for target in report.targets {
            for item in target.items {
                XCTAssertEqual(item.url.deletingLastPathComponent().path, item.root.path)
                XCTAssertFalse(item.identity.isSymbolicLink)
                if target.target.isTrash || target.target.id == .xcodeArchives || target.target.id == .oldDownloads {
                    XCTAssertFalse(item.preselected)
                }
                if target.target.id == .userCaches, item.name.hasPrefix("com.apple.") {
                    XCTAssertEqual(item.safety, .review)
                    XCTAssertFalse(item.preselected)
                }
            }
        }
    }

    func testSpaceLensOnHomeFinishesWithinBounds() async throws {
        try XCTSkipUnless(enabled)
        let options = SpaceLensOptions()
        let control = StorageScanControl(maximumDuration: 45, maximumEntries: 5_000_000)
        let started = Date()
        let report = try await SpaceLensScanner().scan(home, options: options, control: control)
        let elapsed = Date().timeIntervalSince(started)
        func count(_ node: SpaceLensNode) -> Int { 1 + (node.children ?? []).reduce(0) { $0 + count($1) } }
        line("space lens \(String(format: "%.1f", elapsed)) s, entries \(report.visitedEntries), retained nodes \(count(report.root)), total \(mb(report.root.allocatedBytes)), complete \(report.root.complete), limit \(report.limitReached)")
        for child in (report.root.children ?? []).prefix(8) {
            line("  \(child.name): \(mb(child.allocatedBytes)) \(child.kind.rawValue) complete \(child.complete)")
        }
        XCTAssertLessThan(elapsed, 60)
        XCTAssertGreaterThan(report.root.allocatedBytes, 0)
        XCTAssertLessThanOrEqual(count(report.root), options.maximumRetainedNodes + 2_000)
        let childSum = (report.root.children ?? []).reduce(Int64(0)) { $0 + $1.allocatedBytes }
        XCTAssertLessThanOrEqual(childSum, report.root.allocatedBytes)
    }
}

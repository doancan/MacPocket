import Darwin
import XCTest
@testable import MacPocketCore

/// Temp-directory fixtures shared by the storage tests.
class StorageFixtureCase: XCTestCase {
    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try canonicalFileURL(root)
    }

    @discardableResult
    func write(_ url: URL, bytes count: Int, byte: UInt8 = 0x41) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: byte, count: count).write(to: url)
        return url
    }

    func directory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `st_blocks * 512`, the allocated size the scanners must report.
    func allocated(_ url: URL) -> Int64 {
        var info = stat()
        XCTAssertEqual(lstat(url.path, &info), 0)
        return Int64(info.st_blocks) * 512
    }

    func control(seconds: TimeInterval = 30, entries: Int = 1_000_000) -> StorageScanControl {
        StorageScanControl(maximumDuration: seconds, maximumEntries: entries)
    }
}

final class StorageScanningTests: StorageFixtureCase {
    func testMeasuresAllocatedSizeIncludingDirectoryBlocks() throws {
        let root = try fixture()
        let a = try write(root.appendingPathComponent("a.bin"), bytes: 10_000)
        let nested = try directory(root.appendingPathComponent("nested"))
        let b = try write(nested.appendingPathComponent("b.bin"), bytes: 70_000)
        let result = DirectorySizer.measure(root.path, control: control(), links: HardLinkRegistry())
        let expected = allocated(root) + allocated(a) + allocated(nested) + allocated(b)
        XCTAssertEqual(result.allocatedBytes, expected)
        XCTAssertEqual(result.logicalBytes, 80_000)
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(result.directoryCount, 2)
        XCTAssertTrue(result.complete)
        XCTAssertGreaterThanOrEqual(allocated(a), 10_000, "Allocated size rounds up to blocks")
    }

    func testSparseFileUsesAllocatedNotLogicalSize() throws {
        let root = try fixture()
        let url = root.appendingPathComponent("sparse")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 512 * 1_048_576)
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        let result = DirectorySizer.measure(root.path, control: control(), links: HardLinkRegistry())
        XCTAssertEqual(result.logicalBytes, 512 * 1_048_576 + 1)
        XCTAssertLessThan(result.allocatedBytes, 16 * 1_048_576, "A sparse file must not count its holes")
    }

    func testHardLinksCountOnceAndSymlinksAreNotFollowed() throws {
        let root = try fixture()
        let data = try write(root.appendingPathComponent("data"), bytes: 50_000)
        try FileManager.default.linkItem(at: data, to: root.appendingPathComponent("hard-link"))
        let outside = try fixture()
        try write(outside.appendingPathComponent("big"), bytes: 2_000_000)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dir-link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("file-link"),
                                                   withDestinationURL: outside.appendingPathComponent("big"))
        let result = DirectorySizer.measure(root.path, control: control(), links: HardLinkRegistry())
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.allocatedBytes, allocated(root) + allocated(data))
        XCTAssertEqual(result.skippedLinks, 2)
    }

    func testSharedRegistryCountsHardLinkOnceAcrossWalks() throws {
        let root = try fixture()
        let a = try directory(root.appendingPathComponent("a"))
        let b = try directory(root.appendingPathComponent("b"))
        let data = try write(a.appendingPathComponent("data"), bytes: 40_000)
        try FileManager.default.linkItem(at: data, to: b.appendingPathComponent("same"))
        let links = HardLinkRegistry()
        let first = DirectorySizer.measure(a.path, control: control(), links: links)
        let second = DirectorySizer.measure(b.path, control: control(), links: links)
        XCTAssertEqual(first.fileCount + second.fileCount, 1)
    }

    func testSymlinkRootIsNotFollowed() throws {
        let root = try fixture()
        let target = try directory(root.appendingPathComponent("target"))
        try write(target.appendingPathComponent("x"), bytes: 100_000)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let result = DirectorySizer.measure(link.path, control: control(), links: HardLinkRegistry())
        XCTAssertEqual(result.allocatedBytes, 0)
        XCTAssertEqual(result.skippedLinks, 1)
    }

    func testEntryBudgetStopsAndMarksPartial() throws {
        let root = try fixture()
        for index in 0..<1_200 { try write(root.appendingPathComponent("f\(index)"), bytes: 1) }
        let limited = control(entries: 300)
        let result = DirectorySizer.measure(root.path, control: limited, links: HardLinkRegistry())
        XCTAssertFalse(result.complete)
        XCTAssertTrue(limited.limitReached)
        XCTAssertLessThan(result.fileCount, 1_200)
    }

    func testCancellationStopsWalk() throws {
        let root = try fixture()
        for index in 0..<600 { try write(root.appendingPathComponent("f\(index)"), bytes: 1) }
        let cancelled = control()
        cancelled.cancel()
        let result = DirectorySizer.measure(root.path, control: cancelled, links: HardLinkRegistry())
        XCTAssertFalse(result.complete)
        XCTAssertLessThan(result.fileCount, 600)
    }

    func testUnreadableFolderIsCountedAndMarksPartial() throws {
        let root = try fixture()
        let locked = try directory(root.appendingPathComponent("locked"))
        try write(locked.appendingPathComponent("secret"), bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let result = DirectorySizer.measure(root.path, control: control(), links: HardLinkRegistry())
        XCTAssertEqual(result.inaccessibleCount, 1)
        XCTAssertFalse(result.complete)
    }

    func testVolumeCapacityIsReadable() throws {
        let volume = try VolumeCapacity.read()
        XCTAssertGreaterThan(volume.totalBytes, 0)
        XCTAssertGreaterThan(volume.usedBytes, 0)
        XCTAssertLessThanOrEqual(volume.availableBytes, volume.totalBytes)
        XCTAssertGreaterThanOrEqual(volume.importantAvailableBytes, volume.availableBytes)
    }
}

final class StorageOverviewTests: StorageFixtureCase {
    private func options(home: URL, volumeUsed: Int64) -> StorageOverviewOptions {
        var options = StorageOverviewOptions(home: home)
        // /Applications is a real system path; it is exercised by the real-system check instead.
        options.categories = StorageCategory.allCases.filter { $0 != .system && $0 != .applications }
        options.volume = VolumeCapacity(name: "Test", totalBytes: volumeUsed * 4, availableBytes: volumeUsed * 3,
                                        importantAvailableBytes: volumeUsed * 3)
        return options
    }

    func testCategoriesAggregateWithoutDoubleCounting() async throws {
        let home = try fixture()
        let document = try write(home.appendingPathComponent("Documents/report.pdf"), bytes: 120_000)
        try write(home.appendingPathComponent("Desktop/note.txt"), bytes: 30_000)
        try write(home.appendingPathComponent("Library/Caches/com.example.app/blob"), bytes: 200_000)
        // Homebrew's cache belongs to Geliştirici only, although it lives under ~/Library/Caches.
        try write(home.appendingPathComponent("Library/Caches/Homebrew/downloads/pkg.tar.gz"), bytes: 300_000)
        try write(home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o"), bytes: 400_000)
        try write(home.appendingPathComponent("Library/Logs/app.log"), bytes: 10_000)
        try write(home.appendingPathComponent("Downloads/installer.dmg"), bytes: 500_000)
        try write(home.appendingPathComponent(".Trash/old.zip"), bytes: 60_000)
        // A hard link of a document inside Downloads must count once overall.
        try FileManager.default.linkItem(at: document, to: home.appendingPathComponent("Downloads/report-link.pdf"))
        // A symlink to a big file outside home is not followed.
        let outside = try fixture()
        try write(outside.appendingPathComponent("huge"), bytes: 3_000_000)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Documents/huge-link"),
                                                   withDestinationURL: outside.appendingPathComponent("huge"))
        // Photos library: a package with many files, reported as one item.
        // Everything else in home counts as other user files, except the rest of ~/Library.
        try write(home.appendingPathComponent("Projects/app/main.swift"), bytes: 25_000)
        try write(home.appendingPathComponent(".config/tool/settings.json"), bytes: 2_000)
        try write(home.appendingPathComponent("Library/Containers/com.example/Data/blob"), bytes: 900_000)
        let library = try directory(home.appendingPathComponent("Pictures/Photos Library.photoslibrary"))
        for index in 0..<5 { try write(library.appendingPathComponent("originals/\(index).heic"), bytes: 80_000) }

        let report = try await StorageOverviewScanner().scan(options(home: home, volumeUsed: 100_000_000), control: control())
        func usage(_ category: StorageCategory) throws -> StorageCategoryUsage {
            try XCTUnwrap(report.categories.first { $0.category == category })
        }
        let documents = try usage(.documents)
        // Categories run in parallel, so the hard-linked report may be attributed to either category.
        XCTAssertGreaterThanOrEqual(documents.measurement.fileCount, 1)
        XCTAssertEqual(documents.measurement.skippedLinks, 1)
        XCTAssertLessThan(documents.bytes, 1_000_000, "The symlinked 3 MB file must not be counted")
        let caches = try usage(.caches)
        XCTAssertEqual(caches.measurement.fileCount, 1, "Homebrew is pruned from caches")
        XCTAssertEqual(caches.largestItems.map { ($0.path as NSString).lastPathComponent }, ["com.example.app"])
        let developer = try usage(.developer)
        XCTAssertEqual(developer.measurement.fileCount, 2)
        XCTAssertGreaterThanOrEqual(developer.bytes, 700_000)
        let downloads = try usage(.downloads)
        XCTAssertEqual(downloads.measurement.fileCount + documents.measurement.fileCount, 3,
                       "The hard link is counted in exactly one category")
        let photos = try usage(.photos)
        XCTAssertEqual(photos.largestItems.count, 1)
        XCTAssertEqual(photos.largestItems.first?.isPackage, true)
        XCTAssertGreaterThanOrEqual(photos.bytes, 400_000)
        XCTAssertEqual(try usage(.trash).measurement.fileCount, 1)
        XCTAssertEqual(try usage(.media).bytes, 0, "Missing roots are skipped")
        let other = try usage(.otherUser)
        XCTAssertEqual(other.measurement.fileCount, 2, "Projects and .config, never ~/Library or other categories")
        XCTAssertEqual(Set(other.largestItems.map { ($0.path as NSString).lastPathComponent }), ["Projects", ".config"])
        XCTAssertLessThan(other.bytes, 900_000)

        // Every file of the fixture is attributed exactly once.
        let totalFiles = report.categories.reduce(0) { $0 + $1.measurement.fileCount }
        XCTAssertEqual(totalFiles, 3 + 1 + 2 + 1 + 1 + 5 + 2, "The ~/Library/Containers file is left to Sistem ve Diğer")
        XCTAssertEqual(report.systemAndOtherBytes, 100_000_000 - report.measuredBytes)
        XCTAssertEqual(report.segments.last?.category, .system)
        XCTAssertFalse(report.isPartial)
    }

    func testSystemAndOtherCanBeRecomputedAgainstLiveUsedSpace() async throws {
        let home = try fixture()
        let report = try await StorageOverviewScanner().scan(options(home: home, volumeUsed: 10_000_000), control: control())
        XCTAssertEqual(report.systemAndOtherBytes(usedBytes: 10_000_000), report.systemAndOtherBytes)
        XCTAssertEqual(report.systemAndOtherBytes(usedBytes: report.measuredBytes + 5), 5)
        XCTAssertEqual(report.systemAndOtherBytes(usedBytes: 0), 0, "never negative")
        XCTAssertEqual(report.segments(usedBytes: report.measuredBytes + 5).last?.bytes, 5)
    }

    func testCategoryRootThatIsSymlinkIsSkipped() async throws {
        let home = try fixture()
        let elsewhere = try fixture()
        try write(elsewhere.appendingPathComponent("big"), bytes: 1_000_000)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Downloads"), withDestinationURL: elsewhere)
        let report = try await StorageOverviewScanner().scan(options(home: home, volumeUsed: 10_000_000), control: control())
        let downloads = try XCTUnwrap(report.categories.first { $0.category == .downloads })
        XCTAssertEqual(downloads.bytes, 0)
        XCTAssertTrue(downloads.measuredRoots.isEmpty)
    }

    func testBudgetMarksReportPartial() async throws {
        let home = try fixture()
        for index in 0..<2_000 { try write(home.appendingPathComponent("Documents/f\(index)"), bytes: 1) }
        let report = try await StorageOverviewScanner().scan(options(home: home, volumeUsed: 10_000_000),
                                                             control: control(entries: 500))
        XCTAssertTrue(report.limitReached)
        XCTAssertTrue(report.isPartial)
    }

    func testCancelledScanThrows() async throws {
        let home = try fixture()
        try write(home.appendingPathComponent("Documents/a"), bytes: 1)
        let cancelled = control()
        cancelled.cancel()
        do {
            _ = try await StorageOverviewScanner().scan(options(home: home, volumeUsed: 1_000_000), control: cancelled)
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    func testTaskCancellationIsForwarded() async throws {
        let home = try fixture()
        for index in 0..<3_000 { try write(home.appendingPathComponent("Documents/d\(index % 30)/f\(index)"), bytes: 1) }
        let scanControl = control()
        let scanOptions = options(home: home, volumeUsed: 1_000_000)
        let task = Task { try await StorageOverviewScanner().scan(scanOptions, control: scanControl) }
        task.cancel()
        _ = try? await task.value
        XCTAssertTrue(scanControl.isCancelled)
    }

    func testCacheRoundTrip() async throws {
        let home = try fixture()
        try write(home.appendingPathComponent("Documents/a"), bytes: 5_000)
        let report = try await StorageOverviewScanner().scan(options(home: home, volumeUsed: 1_000_000), control: control())
        let cache = StorageOverviewCache(url: home.appendingPathComponent("cache/overview.json"))
        XCTAssertNil(cache.load())
        try cache.save(report)
        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.categories, report.categories)
        XCTAssertEqual(loaded.volume, report.volume)
        XCTAssertEqual(loaded.scannedAt.timeIntervalSince1970, report.scannedAt.timeIntervalSince1970, accuracy: 0.001)
        try Data("garbage".utf8).write(to: cache.url)
        XCTAssertNil(cache.load(), "A corrupt cache is ignored, not fatal")
    }
}

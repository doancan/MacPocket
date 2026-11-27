import CoreGraphics
import XCTest
@testable import MacPocketCore

final class SpaceLensTests: StorageFixtureCase {
    private func scan(_ root: URL, _ configure: (inout SpaceLensOptions) -> Void = { _ in },
                      control scanControl: StorageScanControl? = nil) async throws -> SpaceLensReport {
        var options = SpaceLensOptions()
        configure(&options)
        return try await SpaceLensScanner().scan(root, options: options, control: scanControl ?? control())
    }

    private func sum(_ nodes: [SpaceLensNode]?) -> Int64 { (nodes ?? []).reduce(0) { $0 + $1.allocatedBytes } }

    func testSizesRollUpAndMatchDirectorySizer() async throws {
        let root = try fixture()
        try write(root.appendingPathComponent("a/b/big.mov"), bytes: 900_000)
        try write(root.appendingPathComponent("a/small.txt"), bytes: 4_000)
        try write(root.appendingPathComponent("top.zip"), bytes: 300_000)
        let report = try await scan(root)
        let tree = report.root
        XCTAssertEqual(tree.allocatedBytes, DirectorySizer.measure(root.path, control: control(), links: HardLinkRegistry()).allocatedBytes)
        XCTAssertEqual(tree.fileCount, 3)
        XCTAssertTrue(tree.complete)
        XCTAssertEqual(tree.children?.map(\.name), ["a", "top.zip"], "Children are sorted by size")
        // A folder's size is its own blocks plus its children.
        let a = try XCTUnwrap(tree.node(at: root.appendingPathComponent("a").path))
        XCTAssertEqual(a.allocatedBytes, allocated(root.appendingPathComponent("a")) + sum(a.children))
        XCTAssertEqual(tree.allocatedBytes, allocated(root) + sum(tree.children))
        XCTAssertEqual(tree.node(at: root.appendingPathComponent("a/b/big.mov").path)?.kind, .video)
        XCTAssertEqual(tree.node(at: root.appendingPathComponent("top.zip").path)?.kind, .archive)
        XCTAssertNotNil(tree.node(at: root.appendingPathComponent("top.zip").path)?.identity, "Retained nodes carry an identity for Trash")
    }

    func testPackageIsOneOpaqueNode() async throws {
        let root = try fixture()
        for index in 0..<4 { try write(root.appendingPathComponent("Tool.app/Contents/Resources/r\(index)"), bytes: 50_000) }
        let report = try await scan(root)
        let app = try XCTUnwrap(report.root.children?.first { $0.name == "Tool.app" })
        XCTAssertEqual(app.kind, .package)
        XCTAssertNil(app.children, "Package internals are never exposed")
        XCTAssertFalse(app.needsExpansion)
        XCTAssertEqual(app.fileCount, 4)
        XCTAssertGreaterThanOrEqual(app.allocatedBytes, 200_000)
    }

    func testRetainedDepthLeavesDeeperFoldersForExpansion() async throws {
        let root = try fixture()
        try write(root.appendingPathComponent("one/two/three/file"), bytes: 10_000)
        let report = try await scan(root) { $0.retainedDepth = 1 }
        let one = try XCTUnwrap(report.root.children?.first)
        XCTAssertTrue(one.needsExpansion)
        XCTAssertGreaterThanOrEqual(one.allocatedBytes, 10_000, "Unretained levels still contribute their size")
        // Drill-down rescans the folder and grafts it into the tree.
        let deeper = try await scan(one.url)
        let grafted = report.root.replacing(one.path, with: deeper.root)
        XCTAssertNotNil(grafted.node(at: root.appendingPathComponent("one/two/three/file").path))
        XCTAssertEqual(grafted.node(at: one.path)?.allocatedBytes, deeper.root.allocatedBytes)
    }

    func testWideFolderFoldsSmallItemsIntoRemainder() async throws {
        let root = try fixture()
        for index in 0..<10 { try write(root.appendingPathComponent("f\(index)"), bytes: (index + 1) * 20_000) }
        let report = try await scan(root) { $0.childrenPerFolder = 3 }
        let children = try XCTUnwrap(report.root.children)
        XCTAssertEqual(children.count, 4)
        let remainder = try XCTUnwrap(children.first { $0.kind == .remainder })
        XCTAssertEqual(remainder.fileCount, 7)
        XCTAssertNil(remainder.identity, "Synthetic nodes can never be moved to Trash")
        XCTAssertEqual(Set(children.filter { $0.kind != .remainder }.map(\.name)), ["f9", "f8", "f7"])
        XCTAssertEqual(report.root.allocatedBytes, allocated(root) + sum(children), "Folding preserves the total")
    }

    func testSymlinksNotFollowedAndHardLinksCountedOnce() async throws {
        let root = try fixture()
        let data = try write(root.appendingPathComponent("data"), bytes: 100_000)
        try FileManager.default.linkItem(at: data, to: root.appendingPathComponent("link"))
        let outside = try fixture()
        try write(outside.appendingPathComponent("huge"), bytes: 2_000_000)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: outside)
        let report = try await scan(root)
        XCTAssertEqual(report.root.fileCount, 1)
        XCTAssertEqual(report.root.children?.count, 1)
        XCTAssertLessThan(report.root.allocatedBytes, 1_000_000)
    }

    func testRemovingUpdatesAncestorSizes() async throws {
        let root = try fixture()
        let doomed = try write(root.appendingPathComponent("a/doomed.bin"), bytes: 400_000)
        try write(root.appendingPathComponent("a/kept.bin"), bytes: 100_000)
        let tree = try await scan(root).root
        let before = tree.allocatedBytes
        let updated = tree.removing([doomed.path])
        XCTAssertNil(updated.node(at: doomed.path))
        XCTAssertEqual(updated.allocatedBytes, before - allocated(doomed))
        XCTAssertEqual(updated.fileCount, 1)
        XCTAssertEqual(updated.node(at: root.appendingPathComponent("a").path)?.children?.count, 1)
    }

    func testBudgetProducesHonestPartialTree() async throws {
        let root = try fixture()
        for index in 0..<3_000 { try write(root.appendingPathComponent("d\(index % 2)/f\(index)"), bytes: 1) }
        let limited = control(entries: 600)
        let report = try await scan(root, control: limited)
        XCTAssertTrue(report.limitReached)
        XCTAssertFalse(report.root.complete)
        XCTAssertLessThan(report.root.fileCount, 3_000)
        XCTAssertGreaterThan(report.root.fileCount, 0, "Partial sizes still roll up")
    }

    /// Regression: an unreadable folder used to leave the builder stack unbalanced, so siblings were
    /// nested under it and the parent vanished from the tree.
    func testUnreadableFolderKeepsTreeStructure() async throws {
        let root = try fixture()
        try write(root.appendingPathComponent("parent/a-before/file"), bytes: 50_000)
        let locked = try directory(root.appendingPathComponent("parent/locked"))
        try write(locked.appendingPathComponent("secret"), bytes: 10)
        try write(root.appendingPathComponent("parent/z-after/file"), bytes: 80_000)
        try write(root.appendingPathComponent("sibling/file"), bytes: 20_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        for tree in [try await scan(root).root,
                     try XCTUnwrap(SpaceLensScanner.build(root.path, options: .init(), control: control()))] {
            XCTAssertEqual(Set(tree.children?.map(\.name) ?? []), ["parent", "sibling"])
            let parent = try XCTUnwrap(tree.node(at: root.appendingPathComponent("parent").path))
            XCTAssertEqual(Set(parent.children?.map(\.name) ?? []), ["a-before", "locked", "z-after"])
            let lockedNode = try XCTUnwrap(parent.children?.first { $0.name == "locked" })
            XCTAssertFalse(lockedNode.complete)
            XCTAssertEqual(lockedNode.inaccessibleCount, 1)
            XCTAssertFalse(parent.complete)
            XCTAssertEqual(tree.inaccessibleCount, 1)
            XCTAssertEqual(tree.fileCount, 3)
            XCTAssertTrue(try XCTUnwrap(tree.node(at: root.appendingPathComponent("sibling").path)).complete)
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Regression: fts reports FTS_DP for a skipped mount point; hiding only its FTS_D unbalanced the tree
    /// (on a real home, ~/Library disappeared and one of its children showed up at the top level).
    func testOtherVolumeIsSkippedWithoutBreakingTree() async throws {
        let root = try fixture()
        let image = root.appendingPathComponent("vol.dmg")
        let mountPoint = try directory(root.appendingPathComponent("parent/mnt"))
        guard try Self.run("/usr/bin/hdiutil", ["create", "-size", "2m", "-fs", "HFS+", "-volname", "MPTest", image.path]) == 0,
              try Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noverify", "-mountpoint", mountPoint.path, image.path]) == 0 else {
            throw XCTSkip("hdiutil is unavailable")
        }
        addTeardownBlock { _ = try? Self.run("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path]) }
        try write(mountPoint.appendingPathComponent("on-other-volume"), bytes: 500_000)
        try write(root.appendingPathComponent("parent/z-after/file"), bytes: 30_000)
        try write(root.appendingPathComponent("sibling/file"), bytes: 20_000)
        try FileManager.default.removeItem(at: image)
        for tree in [try await scan(root).root,
                     try XCTUnwrap(SpaceLensScanner.build(root.path, options: .init(), control: control()))] {
            XCTAssertEqual(Set(tree.children?.map(\.name) ?? []), ["parent", "sibling"])
            let parent = try XCTUnwrap(tree.node(at: root.appendingPathComponent("parent").path))
            XCTAssertEqual(parent.children?.map(\.name), ["z-after"], "The mount point is not measured")
            XCTAssertEqual(tree.fileCount, 2)
        }
        let measured = DirectorySizer.measure(root.path, control: control(), links: HardLinkRegistry())
        XCTAssertEqual(measured.fileCount, 2)
    }

    func testRetainedNodesPassTrashValidationAndPackagesStayProtected() async throws {
        let root = try fixture()
        try write(root.appendingPathComponent("folder/inner/file.bin"), bytes: 40_000)
        let loose = try write(root.appendingPathComponent("loose.zip"), bytes: 20_000)
        try write(root.appendingPathComponent("Tool.app/Contents/Info.plist"), bytes: 1_000)
        let tree = try await scan(root).root
        func all(_ node: SpaceLensNode) -> [SpaceLensNode] { [node] + (node.children ?? []).flatMap(all) }
        let candidates = all(tree).filter { $0.path != tree.path && $0.kind != .remainder }
        XCTAssertFalse(candidates.isEmpty)
        for node in candidates {
            let identity = try XCTUnwrap(node.identity, "\(node.path) needs an identity to be trashable")
            XCTAssertNoThrow(try FileTrashRequest(url: node.url, identity: identity, root: tree.url).validate(), node.path)
        }
        XCTAssertNil(tree.node(at: root.appendingPathComponent("Tool.app/Contents").path), "Package internals are never offered")
        // A forged request for a package interior is still refused by the shared validation.
        let interior = root.appendingPathComponent("Tool.app/Contents/Info.plist")
        XCTAssertThrowsError(try FileTrashRequest(url: interior, identity: try FileIdentity.read(interior), root: tree.url).validate()) {
            XCTAssertEqual($0 as? FileServiceError, .insidePackage)
        }
        // The scanned root itself is never a valid target.
        XCTAssertThrowsError(try FileTrashRequest(url: tree.url, identity: try XCTUnwrap(tree.identity), root: tree.url).validate())
        // A file changed after the scan is refused.
        let looseNode = try XCTUnwrap(tree.node(at: loose.path))
        try write(loose, bytes: 30_000)
        XCTAssertThrowsError(try FileTrashRequest(url: loose, identity: try XCTUnwrap(looseNode.identity), root: tree.url).validate()) {
            XCTAssertEqual($0 as? FileServiceError, .changed)
        }
    }

    func testRejectsFilesAndSymlinkRootsResolveToTarget() async throws {
        let root = try fixture()
        let file = try write(root.appendingPathComponent("file"), bytes: 10)
        do {
            _ = try await scan(file)
            XCTFail("A file cannot be a Space Lens root")
        } catch let error as FileServiceError { XCTAssertEqual(error, .notDirectory) }
    }

    func testCancellationThrows() async throws {
        let root = try fixture()
        try write(root.appendingPathComponent("x"), bytes: 10)
        let cancelled = control()
        cancelled.cancel()
        do {
            _ = try await scan(root, control: cancelled)
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }
}

final class TreemapTests: XCTestCase {
    private func assertValidLayout(_ values: [Double], in bounds: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let rects = Treemap.layout(values, in: bounds)
        XCTAssertEqual(rects.count, values.count, file: file, line: line)
        let total = values.reduce(0) { $0 + max(0, $1) }
        let area = Double(bounds.width * bounds.height)
        var covered = 0.0
        for (index, rect) in rects.enumerated() {
            let value = max(0, values[index])
            if value == 0 { XCTAssertEqual(rect, .zero, file: file, line: line); continue }
            let expected = value / total * area
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: max(1e-6, expected * 1e-6),
                           "Area of item \(index) is proportional to its value", file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minX, bounds.minX - 1e-6, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minY, bounds.minY - 1e-6, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX + 1e-6, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxY, bounds.maxY + 1e-6, file: file, line: line)
            covered += Double(rect.width * rect.height)
        }
        XCTAssertEqual(covered, area, accuracy: area * 1e-9, "The rectangles tile the bounds", file: file, line: line)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                let overlapArea = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
                XCTAssertLessThan(overlapArea, 1e-6, "Items \(i) and \(j) overlap", file: file, line: line)
            }
        }
    }

    func testAreasProportionalNoOverlapWithinBounds() {
        assertValidLayout([6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
        assertValidLayout([1], in: CGRect(x: 10, y: 20, width: 300, height: 200))
        assertValidLayout([5, 0, 3, 0, 1], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        assertValidLayout([1_000_000, 1, 1, 1], in: CGRect(x: 5, y: 5, width: 800, height: 300))
    }

    func testRandomizedLayouts() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<60 {
            let count = Int.random(in: 1...120, using: &generator)
            let values = (0..<count).map { _ in Double.random(in: 0...1, using: &generator) < 0.1 ? 0 : Double.random(in: 1...1e9, using: &generator) }
            let bounds = CGRect(x: Double.random(in: -50...50, using: &generator), y: Double.random(in: -50...50, using: &generator),
                                width: Double.random(in: 10...1600, using: &generator), height: Double.random(in: 10...900, using: &generator))
            assertValidLayout(values, in: bounds)
        }
    }

    func testSquarifiedAspectRatiosStayReasonable() {
        let rects = Treemap.layout(Array(repeating: 1, count: 16), in: CGRect(x: 0, y: 0, width: 400, height: 400))
        for rect in rects {
            XCTAssertLessThanOrEqual(max(rect.width / rect.height, rect.height / rect.width), 2.01)
        }
    }

    func testPreservesInputOrderMapping() {
        let rects = Treemap.layout([1, 9], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(Double(rects[0].width * rects[0].height), 1_000, accuracy: 1e-6)
        XCTAssertEqual(Double(rects[1].width * rects[1].height), 9_000, accuracy: 1e-6)
    }

    func testDegenerateInputs() {
        XCTAssertEqual(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [])
        XCTAssertEqual(Treemap.layout([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [.zero, .zero])
        XCTAssertEqual(Treemap.layout([1, 2], in: .zero), [.zero, .zero])
        XCTAssertEqual(Treemap.layout([-5, 5], in: CGRect(x: 0, y: 0, width: 10, height: 10))[0], .zero)
    }
}

/// Deterministic generator so randomized layout tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd
        return z ^ (z >> 33)
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacPocketCore

final class SimilarImagesTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-image-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try canonicalFileURL(root)
    }
    private func image(_ url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 192, bitsPerComponent: 8, bytesPerRow: 1024,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
        for index in 0..<10 {
            context.setFillColor(CGColor(red: CGFloat(index) / 10, green: 0.8, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: index * 20, y: (index % 3) * 50, width: 50, height: 50))
        }
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
    }
    func testImageOnlyRetentionCannotBeCrowdedOutByLargeNonImageFile() async throws {
        let root = try fixture()
        try image(root.appendingPathComponent("sample.PNG"))
        try Data(repeating: 65, count: 100_000).write(to: root.appendingPathComponent("large.txt"))
        var options = FileScanOptions(); options.maximumRetainedFiles = 1; options.allowedExtensions = ["PNG"]
        let report = try await FileScanner().scan(root, options: options)
        XCTAssertEqual(report.fileCount, 1)
        XCTAssertEqual(report.files.first?.url.lastPathComponent, "sample.PNG")
        XCTAssertTrue(report.retainedAllFiles)
        let unfiltered = try await FileScanner().scan(root)
        XCTAssertEqual(unfiltered.fileCount, 2)
    }
    func testThumbnailIsBoundedAndChangedInputRejected() throws {
        let root = try fixture(); let url = root.appendingPathComponent("sample.png")
        try image(url)
        let file = ScannedFile(url: url, identity: try .read(url))
        let thumbnail = try SimilarImagesService.thumbnail(for: file, maximumPixelSize: 64)
        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 64)
        try Data("changed".utf8).write(to: url)
        XCTAssertThrowsError(try SimilarImagesService.thumbnail(for: file))
    }
    func testVisionFindsOwnedIdenticalImagePairAndReportsRetentionLimit() async throws {
        let root = try fixture(); let original = root.appendingPathComponent("a.png")
        try image(original)
        try FileManager.default.copyItem(at: original, to: root.appendingPathComponent("b.png"))
        try FileManager.default.copyItem(at: original, to: root.appendingPathComponent("c.png"))
        var options = SimilarImagesOptions(); options.maximumImages = 2; options.distanceThreshold = 0.3
        let report = try await SimilarImagesService().scan(root, options: options)
        XCTAssertEqual(report.discoveredImages, 3)
        XCTAssertEqual(report.analyzedImages, 2, report.issues.joined(separator: "\n"))
        XCTAssertTrue(report.partial)
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups.first?.matches.count, 1)
        XCTAssertEqual(try XCTUnwrap(report.groups.first?.matches.first?.distance), 0, accuracy: 0.0001)
    }
    func testCorruptSupportedFileIsExplicitlySkipped() async throws {
        let root = try fixture(); try Data("not an image".utf8).write(to: root.appendingPathComponent("bad.png"))
        let report = try await SimilarImagesService().scan(root)
        XCTAssertEqual(report.discoveredImages, 1)
        XCTAssertEqual(report.analyzedImages, 0)
        XCTAssertEqual(report.skippedImages, 1)
        XCTAssertTrue(report.partial)
        XCTAssertFalse(report.issues.isEmpty)
    }
    func testCancelledScanDoesNotReadImagesOrProduceSuccess() async throws {
        let root = try fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SimilarImagesService().scan(root)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
}

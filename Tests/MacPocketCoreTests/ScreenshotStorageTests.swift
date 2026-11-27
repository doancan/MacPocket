import CoreGraphics
import ImageIO
import XCTest
@testable import MacPocketCore

final class ScreenshotStorageTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocketScreenshotTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testExclusiveAtomicWriterPreservesCollidingFilesAndCleansTemporaryFiles() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 100)
        let first = try ScreenshotFileWriter.write(Data("first".utf8), folder: dir, date: date, prefix: "Fixture", format: .png)
        let second = try ScreenshotFileWriter.write(Data("second".utf8), folder: dir, date: date, prefix: "Fixture", format: .png)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
    }
    func testConcurrentWritersNeverOverwriteEachOther() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try await withThrowingTaskGroup(of: URL.self) { group in
            for i in 0..<12 {
                group.addTask { try ScreenshotFileWriter.write(Data("\(i)".utf8), folder: dir, date: Date(timeIntervalSince1970: 10), prefix: "Parallel", format: .png) }
            }
            var result: [URL] = []
            for try await url in group { result.append(url) }
            return result
        }
        XCTAssertEqual(Set(files).count, 12)
        XCTAssertEqual(Set(try files.map { try String(contentsOf: $0, encoding: .utf8) }), Set((0..<12).map(String.init)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 12)
    }
    func testCancelledWriteDoesNotCreateAnything() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try ScreenshotFileWriter.write(Data("discard".utf8), folder: dir, date: Date(), prefix: "Cancelled", format: .png)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled write completed") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
    func testWriterRejectsNestedAndNullPrefixes() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for prefix in ["../escape", "", "bad\0name"] {
            XCTAssertThrowsError(try ScreenshotFileWriter.write(Data(), folder: dir, date: Date(), prefix: prefix, format: .png))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
    func testPinBudgetChecksInvalidAndOverflowingGeometry() {
        XCTAssertTrue(ScreenshotPinPolicy.allows(width: 1920, height: 1080, count: 0, usedPixels: 0))
        XCTAssertFalse(ScreenshotPinPolicy.allows(width: .max, height: .max, count: 0, usedPixels: 0))
        XCTAssertFalse(ScreenshotPinPolicy.allows(width: 1, height: 1, count: 8, usedPixels: 0))
        XCTAssertFalse(ScreenshotPinPolicy.allows(width: 0, height: 1, count: 0, usedPixels: 0))
        XCTAssertFalse(ScreenshotPinPolicy.allows(width: 2000, height: 1000, count: 1, usedPixels: 47_000_000))
    }
    func testPinFramesFitNegativeAndSmallDisplaysAndNonfiniteScale() {
        for screen in [CGRect(x: -1920, y: 300, width: 1920, height: 1080), CGRect(x: 0, y: -1080, width: 1280, height: 800), CGRect(x: 0, y: 0, width: 180, height: 160)] {
            for scale: CGFloat in [1, 2, .nan, .infinity] {
                let frame = ScreenshotPinPolicy.frame(pixels: CGSize(width: 2000, height: 40_000), scale: scale, visible: screen, anchor: CGPoint(x: 9000, y: -9000))
                XCTAssertTrue(screen.contains(frame))
                XCTAssertTrue(frame.width.isFinite)
                XCTAssertTrue(frame.height.isFinite)
            }
        }
    }
    func testEncoderStoresSourceScaleAsResolution() throws {
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        let data = try ScreenshotEncoder.encode(image, as: .png, scale: 2)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double), 144, accuracy: 0.1)
    }
}

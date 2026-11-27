import CoreGraphics
import CoreText
import XCTest
@testable import MacPocketCore

final class ScrollingScreenshotTests: XCTestCase {
    private func image(top: Int = 0, width: Int = 160, height: Int = 240, header: Int = 0, footer: Int = 0, period: Int? = nil) -> CGImage {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let documentY: Int
            if y < header { documentY = 100_000 + y }
            else if y >= height - footer { documentY = 200_000 + y - height + footer }
            else { documentY = (top + y - header) % (period ?? Int.max) }
            for x in 0..<width {
                let seed = (UInt32(truncatingIfNeeded: documentY) &* 2_654_435_761) ^ (UInt32(x) &* 2_246_822_519)
                let i = (y * width + x) * 4
                data[i] = UInt8(truncatingIfNeeded: seed >> 4)
                data[i + 1] = UInt8(truncatingIfNeeded: seed >> 12)
                data[i + 2] = UInt8(truncatingIfNeeded: seed >> 20)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    private func pixels(_ image: CGImage) -> Data { image.dataProvider!.data! as Data }

    func testDownwardOverlapPreservesEveryPixelAndOrientation() throws {
        var stitch = ScrollScreenshotStitcher()
        XCTAssertEqual(try stitch.append(image()), .started)
        XCTAssertEqual(try stitch.append(image(top: 80)), .appended(pixels: 80))
        XCTAssertEqual(try stitch.append(image(top: 170)), .appended(pixels: 90))
        let result = try stitch.render()
        XCTAssertEqual(result.width, 160)
        XCTAssertEqual(result.height, 410)
        XCTAssertEqual(pixels(result), pixels(image(height: 410)))
    }
    func testFixedHeaderAndFooterAppearOnce() throws {
        var stitch = ScrollScreenshotStitcher()
        _ = try stitch.append(image(header: 24, footer: 20))
        XCTAssertEqual(try stitch.append(image(top: 90, header: 24, footer: 20)), .appended(pixels: 90))
        XCTAssertEqual(try stitch.append(image(top: 160, header: 24, footer: 20)), .appended(pixels: 70))
        XCTAssertEqual(pixels(try stitch.render()), pixels(image(height: 400, header: 24, footer: 20)))
    }
    func testReverseAndReturnDoNotDuplicateContent() throws {
        var stitch = ScrollScreenshotStitcher()
        _ = try stitch.append(image(top: 100))
        _ = try stitch.append(image(top: 200))
        XCTAssertEqual(try stitch.append(image(top: 140)), .revisited)
        XCTAssertEqual(try stitch.append(image(top: 200)), .revisited)
        XCTAssertEqual(try stitch.append(image(top: 250)), .appended(pixels: 50))
        XCTAssertEqual(pixels(try stitch.render()), pixels(image(top: 100, height: 390)))
    }
    func testAboveStartDoesNotPrependAndCanReturnToExtend() throws {
        var stitch = ScrollScreenshotStitcher()
        _ = try stitch.append(image(top: 100))
        XCTAssertEqual(try stitch.append(image(top: 50)), .revisited)
        XCTAssertEqual(try stitch.append(image(top: 180)), .appended(pixels: 80))
        XCTAssertEqual(pixels(try stitch.render()), pixels(image(top: 100, height: 320)))
    }
    func testRepeatedFrameIsUnchanged() throws {
        var stitch = ScrollScreenshotStitcher()
        let first = image()
        _ = try stitch.append(first)
        XCTAssertEqual(try stitch.append(first), .unchanged)
        XCTAssertEqual(stitch.sections, 1)
        XCTAssertEqual(try stitch.render().height, 240)
    }
    func testMissingOverlapDoesNotMutateReferenceAndCanRecover() throws {
        var stitch = ScrollScreenshotStitcher()
        let first = image()
        _ = try stitch.append(first)
        XCTAssertEqual(try stitch.append(image(top: 900)), .unmatched)
        XCTAssertEqual(pixels(try stitch.render()), pixels(first))
        XCTAssertEqual(try stitch.append(image(top: 60)), .appended(pixels: 60))
        XCTAssertEqual(stitch.height, 300)
    }
    func testRepeatingRowsAreAmbiguousRatherThanGuessed() throws {
        var stitch = ScrollScreenshotStitcher()
        _ = try stitch.append(image(period: 30))
        XCTAssertEqual(try stitch.append(image(top: 10, period: 30)), .ambiguous)
        XCTAssertEqual(stitch.sections, 1)
    }
    func testPixelHeightAndSectionLimitsPreserveAcceptedImage() throws {
        for limits in [ScrollScreenshotStitcher.Limits(pixels: 160 * 260), .init(height: 260), .init(sections: 1)] {
            var stitch = ScrollScreenshotStitcher(limits: limits)
            let first = image()
            _ = try stitch.append(first)
            XCTAssertEqual(try stitch.append(image(top: 80)), .limitReached)
            XCTAssertEqual(pixels(try stitch.render()), pixels(first))
        }
    }
    func testGeometryChangesAndInvalidInitialAreaFailExplicitly() throws {
        var stitch = ScrollScreenshotStitcher()
        XCTAssertThrowsError(try stitch.render())
        XCTAssertThrowsError(try stitch.append(image(width: 20)))
        _ = try stitch.append(image())
        XCTAssertThrowsError(try stitch.append(image(width: 162)))
    }
    func testDifferenceDistinguishesStableAndMovedViews() {
        let first = image()
        XCTAssertEqual(ScrollScreenshotStitcher.difference(first, first), 0)
        XCTAssertGreaterThan(ScrollScreenshotStitcher.difference(first, image(top: 20)), 5)
        XCTAssertTrue(ScrollScreenshotStitcher.difference(first, image(width: 170)).isInfinite)
    }

    func testNativeTextOnWhitePageMatchesItsActualOffset() throws {
        let context = CGContext(data: nil, width: 480, height: 1800, bitsPerComponent: 8, bytesPerRow: 480 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 480, height: 1800))
        let font = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        for n in 0..<60 {
            let text = NSAttributedString(string: "Line \(n): content \(n * 7919) and distinct words", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 25, y: CGFloat(1770 - n * 29))
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        let page = try XCTUnwrap(context.makeImage())
        func frame(_ top: Int) throws -> CGImage { try XCTUnwrap(page.cropping(to: CGRect(x: 0, y: top, width: 480, height: 600))) }
        var stitch = ScrollScreenshotStitcher()
        _ = try stitch.append(frame(0))
        XCTAssertEqual(try stitch.append(frame(173)), .appended(pixels: 173))
        XCTAssertEqual(try stitch.append(frame(390)), .appended(pixels: 217))
        XCTAssertEqual(pixels(try stitch.render()), pixels(try XCTUnwrap(page.cropping(to: CGRect(x: 0, y: 0, width: 480, height: 990)))))
    }

    func testTexturedFixedSidebarIsRejectedInsteadOfRepeated() throws {
        func frame(_ top: Int) throws -> CGImage {
            let body = image(top: top)
            let context = CGContext(data: nil, width: 160, height: 240, bitsPerComponent: 8, bytesPerRow: 640,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(body, in: CGRect(x: 0, y: 0, width: 160, height: 240))
            let sidebar = try XCTUnwrap(image().cropping(to: CGRect(x: 0, y: 0, width: 32, height: 240)))
            context.draw(sidebar, in: CGRect(x: 0, y: 0, width: 32, height: 240))
            return try XCTUnwrap(context.makeImage())
        }
        var stitch = ScrollScreenshotStitcher()
        let first = try frame(0)
        _ = try stitch.append(first)
        XCTAssertEqual(try stitch.append(frame(70)), .unmatched)
        XCTAssertEqual(pixels(try stitch.render()), pixels(first))
    }
}

import CoreGraphics
import ImageIO
import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class ScreenshotTests: XCTestCase {
    /// A solid image; `transparent` leaves it fully clear.
    private func image(width: Int = 40, height: Int = 30, color: CGColor = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                       transparent: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent {
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return context.makeImage()!
    }

    /// RGBA of one pixel, origin top-left.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return data
    }

    func testDefaultsUseTheUsualScreenshotShortcutsAndPersist() throws {
        let settings = ScreenshotSettings()
        XCTAssertEqual(settings.shortcuts[.fullscreen], KeyCombo(keyCode: 20, modifiers: [.command, .shift]))
        XCTAssertEqual(settings.shortcuts[.area], KeyCombo(keyCode: 21, modifiers: [.command, .shift]))
        XCTAssertEqual(settings.shortcuts[.allInOne], KeyCombo(keyCode: 23, modifiers: [.command, .shift]))
        XCTAssertNil(settings.shortcuts[.window])
        let defaults = temporaryDefaults()
        var changed = settings
        changed.format = .jpg
        changed.overlayAutoClose = 10
        changed.save(to: defaults)
        XCTAssertEqual(ScreenshotSettings.load(from: defaults), changed)
    }

    func testFileNamesNeverOverwrite() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_793_700_000)
        let first = ScreenshotFiles.url(in: folder, at: date, prefix: "Ekran Resmi", format: .png) { _ in false }
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Ekran Resmi 20"))
        XCTAssertEqual(first.pathExtension, "png")
        let taken: Set<String> = [first.path]
        let second = ScreenshotFiles.url(in: folder, at: date, prefix: "Ekran Resmi", format: .png) { taken.contains($0.path) }
        XCTAssertTrue(second.lastPathComponent.hasSuffix(" (2).png"))
        XCTAssertEqual(ScreenshotFiles.url(in: folder, at: date, prefix: "Screenshot", format: .heic) { _ in false }.pathExtension, "heic")
    }

    func testSelectionGeometryNormalizesScalesAndClamps() throws {
        XCTAssertEqual(ScreenshotGeometry.rect(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 100)),
                       CGRect(x: 10, y: 40, width: 40, height: 60))
        let pixels = try XCTUnwrap(ScreenshotGeometry.pixelRect(CGRect(x: 10.2, y: 5, width: 100.4, height: 50), scale: 2,
                                                                 imageSize: CGSize(width: 3000, height: 2000)))
        XCTAssertEqual(pixels, CGRect(x: 20, y: 10, width: 201, height: 100))
        let clamped = try XCTUnwrap(ScreenshotGeometry.pixelRect(CGRect(x: -20, y: -20, width: 60, height: 60), scale: 1,
                                                                  imageSize: CGSize(width: 100, height: 100)))
        XCTAssertEqual(clamped, CGRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertNil(ScreenshotGeometry.pixelRect(CGRect(x: 10, y: 10, width: 0.2, height: 30), scale: 1, imageSize: CGSize(width: 100, height: 100)))
        XCTAssertEqual(ScreenshotGeometry.sizeLabel(CGRect(x: 0, y: 0, width: 640, height: 360), scale: 2), "1280 × 720")
    }

    func testEncodingKeepsSizeAndFlattensJPEGTransparencyToWhite() throws {
        for format in ScreenshotFormat.allCases {
            let data = try ScreenshotEncoder.encode(image(), as: format)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 40, "\(format)")
            XCTAssertEqual(decoded.height, 30, "\(format)")
        }
        let jpeg = try ScreenshotEncoder.encode(image(transparent: true), as: .jpg)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil)), 0, nil))
        let corner = pixel(decoded, 5, 5)
        XCTAssertGreaterThan(corner[0], 245)
        XCTAssertGreaterThan(corner[1], 245)
        XCTAssertGreaterThan(corner[2], 245)
        let png = try ScreenshotEncoder.encode(image(transparent: true), as: .png)
        let decodedPNG = try XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil)), 0, nil))
        XCTAssertEqual(pixel(decodedPNG, 5, 5)[3], 0, "PNG keeps transparency")
    }

    func testHistoryKeepsNewestFirstDeduplicatesCapsAndPrunes() {
        var history = ScreenshotHistory()
        let now = Date()
        history.add(ScreenshotHistoryEntry(path: "/a.png", date: now.addingTimeInterval(-10), mode: .area, pixelWidth: 1, pixelHeight: 1))
        history.add(ScreenshotHistoryEntry(path: "/b.png", date: now, mode: .fullscreen, pixelWidth: 1, pixelHeight: 1))
        history.add(ScreenshotHistoryEntry(path: "/a.png", date: now, mode: .area, pixelWidth: 2, pixelHeight: 2))
        XCTAssertEqual(history.entries.map(\.path), ["/a.png", "/b.png"])
        for index in 0..<(ScreenshotHistory.limit + 5) {
            history.add(ScreenshotHistoryEntry(path: "/\(index).png", date: now, mode: .area, pixelWidth: 1, pixelHeight: 1))
        }
        XCTAssertEqual(history.entries.count, ScreenshotHistory.limit)
        history = ScreenshotHistory(entries: [
            ScreenshotHistoryEntry(path: "/old.png", date: now.addingTimeInterval(-31 * 24 * 3600), mode: .area, pixelWidth: 1, pixelHeight: 1),
            ScreenshotHistoryEntry(path: "/gone.png", date: now, mode: .area, pixelWidth: 1, pixelHeight: 1),
            ScreenshotHistoryEntry(path: "/kept.png", date: now, mode: .area, pixelWidth: 1, pixelHeight: 1),
        ])
        history.prune(now: now) { $0 != "/gone.png" }
        XCTAssertEqual(history.entries.map(\.path), ["/kept.png"])
    }

    func testAnnotationsAreDrawnWhereTheEditorPutsThem() throws {
        let base = image(width: 100, height: 80, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let arrow = try XCTUnwrap(AnnotationRenderer.render(base, annotations: [
            .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10), color: .red, width: 6),
        ]))
        let onArrow = pixel(arrow, 40, 10)
        XCTAssertGreaterThan(onArrow[0], 200)
        XCTAssertLessThan(onArrow[1], 120, "Arrow is red near the top (top-left origin)")
        XCTAssertGreaterThan(pixel(arrow, 40, 70)[1], 240, "Bottom stays white")

        let highlight = try XCTUnwrap(AnnotationRenderer.render(base, annotations: [
            .highlight(CGRect(x: 0, y: 40, width: 100, height: 40), color: .yellow),
        ]))
        XCTAssertLessThan(pixel(highlight, 50, 60)[2], 200, "Yellow highlight removes blue from white")
        XCTAssertGreaterThan(pixel(highlight, 50, 20)[2], 240)

        let text = try XCTUnwrap(AnnotationRenderer.render(base, annotations: [
            .text("MMMM", at: CGPoint(x: 5, y: 5), color: .black, size: 30),
        ]))
        let dark = (0..<60).contains { x in (5..<35).contains { y in pixel(text, x, y)[0] < 80 } }
        XCTAssertTrue(dark, "Text is drawn near its top-left origin")
    }

    func testPixelateAveragesBlocks() throws {
        // Left half black, right half white: a 50 px block straddling the edge turns grey.
        let context = CGContext(data: nil, width: 100, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 20))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 20))
        let base = context.makeImage()!
        let result = try XCTUnwrap(AnnotationRenderer.render(base, annotations: [.pixelate(CGRect(x: 25, y: 0, width: 50, height: 20), block: 50)]))
        let middle = pixel(result, 48, 10)[0]
        XCTAssertGreaterThan(middle, 60)
        XCTAssertLessThan(middle, 200)
        XCTAssertEqual(pixel(result, 5, 10)[0], 0, "Outside the area is untouched")
    }
}

final class ScreenshotShortcutConflictTests: XCTestCase {
    func testEnabledMacOSShortcutsConflictAndDisabledOnesDoNot() {
        let shortcuts = ScreenshotSettings().shortcuts
        XCTAssertEqual(ScreenshotShortcutConflicts.system(shortcuts, symbolicHotKeys: nil), [.fullscreen, .area, .allInOne],
                       "Untouched settings mean macOS still owns ⇧⌘3/4/5")
        let disabled: [String: Any] = ["28": ["enabled": false], "30": ["enabled": false], "184": ["enabled": NSNumber(value: 0)]]
        XCTAssertTrue(ScreenshotShortcutConflicts.system(shortcuts, symbolicHotKeys: disabled).isEmpty)
        let onlyArea: [String: Any] = ["28": ["enabled": false], "30": ["enabled": true], "184": ["enabled": false]]
        XCTAssertEqual(ScreenshotShortcutConflicts.system(shortcuts, symbolicHotKeys: onlyArea), [.area])
    }

    func testRecognizesCleanShotBuilds() {
        XCTAssertEqual(ScreenshotShortcutConflicts.runningApp(bundleIDs: ["com.apple.finder", "com.getcleanshot.app-setapp"]), "CleanShot X")
        XCTAssertEqual(ScreenshotShortcutConflicts.runningApp(bundleIDs: ["pl.maketheweb.cleanshotx"]), "CleanShot X")
        XCTAssertNil(ScreenshotShortcutConflicts.runningApp(bundleIDs: ["com.apple.Safari"]))
    }
}

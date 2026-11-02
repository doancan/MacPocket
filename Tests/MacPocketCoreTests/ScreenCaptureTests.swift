import AppKit
import CoreImage
import XCTest
@testable import MacPocketCore

final class ScreenTextArrangeTests: XCTestCase {
    func testReadingOrderTopToBottomAndLeftToRight() {
        let lines = [
            ScreenTextReader.Line(text: "ikinci", box: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.05)),
            ScreenTextReader.Line(text: "sağ", box: CGRect(x: 0.6, y: 0.8, width: 0.2, height: 0.05)),
            ScreenTextReader.Line(text: "sol", box: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.05)),
            ScreenTextReader.Line(text: "son", box: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)),
        ]
        XCTAssertEqual(ScreenTextReader.arrange(lines), "sol sağ\nikinci\nson")
        XCTAssertEqual(ScreenTextReader.arrange([]), "")
    }
}

final class ScreenTextVisionTests: XCTestCase {
    private func image(_ text: String) throws -> CGImage {
        let size = NSSize(width: 900, height: 220)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            (text as NSString).draw(at: NSPoint(x: 30, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black])
            return true
        }
        return try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testRecognizesTurkishTextOnDevice() throws {
        try XCTSkipIf(TestEnvironment.isVirtualMachine, "Vision text recognition is unavailable in virtual machines")
        let text = try ScreenTextReader.text(in: image("Merhaba Dünya 2026"))
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Merhaba Dünya 2026")
    }

    func testReadsAQRCode() throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://example.com/macpocket".utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        XCTAssertEqual(try ScreenTextReader.codes(in: cgImage), ["https://example.com/macpocket"])
    }
}

final class PickedColorTests: XCTestCase {
    func testFormats() {
        let cobalt = PickedColor(red: 10 / 255, green: 92 / 255, blue: 1)
        XCTAssertEqual(cobalt.formatted(.hex), "#0A5CFF")
        XCTAssertEqual(cobalt.formatted(.rgb), "rgb(10, 92, 255)")
        XCTAssertEqual(cobalt.formatted(.hsl), "hsl(220, 100%, 52%)")
        XCTAssertEqual(PickedColor(red: 1, green: 0.5, blue: 0).formatted(.swiftUI), "Color(red: 1, green: 0.5, blue: 0)")
    }

    func testGreyHasNoHueAndValuesClamp() {
        XCTAssertEqual(PickedColor(red: 0.5, green: 0.5, blue: 0.5).formatted(.hsl), "hsl(0, 0%, 50%)")
        XCTAssertEqual(PickedColor(red: 2, green: -1, blue: 0).formatted(.hex), "#FF0000")
    }
}

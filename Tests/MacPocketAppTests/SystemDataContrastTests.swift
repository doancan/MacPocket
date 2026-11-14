import AppKit
import SwiftUI
import XCTest
@testable import MacPocketApp

/// WCAG 2.x contrast of the colors the page uses for small text, in both appearances.
@MainActor
final class SystemDataContrastTests: XCTestCase {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// The color as it lands on `background` once its alpha is applied (labels are partly transparent).
    private func resolved(_ color: Color, _ appearance: NSAppearance.Name, over background: RGB = (1, 1, 1)) -> RGB {
        var result: RGB = (0, 0, 0)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
            let alpha = Double(rgb.alphaComponent)
            result = (Double(rgb.redComponent) * alpha + background.r * (1 - alpha), Double(rgb.greenComponent) * alpha + background.g * (1 - alpha),
                      Double(rgb.blueComponent) * alpha + background.b * (1 - alpha))
        }
        return result
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func ratio(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    private func over(_ foreground: (r: Double, g: Double, b: Double), alpha: Double, on background: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        (foreground.r * alpha + background.r * (1 - alpha), foreground.g * alpha + background.g * (1 - alpha), foreground.b * alpha + background.b * (1 - alpha))
    }

    func testBadgeAndSecondaryTextMeetWCAGAAForSmallText() {
        var report: [String] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let panel = resolved(PocketTheme.panel, appearance)
            for (name, tone) in [("success", PocketTone.success), ("warning", .warning), ("critical", .critical)] {
                let tint = resolved(tone.color, appearance, over: panel)
                let badgeBackground = over(tint, alpha: 0.12, on: panel)
                let text = resolved(tone.readableTextColor, appearance, over: badgeBackground)
                let value = ratio(text, badgeBackground)
                report.append("\(appearance.rawValue.suffix(8)) badge \(name): \(String(format: "%.2f", value)):1")
                XCTAssertGreaterThanOrEqual(value, 4.5, "\(name) badge in \(appearance.rawValue)")
            }
            let secondary = ratio(resolved(Color.readableSecondary, appearance, over: panel), panel)
            report.append("\(appearance.rawValue.suffix(8)) secondary text: \(String(format: "%.2f", secondary)):1")
            XCTAssertGreaterThanOrEqual(secondary, 4.5, "secondary text in \(appearance.rawValue)")
        }
        print("CONTRAST\n" + report.joined(separator: "\n"))
    }
}

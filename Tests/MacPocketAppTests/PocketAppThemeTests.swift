import AppKit
import SwiftUI
import XCTest
@testable import MacPocketApp

@MainActor final class PocketAppThemeTests: XCTestCase {
    private func luminance(_ color: Color, dark: Bool = false) -> Double {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result = 0.0
        appearance.performAsCurrentDrawingAppearance {
            let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            result = 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
        }
        return result
    }

    private func contrast(_ a: Color, _ b: Color, darkA: Bool = false, darkB: Bool = false) -> Double {
        let la = luminance(a, dark: darkA), lb = luminance(b, dark: darkB)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testEveryThemeKeepsWhiteTextOnBrandFillsReadable() {
        for theme in PocketAppTheme.allCases {
            XCTAssertGreaterThanOrEqual(contrast(.white, theme.brand), 4.5, "\(theme.rawValue) brand vs white text")
        }
    }

    func testEveryThemeBrandStaysVisibleOnTheDarkCanvasAndTheLightCard() {
        for theme in PocketAppTheme.allCases {
            XCTAssertGreaterThanOrEqual(contrast(theme.brand, theme.background, darkB: true), 3.0, "\(theme.rawValue) on dark canvas")
            XCTAssertGreaterThanOrEqual(contrast(theme.brand, theme.panel), 3.0, "\(theme.rawValue) on light card")
        }
    }

    func testPrimaryTextIsReadableOnEveryThemeSurface() {
        for theme in PocketAppTheme.allCases {
            for surface in [theme.background, theme.panel, theme.raised, theme.sidebar] {
                XCTAssertGreaterThanOrEqual(contrast(.black, surface), 12, "\(theme.rawValue) light surface")
                XCTAssertGreaterThanOrEqual(contrast(.white, surface, darkB: true), 10, "\(theme.rawValue) dark surface")
            }
        }
    }

    func testThemesAreDistinctAndTheStoredChoiceIsRead() {
        XCTAssertEqual(Set(PocketAppTheme.allCases.map(\.rawValue)).count, PocketAppTheme.allCases.count)
        let key = PocketPreferenceKey.theme
        let previous = UserDefaults.standard.string(forKey: key)
        defer { previous.map { UserDefaults.standard.set($0, forKey: key) } ?? UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set("forest", forKey: key)
        XCTAssertEqual(PocketAppTheme.current, .forest)
        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(PocketAppTheme.current, .defaultValue)
    }
}

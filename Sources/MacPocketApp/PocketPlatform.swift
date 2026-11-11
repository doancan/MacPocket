import AppKit
import SwiftUI

enum PocketAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    /// Follows the macOS appearance unless the user picks one explicitly.
    static let defaultValue = PocketAppearance.system
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app-wide color theme chosen in Settings → Appearance: the brand colors and the tint of every surface.
/// Brand colors are mid-tones that keep 4.4:1 or better against white text and against the dark canvas.
enum PocketAppTheme: String, CaseIterable, Identifiable {
    case macpocket, midnight, tokyo, ocean, mint, forest, nord, solarized, gruvbox, sunset, cherry, mocha, sand, rose, violet, dracula, graphite
    var id: String { rawValue }
    static let defaultValue = PocketAppTheme.macpocket

    static var current: PocketAppTheme {
        PocketAppTheme(rawValue: UserDefaults.standard.string(forKey: PocketPreferenceKey.theme) ?? "") ?? .defaultValue
    }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .macpocket: "MacPocket"
        case .midnight: "Gece yarısı"
        case .ocean: "Okyanus"
        case .mint: "Nane"
        case .nord: "Nord"
        case .solarized: "Solarized"
        case .mocha: "Kahve"
        case .tokyo: "Tokyo"
        case .gruvbox: "Gruvbox"
        case .cherry: "Kiraz"
        case .sand: "Kum"
        case .dracula: "Dracula"
        case .forest: "Orman"
        case .sunset: "Gün batımı"
        case .rose: "Gül"
        case .violet: "Mor"
        case .graphite: "Grafit"
        }
    }

    /// Primary and secondary brand colors (hex).
    private var brandHex: (UInt32, UInt32) {
        switch self {
        case .macpocket: (0x0A5CFF, 0x7B5CFF)
        case .midnight: (0x4263EB, 0x7048E8)
        case .ocean: (0x0A76A8, 0x2563EB)
        case .mint: (0x0B8272, 0x2A8F52)
        case .nord: (0x4C6E96, 0x5E8C95)
        case .solarized: (0x1A74B8, 0x9A7400)
        case .mocha: (0xA9482A, 0x8C6A4F)
        case .tokyo: (0x4C6AD8, 0x8B5FBF)
        case .gruvbox: (0xA65A00, 0x6B7F2A)
        case .cherry: (0xC23648, 0xD2562F)
        case .sand: (0x8A6620, 0xA8782C)
        case .dracula: (0x7C5CC4, 0xC2418F)
        case .forest: (0x1B8044, 0x0E8F84)
        case .sunset: (0xC94A17, 0xC2255C)
        case .rose: (0xC7305F, 0x8E44C9)
        case .violet: (0x6D45E0, 0xB03FC9)
        case .graphite: (0x6B7280, 0x4B6A8A)
        }
    }

    /// (light, dark) hex pairs: canvas, card, raised card, sidebar well.
    private var surfaceHex: (background: (UInt32, UInt32), panel: (UInt32, UInt32), raised: (UInt32, UInt32), sidebar: (UInt32, UInt32)) {
        switch self {
        case .macpocket: ((0xF4F5F8, 0x121317), (0xFFFFFF, 0x1C1D23), (0xF7F8FA, 0x25272E), (0xEFF1F5, 0x16171C))
        case .midnight: ((0xEEF1FA, 0x0B1020), (0xFFFFFF, 0x121A30), (0xF2F4FC, 0x1B2440), (0xE6EAF7, 0x0E1528))
        case .ocean: ((0xF1F7FA, 0x0F161B), (0xFFFFFF, 0x192129), (0xF4F9FB, 0x222C35), (0xE8F1F6, 0x131B21))
        case .mint: ((0xF0F8F6, 0x0E1514), (0xFFFFFF, 0x17201E), (0xF4FAF8, 0x202B28), (0xE5F2EE, 0x121A18))
        case .nord: ((0xECEFF4, 0x1D2129), (0xFFFFFF, 0x262B35), (0xF2F4F8, 0x2F3541), (0xE3E8F0, 0x20242C))
        case .solarized: ((0xFDF6E3, 0x00232C), (0xFFFDF5, 0x042F3A), (0xF7F0DC, 0x093B47), (0xF3ECD6, 0x001D25))
        case .mocha: ((0xFAF5EF, 0x17110E), (0xFFFFFF, 0x221A16), (0xFCF8F3, 0x2C231E), (0xF3EBE1, 0x1B1410))
        case .tokyo: ((0xEEF1F8, 0x0F111A), (0xFFFFFF, 0x161A27), (0xF2F4FA, 0x1F2335), (0xE4E8F3, 0x12151F))
        case .gruvbox: ((0xF8F3E3, 0x1D1B16), (0xFFFDF6, 0x2A2722), (0xFBF7EA, 0x34302A), (0xF1EAD2, 0x211F1A))
        case .cherry: ((0xFBF3F3, 0x160F10), (0xFFFFFF, 0x211718), (0xFDF6F6, 0x2B2021), (0xF5E8E9, 0x1A1213))
        case .sand: ((0xF8F4EB, 0x15130E), (0xFFFDF8, 0x201D16), (0xFAF7F0, 0x2A261D), (0xEFE8D8, 0x191710))
        case .dracula: ((0xF5F3FA, 0x16141F), (0xFFFFFF, 0x211F2E), (0xF8F6FC, 0x2B2940), (0xECE8F5, 0x1A1826))
        case .forest: ((0xF2F8F4, 0x0F1512), (0xFFFFFF, 0x19211C), (0xF5FAF7, 0x222B25), (0xE8F1EB, 0x131A16))
        case .sunset: ((0xFBF5F0, 0x171210), (0xFFFFFF, 0x211A17), (0xFDF8F4, 0x2B2320), (0xF6ECE4, 0x1B1513))
        case .rose: ((0xFBF3F6, 0x171014), (0xFFFFFF, 0x21181D), (0xFDF6F8, 0x2B2127), (0xF6E9EE, 0x1B1317))
        case .violet: ((0xF6F4FC, 0x131019), (0xFFFFFF, 0x1D1926), (0xF9F7FD, 0x262230), (0xEEEAF8, 0x16121D))
        case .graphite: ((0xF3F3F4, 0x111112), (0xFFFFFF, 0x1C1C1E), (0xF7F7F8, 0x262628), (0xECECEE, 0x151516))
        }
    }

    var brand: Color { Color(hex: brandHex.0) }
    var brandSecondary: Color { Color(hex: brandHex.1) }
    var background: Color { Color(light: surfaceHex.background.0, dark: surfaceHex.background.1) }
    var panel: Color { Color(light: surfaceHex.panel.0, dark: surfaceHex.panel.1) }
    var raised: Color { Color(light: surfaceHex.raised.0, dark: surfaceHex.raised.1) }
    var sidebar: Color { Color(light: surfaceHex.sidebar.0, dark: surfaceHex.sidebar.1) }
    var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brand.mix(with: brandSecondary, by: 0.5), brandSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum PocketTheme {
    /// The theme's brand color, or the macOS accent color when chosen in Settings → Appearance.
    static var brand: Color { PocketAccentStyle.current == .system ? .accentColor : PocketAppTheme.current.brand }
    static let cobalt = Color(hex: 0x0A5CFF)
    static var brandSecondary: Color { PocketAppTheme.current.brandSecondary }
    static var brandGradient: LinearGradient { PocketAppTheme.current.brandGradient }

    /// Page canvas: tinted off-white instead of the grey window background; tinted near-black in dark mode.
    static var background: Color { PocketAppTheme.current.background }
    /// Card surface: white with a soft shadow in light mode, an elevated tone in dark mode.
    static var panel: Color { PocketAppTheme.current.panel }
    static var raised: Color { PocketAppTheme.current.raised }
    static var group: Color { background }
    /// Inset wells (code output, search fields).
    static var sidebar: Color { PocketAppTheme.current.sidebar }
    static let line = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.08)
    static var accent: Color { brand }
    static let memory = Color(hex: 0x9B5CFF)
    static let disk = Color(hex: 0x22A55B)
    static let power = Color(hex: 0xFF8A00)
}

/// Each module has its own color identity, as in System Settings and CleanMyMac.
extension PocketPage {
    var tint: Color {
        switch self {
        case .overview: PocketTheme.brand
        case .performance: Color(hex: 0x00A6C8)
        case .power: PocketTheme.power
        case .cleanup: Color(hex: 0xF2545B)
        case .storage: PocketTheme.disk
        case .applications: Color(hex: 0x7B5CFF)
        case .tools: Color(hex: 0x5F6B7E)
        case .practical: Color(hex: 0x007E80)
        case .ssh: Color(hex: 0x22A55B)
        case .menuBar: Color(hex: 0x3B7BFF)
        }
    }
}

private struct PocketTintKey: EnvironmentKey {
    /// Read per use, so a theme change reaches views that never set a tint of their own.
    static var defaultValue: Color { PocketTheme.brand }
}

extension EnvironmentValues {
    /// The current module color; headings, icon tiles and the page backdrop read it.
    var pocketTint: Color {
        get { self[PocketTintKey.self] }
        set { self[PocketTintKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// Appearance-adaptive color resolved by AppKit, so it follows the window's light/dark appearance.
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkOpacity : lightOpacity)
        })
    }
}

/// Ambient page background: the canvas with a soft wash of the module color at the top.
struct PocketBackdrop: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.22 : 0.14
        ZStack {
            PocketTheme.background
            RadialGradient(colors: [tint.opacity(strength), .clear], center: .topLeading, startRadius: 0, endRadius: 720)
            RadialGradient(colors: [PocketTheme.brandSecondary.opacity(strength * 0.45), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 560)
        }
        // Three full-window gradient layers flattened into one texture (~20 MB each on a 5K display).
        .drawingGroup()
        .modifier(PocketBackgroundExtension())
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Mirrors the module wash under the floating glass sidebar so the window reads as one surface.
private struct PocketBackgroundExtension: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.backgroundExtensionEffect()
    }
}

/// Rounded-square icon with a vertical gradient and a white glyph (System Settings style).
struct PocketIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                // Tint plus a white sheen at the top.
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.24), .clear], startPoint: .top, endPoint: .bottom))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: tint.opacity(size > 30 ? 0.35 : 0.2), radius: size > 30 ? 8 : 2, y: size > 30 ? 4 : 1)
            .accessibilityHidden(true)
    }
}

private struct PocketGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(PocketTheme.line))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        }
    }
}

extension View {
    func pocketGlass(radius: CGFloat = 12) -> some View { modifier(PocketGlass(radius: radius)) }
}

extension Notification.Name {
    static let pocketFind = Notification.Name("MacPocket.find")
    static let pocketQuickLook = Notification.Name("MacPocket.quickLook")
}

@MainActor
func showPocketWindow(_ openWindow: OpenWindowAction) {
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
}

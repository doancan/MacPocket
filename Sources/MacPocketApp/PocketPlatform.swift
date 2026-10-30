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

enum PocketTheme {
    /// Cobalt from the app icon, or the macOS accent color when chosen in Settings → Appearance.
    static var brand: Color { PocketAccentStyle.current == .system ? .accentColor : cobalt }
    static let cobalt = Color(hex: 0x0A5CFF)
    static let brandSecondary = Color(hex: 0x7B5CFF)
    static let brandGradient = LinearGradient(colors: [Color(hex: 0x0A5CFF), Color(hex: 0x5B4BFF), Color(hex: 0x8E5CFF)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Page canvas: a cool off-white instead of the grey window background; near-black in dark mode.
    static let background = Color(light: 0xF4F5F8, dark: 0x121317)
    /// Card surface: white with a soft shadow in light mode, an elevated tone in dark mode.
    static let panel = Color(light: 0xFFFFFF, dark: 0x1C1D23)
    static let raised = Color(light: 0xF7F8FA, dark: 0x25272E)
    static let group = background
    /// Inset wells (code output, search fields).
    static let sidebar = Color(light: 0xEFF1F5, dark: 0x16171C)
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
        case .cleanup: Color(hex: 0xE8458B)
        case .storage: PocketTheme.disk
        case .applications: Color(hex: 0x7B5CFF)
        case .tools: Color(hex: 0x5F6B7E)
        }
    }
}

private struct PocketTintKey: EnvironmentKey {
    static let defaultValue = PocketTheme.brand
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

/// macOS 26+: mirrors the module wash under the floating glass sidebar so the window reads as one surface.
private struct PocketBackgroundExtension: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
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
                // Tint plus a white sheen at the top (Color.mix needs macOS 15).
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
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
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

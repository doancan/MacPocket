import AppKit
import SwiftUI

/// Ayarlar › Görünüm › Liquid Glass: whether MacPocket's own controls use Liquid Glass.
///
/// System chrome (sidebar, toolbar, sheets, menus) is always glass on macOS 27 and isn't affected. This
/// governs the custom glass the app draws itself; tab lenses, search fields, glass buttons, floating panels
/// and HUDs. Off, those get an opaque fill in the same shape. Reduce Transparency needs no special case: the
/// system frosts glass itself.
public enum LiquidGlass {
    public static let preferenceKey = "MacPocket.liquidGlass"
    public static let enabledByDefault = true

    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) as? Bool ?? enabledByDefault
    }
}

/// Custom glass that follows the Liquid Glass setting. Reads the preference itself rather than the
/// environment, because floating panels and HUDs live in their own windows and don't inherit the main
/// window's environment.
private struct AdaptiveGlass<S: Shape, Fallback: ShapeStyle>: ViewModifier {
    @AppStorage(LiquidGlass.preferenceKey) private var enabled = LiquidGlass.enabledByDefault
    let glass: Glass
    let shape: S
    let fallback: Fallback

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(fallback, in: shape)
                .overlay { shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5) }
        }
    }
}

public extension View {
    /// `glassEffect(_:in:)` when Liquid Glass is on; otherwise the control background colour in the same
    /// shape.
    func adaptiveGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(AdaptiveGlass(glass: glass, shape: shape, fallback: Color(nsColor: .controlBackgroundColor)))
    }

    /// `glassEffect(_:in:)` when Liquid Glass is on; otherwise `fallback` in the same shape.
    func adaptiveGlass<S: Shape, F: ShapeStyle>(_ glass: Glass = .regular, in shape: S, fallback: F) -> some View {
        modifier(AdaptiveGlass(glass: glass, shape: shape, fallback: fallback))
    }
}

/// The system glass button styles when Liquid Glass is on (`.glassProminent` for the primary action, `.glass`
/// otherwise), and the bordered styles when it's off.
///
/// Secondary buttons drop the inherited tint: the app tints its whole window with the brand colour for
/// toggles, progress and links, and a tint turns `.glass` into a filled, prominent-looking button; every
/// action would then look primary. A tint belongs to the one primary action (HIG), which keeps it.
public struct AdaptiveGlassButtonStyle: PrimitiveButtonStyle {
    @AppStorage(LiquidGlass.preferenceKey) private var enabled = LiquidGlass.enabledByDefault
    let prominent: Bool

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        switch (enabled, prominent) {
        case (true, true): Button(configuration).buttonStyle(.glassProminent)
        case (true, false): Button(configuration).buttonStyle(.glass).tint(nil)
        case (false, true): Button(configuration).buttonStyle(.borderedProminent)
        case (false, false): Button(configuration).buttonStyle(.bordered).tint(nil)
        }
    }
}

public extension PrimitiveButtonStyle where Self == AdaptiveGlassButtonStyle {
    static var adaptiveGlass: AdaptiveGlassButtonStyle { AdaptiveGlassButtonStyle(prominent: false) }
    static var adaptiveGlassProminent: AdaptiveGlassButtonStyle { AdaptiveGlassButtonStyle(prominent: true) }
}

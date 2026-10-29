import AppKit
import SwiftUI

enum PocketAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Sistemle aynı"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PocketTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .textBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let group = Color(nsColor: .windowBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let memory = Color.purple
    static let disk = Color.green
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

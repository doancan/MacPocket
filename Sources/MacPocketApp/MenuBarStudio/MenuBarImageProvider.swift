import AppKit
import MacPocketAIUsage
import MacPocketCore
import SwiftUI

/// Renders menu bar items for the Menü Çubuğu page with the same code the real status items use, so every
/// preview, style tile and the canvas show exactly what will appear in the menu bar.
@MainActor
struct MenuBarImageProvider {
    let model: PocketModel
    let preferences: MenuBarPreferences
    let history: MenuBarHistory
    let aiUsage: AIUsageService

    /// The item of `module`; `settings` replaces the stored ones (style tiles preview alternatives). With
    /// `demo`, modules that have nothing to show right now (no timer running, no device connected) draw
    /// sample values, so a style tile still shows what the style looks like.
    func image(_ module: MenuBarModule, settings override: MenuBarModuleSettings? = nil, demo: Bool = false) -> NSImage {
        var settings = override ?? preferences.settings(for: module)
        if module == .aiUsage {
            settings.warningThreshold = aiUsage.settings.warning
            settings.criticalThreshold = aiUsage.settings.critical
            if let image = AIUsageMenuBarImage.make(service: aiUsage, settings: settings, dark: false) { return image }
        }
        var external = MenuBarExternalReadings.reading(for: module, model: model, settings: settings)
        if demo, external?.fraction == nil, let sample = Self.sampleReading(module) { external = sample }
        let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: model.system, binaryUnits: preferences.binaryUnits,
                                               weather: WeatherService.shared.snapshot, aiUsage: aiUsage.menuBarReading, external: external)
        return MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: model.system, history: history)
    }

    private static func sampleReading(_ module: MenuBarModule) -> MenuBarReading? {
        func sample(_ text: String, _ fraction: Double, _ symbol: String) -> MenuBarReading {
            MenuBarReading(lines: [text], reserve: [text], fraction: fraction, magnitude: fraction * 100, accessibility: text, symbol: symbol)
        }
        switch module {
        case .awake: return sample(MenuBarFormatter.duration(minutes: 42), 0.6, "cup.and.saucer.fill")
        case .bluetooth: return sample(MenuBarFormatter.percentText("72"), 0.72, "battery.75percent")
        case .display: return sample(MenuBarFormatter.percentText("68"), 0.68, "sun.max.fill")
        default: return nil
        }
    }

    /// The single grouped icon; `override` previews other grouped options.
    func grouped(_ override: MenuBarPreferences? = nil) -> NSImage {
        let preferences = override ?? self.preferences
        let attention = MenuBarAttention.isNeeded(model.system, diskFreeThreshold: ResourceAlertSettings.load(from: .standard).diskFreePercent)
        return MenuBarRenderer.grouped(MenuBarRenderer.groupedState(preferences: preferences, snapshot: model.system,
                                                                   history: history, attention: attention))
    }

    /// The measurement thresholds apply to, in the value's own unit; nil when nothing is measured yet.
    func thresholdValue(_ module: MenuBarModule) -> Double? {
        let settings = preferences.settings(for: module)
        return MenuBarFormatter.reading(module, settings: settings, snapshot: model.system, binaryUnits: preferences.binaryUnits,
                                        weather: WeatherService.shared.snapshot, aiUsage: aiUsage.menuBarReading,
                                        external: MenuBarExternalReadings.reading(for: module, model: model, settings: settings)).thresholdValue
    }

    /// The text the module shows right now, for list subtitles and the inspector header.
    func readingText(_ module: MenuBarModule) -> String {
        let settings = preferences.settings(for: module)
        let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: model.system, binaryUnits: preferences.binaryUnits,
                                               weather: WeatherService.shared.snapshot, aiUsage: aiUsage.menuBarReading,
                                               external: MenuBarExternalReadings.reading(for: module, model: model, settings: settings))
        return reading.lines.joined(separator: " · ")
    }
}

/// The light or dark rendition of the menu bar a preview draws on.
struct MenuBarSurface: Equatable {
    let dark: Bool

    /// Item color on the translucent bar: near-black on the light bar, white on the dark one.
    var foreground: NSColor { dark ? NSColor(white: 1, alpha: 0.96) : NSColor(white: 0.08, alpha: 0.88) }
    var foregroundColor: Color { Color(nsColor: foreground) }
    var barFill: Color { dark ? Color.black.opacity(0.42) : Color.white.opacity(0.66) }
    var wallpaper: [Color] {
        dark ? [Color(hex: 0x1B2A5E), Color(hex: 0x3A2470), Color(hex: 0x0E1430)]
             : [Color(hex: 0x7FA8F5), Color(hex: 0xB59DF2), Color(hex: 0xD9E4FB)]
    }
    var appearance: NSAppearance { NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing() }

    /// An image that draws itself under this surface's appearance and foreground, whatever the window's
    /// appearance: template images take the surface foreground, colored ones resolve their dynamic colors for
    /// it.
    func flatten(_ source: NSImage) -> NSImage {
        let appearance = self.appearance, foreground = self.foreground
        let result = NSImage(size: source.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                source.draw(in: rect)
                if source.isTemplate {
                    foreground.set()
                    rect.fill(using: .sourceAtop)
                }
            }
            return true
        }
        result.accessibilityDescription = source.accessibilityDescription
        return result
    }
}

/// How the preview chooses between light and dark; "system" follows macOS.
enum MenuBarPreviewAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    static let storageKey = "MacPocket.menubar.previewAppearance"

    var title: LocalizedStringKey {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }

    func isDark(system: ColorScheme) -> Bool {
        switch self {
        case .system: system == .dark
        case .light: false
        case .dark: true
        }
    }
}

extension MenuBarAccent {
    /// The swatch color; `nil` for `automatic`.
    @MainActor var swatch: Color? { MenuBarRenderer.color(for: self).map { Color(nsColor: $0) } }
}

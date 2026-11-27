import AppKit
import Foundation
import MacPocketCore

/// Focus Session was removed in 0.4.x. A session that was running when the previous version crashed left
/// system changes behind (hidden desktop icons, guarded ⌘Q, dimmed displays); this puts them back once.
/// User data of removed tools (macros, snippets, screen time) is left in place on purpose: deleting it is not
/// reversible and an older build may still read it.
@MainActor
enum RemovedFeatureRecovery {
    private static let focusPendingKey = "MacPocket.focus.pending"

    private struct FocusPending: Decodable {
        var hidDesktopIcons = false
        var guardedQuit = false
        /// Display ID → brightness before dimming.
        var dimmed: [UInt32: Double]?
    }

    static func run(defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: focusPendingKey) else { return }
        defaults.removeObject(forKey: focusPendingKey)
        guard let pending = try? JSONDecoder().decode(FocusPending.self, from: data) else { return }
        if pending.guardedQuit {
            var settings = QuitGuardSettings.load(from: defaults)
            settings.quitMode = .off
            settings.save(to: defaults)
        }
        DisplayBrightnessService.restoreInterruptedLevels(pending.dimmed ?? [:])
        if pending.hidDesktopIcons { Task { try? await QuickActionService.setDesktopIcons(visible: true) } }
    }
}

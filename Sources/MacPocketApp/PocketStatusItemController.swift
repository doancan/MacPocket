import AppKit
import Combine
import MacPocketCore
import SwiftUI

/// Owns the menu bar status items and their popover, independently of the main window.
///
/// - Grouped layout: one item ("grouped") whose popover has one tab per module.
/// - Separate layout: one item per enabled module, each opening that module's detail.
/// Images are re-rendered only when their inputs change (see `MenuBarRenderer.Key`), and the
/// popover's hosting controller exists only while the popover is shown.
@MainActor
final class PocketStatusItemController: NSObject, NSPopoverDelegate {
    private static let groupedKey = "grouped"

    private let model: PocketModel
    private let store = MenuBarSettingsStore.shared
    private let history = MenuBarHistory.shared
    private var items: [String: NSStatusItem] = [:]
    private var itemOrder: [String] = []
    private var renderKeys: [String: MenuBarRenderer.Key] = [:]
    private var accessibilityTexts: [String: String] = [:]
    private let popover = NSPopover()
    private var popoverOwner: String?
    private var appearanceName: String?
    private var subscriptions = Set<AnyCancellable>()

    init(model: PocketModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        updateAppearance()
        refresh()
        model.$system.receive(on: RunLoop.main).sink { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let snapshot { self.history.record(snapshot) }
                self.refresh()
            }
        }.store(in: &subscriptions)
        store.$preferences.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.updatePing()
            }
        }.store(in: &subscriptions)
        updatePing()
        model.$paused.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTooltips() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAppearance() }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .pocketQuickLook)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.showPopover(for: nil) }
            }.store(in: &subscriptions)
    }

    /// The ping leaves the Mac, so it runs only while the network module shows latency in the menu bar.
    private func updatePing() {
        let preferences = store.preferences
        let wanted = preferences.visible && preferences.enabled.contains(.network)
            && preferences.settings(for: .network).value == .networkPing
        let monitor = model.systemMonitor
        Task { await monitor.setPingEnabled(wanted) }
    }

    private func updateAppearance() {
        let name = UserDefaults.standard.string(forKey: "MacPocket.appearance")
        guard name != appearanceName else { return }
        appearanceName = name
        switch PocketAppearance(rawValue: name ?? PocketAppearance.defaultValue.rawValue) {
        case .dark: popover.appearance = NSAppearance(named: .darkAqua)
        case .light: popover.appearance = NSAppearance(named: .aqua)
        case .system, .none: popover.appearance = nil
        }
    }

    // MARK: Items

    private func desiredKeys(_ preferences: MenuBarPreferences) -> [String] {
        guard preferences.visible else { return [] }
        let enabled = preferences.enabledModules
        // With nothing enabled the grouped glyph stays, so MacPocket is always reachable.
        if preferences.layout == .separate && !enabled.isEmpty { return enabled.map(\.rawValue) }
        return [Self.groupedKey]
    }

    private func refresh() {
        let preferences = store.preferences
        let keys = desiredKeys(preferences)
        if keys != itemOrder { rebuildItems(keys) }
        let snapshot = model.system
        for key in keys {
            guard let button = items[key]?.button else { continue }
            let image: () -> NSImage
            let renderKey: MenuBarRenderer.Key
            let spoken: String
            if let module = MenuBarModule(rawValue: key) {
                let settings = preferences.settings(for: module)
                let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: snapshot,
                                                       binaryUnits: preferences.binaryUnits)
                renderKey = MenuBarRenderer.moduleKey(module, settings: settings, reading: reading, snapshot: snapshot, history: history)
                image = { MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: snapshot, history: self.history) }
                spoken = reading.accessibility
            } else {
                let readings = preferences.enabledModules.map {
                    ($0, MenuBarFormatter.reading($0, settings: preferences.settings(for: $0), snapshot: snapshot,
                                                  binaryUnits: preferences.binaryUnits))
                }
                let reasons = MenuBarAttention.reasons(snapshot, diskFreeThreshold: diskFreeThreshold)
                let state = MenuBarRenderer.groupedState(preferences: preferences, snapshot: snapshot, history: history,
                                                         attention: !reasons.isEmpty)
                renderKey = MenuBarRenderer.groupedKey(state)
                image = { MenuBarRenderer.grouped(state) }
                let parts = readings.map(\.1.accessibility) + (state.attention ? reasons : [])
                spoken = parts.isEmpty ? String(localized: "Sistem durumu") : parts.joined(separator: ", ")
            }
            if renderKeys[key] != renderKey {
                renderKeys[key] = renderKey
                button.image = image()
            }
            if accessibilityTexts[key] != spoken {
                accessibilityTexts[key] = spoken
                button.setAccessibilityLabel(String(localized: "MacPocket, \(spoken)"))
                updateTooltip(button, spoken: spoken)
            }
        }
    }

    /// The same low-disk threshold the resource alerts use (Settings → Notifications).
    private var diskFreeThreshold: Double { ResourceAlertSettings.load(from: .standard).diskFreePercent }

    private func rebuildItems(_ keys: [String]) {
        popover.performClose(nil)
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
        items = [:]
        renderKeys = [:]
        accessibilityTexts = [:]
        itemOrder = keys
        // macOS places each new item to the left of the previous one, so create right-to-left.
        for key in keys.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.imagePosition = .imageOnly
            item.button?.title = ""
            item.button?.setAccessibilityRole(.menuButton)
            item.button?.setAccessibilityHelp(String(localized: "Ayrıntıları göstermek için tıkla"))
            items[key] = item
        }
    }

    private func updateTooltip(_ button: NSStatusBarButton, spoken: String) {
        button.toolTip = model.paused ? spoken + "\n" + String(localized: "İzleme duraklatıldı") : spoken
    }

    private func updateTooltips() {
        for (key, text) in accessibilityTexts {
            if let button = items[key]?.button { updateTooltip(button, spoken: text) }
        }
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        let key = items.first { $0.value.button === sender }?.key
        if NSApp.currentEvent?.type == .rightMouseUp, let key {
            popover.performClose(nil)
            showQuickMenu(for: key)
            return
        }
        if popover.isShown {
            let sameOwner = key == popoverOwner
            popover.performClose(nil)
            if sameOwner { return }
        }
        showPopover(for: key)
    }

    /// Shows the popover under the item `key`, or under the first item when nil (⇧⌘M quick look).
    private func showPopover(for key: String?) {
        guard !popover.isShown, let key = key ?? itemOrder.first, let button = items[key]?.button else { return }
        let content: MenuBarPopoverContent = MenuBarModule(rawValue: key).map { .module($0) } ?? .grouped
        let hosting = NSHostingController(rootView: PocketMenuBarView(model: model, history: history, content: content))
        // The popover follows SwiftUI's ideal size, so switching tabs resizes it smoothly.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popoverOwner = key
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        hosting.view.window?.makeKey()
    }


    // MARK: Right-click menu

    private func showQuickMenu(for key: String) {
        guard let item = items[key] else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "MacPocket’ı aç"), action: #selector(openMainWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Ayarlar"), action: #selector(openSettings), keyEquivalent: ",").target = self
        let schedule = DisplayBrightnessService.shared.schedule
        if schedule.enabled, schedule.source == .solar {
            menu.addItem(.separator())
            if case .paused(until: .some) = NightModeService.shared.status {
                menu.addItem(withTitle: String(localized: "Gece modunu yeniden aç"), action: #selector(resumeNightMode), keyEquivalent: "").target = self
            } else {
                menu.addItem(withTitle: String(localized: "Gece modunu 1 saat kapat"), action: #selector(pauseNightMode), keyEquivalent: "").target = self
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "MacPocket’ten çık"), action: #selector(quit), keyEquivalent: "q").target = self
        // A menu assigned only for this click keeps the left click opening the popover.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        model.openMainWindow?()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        model.openSettingsWindow?()
    }

    @objc private func pauseNightMode() { NightModeService.shared.pauseForAnHour() }

    @objc private func resumeNightMode() { NightModeService.shared.resume() }

    @objc private func quit() { NSApp.terminate(nil) }

    func popoverDidClose(_ notification: Notification) {

        // Releasing the hosted view stops all popover rendering while it is hidden.
        popover.contentViewController = nil
        model.menuBarProcessesWanted = false
        if let owner = popoverOwner { items[owner]?.button?.highlight(false) }
        popoverOwner = nil
    }
}

@MainActor
final class PocketApplicationState: ObservableObject {
    let model: PocketModel
    let loginItem: LoginItemController
    let statusItem: PocketStatusItemController

    init() {
        let model = PocketModel()
        self.model = model
        _ = WindowSwitcherHotkeyController.shared
        loginItem = LoginItemController()
        statusItem = PocketStatusItemController(model: model)
        ClipboardService.shared.start()
        WindowLayoutService.shared.start()
        QuitGuardService.shared.start()
        DisplayBrightnessService.shared.start()
        MonitorVolumeService.shared.start()
        NightModeService.shared.start()
        MacroService.shared.start()
        AppFreezerService.shared.start()
        FocusSessionService.shared.attach(model)
        WorkspaceService.shared.start()
        SnippetService.shared.start()
        ScreenGrabService.shared.start()
        ScreenshotService.shared.start()
        BluetoothBatteryService.shared.start()
        ScreenTimeService.shared.start()
        _ = UpdateService.shared
        DisplaySettingsService.shared.start()
        MouseScrollService.shared.start()
        AudioOutputService.shared.start()
        VolumeMixerService.shared.start()
        ScreenRecorderService.shared.start()
        PrivacyMonitorService.shared.start()
    }
}

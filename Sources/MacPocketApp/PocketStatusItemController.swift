import AppKit
import Combine
import MacPocketCore
import MacPocketAIUsage
import SwiftUI

/// Owns the menu bar status items and their popover, independently of the main window.
///
/// - Grouped layout: one item ("grouped") whose popover has one tab per module.
/// - Separate layout: one item per enabled module, each opening that module's detail.
/// Images are re-rendered only when their inputs change (see `MenuBarRenderer.Key`), and the
/// popover's hosting controller exists only while the popover is shown.
@MainActor
final class PocketStatusItemController: NSObject {
    private static let groupedKey = "grouped"

    private let model: PocketModel
    private let store = MenuBarSettingsStore.shared
    private let history = MenuBarHistory.shared
    private var items: [String: NSStatusItem] = [:]
    private var itemOrder: [String] = []
    private var renderKeys: [String: MenuBarRenderer.Key] = [:]
    private var accessibilityTexts: [String: String] = [:]
    private let popover = NSPopover()
    private lazy var presentation = StatusItemPopoverPresenter(popover: popover, buttons: { [weak self] in self?.items.compactMapValues(\.button) ?? [:] },
        content: { [weak self] key in
            guard let self else { return nil }
            let content: MenuBarPopoverContent = MenuBarModule(rawValue: key).map { .module($0) } ?? .grouped
            let hosting = NSHostingController(rootView: PocketMenuBarView(model: self.model, history: self.history, content: content))
            hosting.sizingOptions = [.preferredContentSize]
            return hosting
        }, didClose: { [weak self] in self?.model.menuBarProcessesWanted = false })
    private var appearanceName: String?
    private var subscriptions = Set<AnyCancellable>()
    /// Advances keep-awake and focus countdowns while monitoring is paused (samples drive `refresh` otherwise).
    private var clock: Timer?

    init(model: PocketModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = true
        updateAppearance()
        refresh()
        // Observation (not Combine) drives the menu bar: only `system` and `paused` writes reach here.
        observe({ [model] in model.system }) { controller, snapshot in
            if let snapshot { controller.history.record(snapshot) }
            controller.refresh()
        }
        store.$preferences.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.updatePing()
                self?.updateWeather()
                if let self { AIUsageIntegration.shared.configure(preferences: self.store.preferences) }
            }
        }.store(in: &subscriptions)
        updatePing()
        updateWeather()
        AIUsageService.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                AIUsageIntegration.shared.configure(preferences: self.store.preferences)
                self.refresh()
            }
        }.store(in: &subscriptions)
        AIUsageIntegration.shared.configure(preferences: store.preferences)
        // The menu bar shows only the forecast and its place; loading/refresh bookkeeping does not redraw it.
        observe({ (WeatherService.shared.snapshot, WeatherService.shared.location) }) { controller, _ in controller.refresh() }
        observe({ [model] in model.paused }) { controller, _ in controller.updateTooltips() }
        observe({ [model] in model.awakeSession }) { controller, _ in controller.refresh() }
        FocusSessionService.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
        BluetoothBatteryService.shared.$devices.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAppearance() }
            }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAppearance() }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .pocketQuickLook)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.showPopover(for: nil) }
            }.store(in: &subscriptions)
    }

    /// Runs `apply` on the main actor for the current value and every later transaction that
    /// changes what `value` reads. The loop ends with the controller or its subscriptions.
    private func observe<Value: Sendable>(_ value: @escaping @MainActor @Sendable () -> Value,
                                          apply: @escaping @MainActor (PocketStatusItemController, Value) -> Void) {
        let task = Task { @MainActor [weak self] in
            for await current in Observations(value) {
                guard let self else { return }
                apply(self, current)
            }
        }
        subscriptions.insert(AnyCancellable { task.cancel() })
    }

    /// The ping leaves the Mac, so it runs only while the network module shows latency in the menu bar.
    private func updatePing() {
        let preferences = store.preferences
        let wanted = preferences.visible && preferences.enabled.contains(.network)
            && preferences.settings(for: .network).value == .networkPing
        let monitor = model.systemMonitor
        Task { await monitor.setPingEnabled(wanted) }
    }

    private func updateWeather() {
        WeatherService.shared.setEnabled(store.preferences.visible && store.preferences.enabled.contains(.weather))
    }

    private func updateAppearance() {
        popover.animates = !PocketReduceMotion.isEnabled
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
        // Weather, AI quotas, keep awake, focus and Bluetooth batteries keep their own item beside the grouped one.
        return [Self.groupedKey] + enabled.filter { !$0.isSystemMetric }.map(\.rawValue)
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
                var settings = preferences.settings(for: module)
                if module == .aiUsage {
                    settings.warningThreshold = AIUsageService.shared.settings.warning
                    settings.criticalThreshold = AIUsageService.shared.settings.critical
                }
                let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: snapshot,
                                                       binaryUnits: preferences.binaryUnits, weather: WeatherService.shared.snapshot, aiUsage: AIUsageService.shared.menuBarReading,
                                                       external: MenuBarExternalReadings.reading(for: module, model: model, settings: settings))
                let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                var moduleKey = MenuBarRenderer.moduleKey(module, settings: settings, reading: reading, snapshot: snapshot, history: history)
                if module == .aiUsage { moduleKey.parts.append(dark ? "ai-dark" : "ai-light") }
                renderKey = moduleKey
                image = {
                    if module == .aiUsage, let image = AIUsageMenuBarImage.make(service: .shared, settings: settings, dark: dark) { return image }
                    return MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: snapshot, history: self.history)
                }
                spoken = reading.accessibility
            } else {
                let readings = preferences.enabledModules.filter(\.isSystemMetric).map {
                    ($0, MenuBarFormatter.reading($0, settings: preferences.settings(for: $0), snapshot: snapshot,
                                                  binaryUnits: preferences.binaryUnits, weather: WeatherService.shared.snapshot, aiUsage: AIUsageService.shared.menuBarReading))
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
        updateClock(keys)
    }

    private func updateClock(_ keys: [String]) {
        let awake = keys.contains(MenuBarModule.awake.rawValue) && model.awakeSession?.active == true && model.awakeSession?.endsAt != nil
        let focus = keys.contains(MenuBarModule.focus.rawValue) && FocusSessionService.shared.isRunning
        if awake || focus {
            guard clock == nil else { return }
            let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else {
            clock?.invalidate(); clock = nil
        }
    }

    /// The same low-disk threshold the resource alerts use (Settings → Notifications).
    private var diskFreeThreshold: Double { ResourceAlertSettings.load(from: .standard).diskFreePercent }

    private func rebuildItems(_ keys: [String]) {
        presentation.close()
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
        guard let key = items.first(where: { $0.value.button === sender })?.key else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentation.close()
            showQuickMenu(for: key)
            return
        }
        presentation.toggle(key)
    }

    /// Shows the popover under the item `key`, or under the first item when nil (⇧⌘M quick look).
    private func showPopover(for key: String?) {
        guard let key = key ?? itemOrder.first else { return }
        presentation.show(key)
    }


    #if DEBUG
    func showAIUsageForDiagnostics() -> NSWindow? {
        showPopover(for: MenuBarModule.aiUsage.rawValue)
        return popover.contentViewController?.view.window
    }
    var aiUsageDiagnosticImage: NSImage? { items[MenuBarModule.aiUsage.rawValue]?.button?.image }
    func closeDiagnosticPopover() { presentation.close() }
    func showWeatherForDiagnostics() -> [String: Any] {
        showPopover(for: MenuBarModule.weather.rawValue)
        let image = items[MenuBarModule.weather.rawValue]?.button?.image
        return ["weatherItem": items[MenuBarModule.weather.rawValue] != nil,
                "hasImage": image != nil, "imageWidth": image?.size.width ?? 0,
                "popoverShown": popover.isShown, "popoverWidth": popover.contentSize.width,
                "popoverHeight": popover.contentSize.height,
                "hasSelectedLocation": WeatherService.shared.location != nil]
    }
    #endif

    // MARK: Right-click menu

    private func showQuickMenu(for key: String) {
        guard let item = items[key] else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "MacPocket’ı aç"), action: #selector(openMainWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Ayarlar"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: String(localized: "Komut Çubuğu’nu Aç"), action: #selector(openCommandBar), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Dosya Rafı’nı Aç"), action: #selector(openShelf), keyEquivalent: "").target = self
        if PocketModule.displays.isAvailable(), DisplayBrightnessService.shared.schedule.enabled, DisplayBrightnessService.shared.schedule.source == .solar {
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

    @objc private func openCommandBar() {
        if PocketModule.commandBar.isAvailable() { CommandBarService.shared.show() }
        else { model.navigation.open(.commandBar); model.openMainWindow?() }
    }

    @objc private func openShelf() {
        if PocketModule.shelf.isAvailable() { ShelfService.shared.show() }
        else { model.navigation.open(.shelf); model.openMainWindow?() }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        model.openSettingsWindow?()
    }

    @objc private func pauseNightMode() { NightModeService.shared.pauseForAnHour() }

    @objc private func resumeNightMode() { NightModeService.shared.resume() }

    @objc private func quit() { NSApp.terminate(nil) }

}

/// Readings for the modules whose state lives outside the system snapshot.
@MainActor enum MenuBarExternalReadings {
    static func reading(for module: MenuBarModule, model: PocketModel, settings: MenuBarModuleSettings, now: Date = Date()) -> MenuBarReading? {
        switch module {
        case .awake:
            return MenuBarFormatter.awakeReading(model.awakeSession, now: now)
        case .focus:
            let focus = FocusSessionService.shared
            return MenuBarFormatter.focusReading(startedAt: focus.startedAt, endsAt: focus.endsAt, now: now)
        case .bluetooth:
            guard PocketModule.bluetoothBattery.isAvailable() else {
                return MenuBarReading(lines: ["—"], reserve: ["—"], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Bluetooth Pilleri modülü kapalı"), symbol: "dot.radiowaves.left.and.right")
            }
            return MenuBarFormatter.bluetoothReading(BluetoothBatteryService.shared.devices, decimals: settings.decimals)
        default:
            return nil
        }
    }
}

@MainActor
final class PocketApplicationState: ObservableObject {
    let model: PocketModel
    let loginItem: LoginItemController
    let statusItem: PocketStatusItemController

    init() {
        #if DEBUG
        ModuleRuntimeAudit.prepareIfRequested()
        WindowSwitcherRuntimeAudit.prepareIfRequested()
        AIUsageRuntimeAudit.prepareIfRequested()
        #endif
        let model = PocketModel()
        self.model = model
        loginItem = LoginItemController()
        statusItem = PocketStatusItemController(model: model)
        PocketModuleRuntime.shared.start(model: model)
        #if DEBUG
        if !ModuleRuntimeAudit.requested && !AIUsageFixtures.requested { _ = UpdateService.shared }
        #else
        _ = UpdateService.shared
        #endif
    }
}

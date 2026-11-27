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
            // Captured before the popover can activate MacPocket: the clipboard tab pastes into this app.
            let target = NSWorkspace.shared.frontmostApplication
            let hosting = NSHostingController(rootView: PocketMenuBarView(model: self.model, history: self.history, content: content,
                                                                          close: { [weak self] in self?.closePopover() },
                                                                          pasteTarget: target))
            hosting.sizingOptions = [.preferredContentSize]
            return hosting
        }, didClose: { [weak self] in self?.model.menuBarProcessesWanted = false })
    private var subscriptions = Set<AnyCancellable>()
    /// Advances the keep-awake countdown while monitoring is paused (samples drive `refresh` otherwise).
    private var clock: Timer?
    /// Brightness and night mode are observed only once their module is in the menu bar.
    private var observesDisplays = false
    /// Redraws the clock item on the second (with seconds) or on the minute boundary.
    private var timeTimer: Timer?
    private var timeTimerShowsSeconds = false

    init(model: PocketModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = true
        updateAppearance()
        refresh()
        // Observation (not Combine) drives the menu bar: only `system` and `paused` writes reach here.
        observe({ [model] in model.system }) { controller, snapshot in
            if let snapshot {
                controller.history.record(snapshot)
                MenuBarInsights.shared.record(snapshot)
            }
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
        // The clipboard item and tab come and go with clipboard history; its count follows the history.
        ClipboardService.shared.$history.map(\.items.count).removeDuplicates()
            .combineLatest(ClipboardService.shared.$settings.map(\.enabled).removeDuplicates())
            .dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
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

    /// The dropdown always follows the macOS light or dark appearance, like the menu bar it hangs from,
    /// whatever the main window's own appearance is set to.
    private func updateAppearance() {
        popover.animates = !PocketReduceMotion.isEnabled
        if popover.appearance != nil { popover.appearance = nil }
    }

    // MARK: Items

    private func desiredKeys(_ preferences: MenuBarPreferences) -> [String] {
        let items = preferences.items(available: \.isRuntimeAvailable)
        return (items.showsGroupedItem ? [Self.groupedKey] : []) + items.modules.map(\.rawValue)
    }

    private func refresh() {
        let preferences = store.preferences
        let keys = desiredKeys(preferences)
        if keys != itemOrder { rebuildItems(keys) }
        let snapshot = model.system
        for key in keys {
            guard let button = items[key]?.button else { continue }
            let appearance = button.effectiveAppearance
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
                var moduleKey = MenuBarRenderer.moduleKey(module, settings: settings, reading: reading, snapshot: snapshot, history: history)
                // Colored items resolve their label color for the bar's appearance, so they re-render when it
                // flips.
                moduleKey.parts.append(dark ? "dark" : "light")
                renderKey = moduleKey
                image = {
                    if module == .aiUsage, let image = AIUsageMenuBarImage.make(service: .shared, settings: settings, dark: dark) { return image }
                    return MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: snapshot, history: self.history,
                                                  appearance: appearance)
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
                var groupedKey = MenuBarRenderer.groupedKey(state)
                groupedKey.parts.append(dark ? "dark" : "light")
                renderKey = groupedKey
                image = { MenuBarRenderer.grouped(state, appearance: appearance) }
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
        updateTimeTimer(keys)
        if keys.contains(MenuBarModule.display.rawValue) { observeDisplays() }
    }

    private func observeDisplays() {
        guard !observesDisplays, PocketModule.displays.isAvailable() else { return }
        observesDisplays = true
        DisplayBrightnessService.shared.$displays.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
        NightModeService.shared.$status.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
    }

    private func updateTimeTimer(_ keys: [String]) {
        guard keys.contains(MenuBarModule.clock.rawValue) else {
            timeTimer?.invalidate()
            timeTimer = nil
            return
        }
        let seconds = store.preferences.settings(for: .clock).value == .clockTimeSeconds
        guard timeTimer == nil || timeTimerShowsSeconds != seconds else { return }
        timeTimer?.invalidate()
        timeTimerShowsSeconds = seconds
        let now = Date()
        let interval: TimeInterval = seconds ? 1 : 60
        let first = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval + interval)
        let timer = Timer(fire: first, interval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = seconds ? 0.05 : 0.5
        RunLoop.main.add(timer, forMode: .common)
        timeTimer = timer
    }

    private func updateClock(_ keys: [String]) {
        let awake = keys.contains(MenuBarModule.awake.rawValue) && model.awakeSession?.active == true && model.awakeSession?.endsAt != nil
        if awake {
            guard clock == nil else { return }
            let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else {
            clock?.invalidate()
            clock = nil
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

    /// Called from inside the popover; a method so the lazy presenter does not reference itself.
    private func closePopover() { presentation.close() }

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

    @objc private func quit() { NSApp.terminate(nil) }

}

/// Readings for the modules whose state lives outside the system snapshot.
@MainActor enum MenuBarExternalReadings {
    static func reading(for module: MenuBarModule, model: PocketModel, settings: MenuBarModuleSettings, now: Date = Date()) -> MenuBarReading? {
        switch module {
        case .awake:
            return MenuBarFormatter.awakeReading(model.awakeSession, now: now)
        case .bluetooth:
            guard PocketModule.bluetoothBattery.isAvailable() else {
                return MenuBarReading(lines: ["—"], reserve: ["—"], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Bluetooth Pilleri modülü kapalı"), symbol: "dot.radiowaves.left.and.right")
            }
            return MenuBarFormatter.bluetoothReading(BluetoothBatteryService.shared.devices, decimals: settings.decimals)
        case .clock:
            return MenuBarFormatter.clockReading(value: settings.value, zoneID: settings.timeZoneID, now: now)
        case .overview, .health:
            guard let snapshot = model.system else { return nil }
            let report = MenuBarInsights.shared.health(snapshot, processes: model.processes)
            return MenuBarReading(lines: ["\(report.score)"], reserve: ["100"], fraction: Double(report.score) / 100, magnitude: Double(report.score),
                                  accessibility: String(localized: "Sağlık puanı \(report.score)"), symbol: module.symbol)
        case .timeline:
            let count = MenuBarInsights.shared.events.events.count
            return MenuBarReading(lines: ["\(count)"], reserve: ["999"], fraction: nil, magnitude: Double(count),
                                  accessibility: String(localized: "\(count) olay"), symbol: module.symbol)
        case .launcher:
            let count = LauncherStore.shared.items.count
            return MenuBarReading(lines: ["\(count)"], reserve: ["99"], fraction: nil, magnitude: Double(count),
                                  accessibility: String(localized: "\(count) favori"), symbol: module.symbol)
        case .clipboard:
            let count = ClipboardService.shared.history.items.count
            return MenuBarReading(lines: ["\(count)"], reserve: ["999"], fraction: nil, magnitude: Double(count),
                                  accessibility: String(localized: "Pano geçmişinde \(count) öğe"), symbol: "doc.on.clipboard")
        case .display:
            guard PocketModule.displays.isAvailable() else {
                return MenuBarReading(lines: ["—"], reserve: ["—"], fraction: nil, magnitude: nil,
                                      accessibility: String(localized: "Ekran Ayarları modülü kapalı"), symbol: "sun.max")
            }
            let displays = DisplayBrightnessService.shared.displays
            let main = displays.first { $0.id == CGMainDisplayID() } ?? displays.first
            let night: MenuBarNightState = switch NightModeService.shared.status {
            case let .active(target): .active(night: target.night)
            case .paused: .paused
            case .off, .needsLocation: .off
            }
            return MenuBarFormatter.displayReading(level: main?.level, displays: displays.count, night: night)
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

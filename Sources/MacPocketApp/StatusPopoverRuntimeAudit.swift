#if DEBUG
import AppKit
import MacPocketCore

/// Exercises real status buttons and NSPopover animations without starting ordinary services.
@MainActor enum StatusPopoverRuntimeAudit {
    static var requested: Bool { CommandLine.arguments.contains("--audit-status-popover") }
    static func configureIfRequested() {
        guard requested else { return }
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        values[PocketPreferenceKey.showWindowAtLaunch] = false
        for module in PocketModule.allCases { values[module.availabilityKey] = false }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }
    static func launch() {
        guard let index = CommandLine.arguments.firstIndex(of: "--audit-status-popover"), CommandLine.arguments.indices.contains(index + 1) else { NSApp.terminate(nil); return }
        let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        Task { await run(destination); NSApp.terminate(nil) }
    }
    private static func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    private static func run(_ destination: URL) async {
        let fixture = Fixture()
        defer { fixture.removeItems() }
        var checks: [String: Bool] = [:]
        checks["statusAnchorsReady"] = await wait { fixture.items.values.allSatisfy { $0.button?.window?.isVisible == true } }
        NSApp.activate(ignoringOtherApps: true)
        checks["hostActiveBeforeInput"] = await wait { NSApp.isActive }
        try? await Task.sleep(for: .milliseconds(150))
        for animated in [true, false] {
            fixture.popover.animates = animated
            let prefix = animated ? "animated." : "immediate."
            fixture.click("weather")
            checks[prefix + "firstClickOpensWeather"] = await wait { fixture.shows("weather") }
            fixture.click("ai")
            checks[prefix + "oneClickWeatherToAI"] = await wait { fixture.shows("ai") }
            try? await Task.sleep(for: .milliseconds(250))
            checks[prefix + "oldCloseCannotClearNewContent"] = fixture.shows("ai")
            checks[prefix + "onlyNewItemHighlighted"] = fixture.items["ai"]?.button?.cell?.isHighlighted == true && fixture.items["weather"]?.button?.cell?.isHighlighted == false
            fixture.click("weather")
            checks[prefix + "oneClickAIToWeather"] = await wait { fixture.shows("weather") }
            fixture.click("weather")
            checks[prefix + "sameItemCloses"] = await wait { fixture.closed }
            fixture.click("weather")
            checks[prefix + "oneClickReopens"] = await wait { fixture.shows("weather") }

            // AppKit's transient dismissal may precede the next button's mouse-up action.
            fixture.popover.performClose(nil)
            fixture.click("ai")
            checks[prefix + "transientCloseBeforeNextAction"] = await wait { fixture.shows("ai") }
            fixture.click("weather")
            fixture.click("grouped")
            checks[prefix + "rapidClicksKeepLatestTarget"] = await wait { fixture.shows("grouped") }
            fixture.click("weather")
            fixture.presenter.close()
            checks[prefix + "explicitCloseCancelsPendingSwitch"] = await wait { fixture.closed }

            fixture.click("weather")
            _ = await wait { fixture.shows("weather") }
            fixture.click("ai")
            fixture.click("ai")
            checks[prefix + "doubleClickTargetEndsClosed"] = await wait { fixture.closed }

            fixture.click("weather")
            _ = await wait { fixture.shows("weather") }
            fixture.click("ai")
            fixture.presenter.show("weather")
            checks[prefix + "quickLookDuringCloseIsPreserved"] = await wait { fixture.shows("weather") }
            fixture.presenter.close()
            _ = await wait { fixture.closed }
        }
        // Local mouse events target only this process's status windows, without global input/TCC.
        fixture.popover.animates = true
        let weatherClick = await fixture.mouseClick("weather")
        let weatherShown = await waitShown(fixture, "weather")
        checks["localMouseClickOpensWeather"] = weatherClick && weatherShown
        let aiClick = await fixture.mouseClick("ai")
        let aiShown = await waitShown(fixture, "ai")
        checks["localMouseClickSwitchesToAI"] = aiClick && aiShown
        fixture.presenter.close()
        checks["finalCloseReleasesContent"] = await wait { fixture.closed }
        var timings: [[String: Any]] = []
        for animated in [true, false] {
            fixture.popover.animates = animated
            for (index, key) in ["weather", "ai", "weather", "ai", "weather", "ai", "weather", "ai", "weather", "ai"].enumerated() {
                let previousShows = fixture.completedShows
                let start = ProcessInfo.processInfo.systemUptime
                fixture.click(key)
                let finished = await wait { fixture.completedShows > previousShows && fixture.shows(key) }
                checks["timed.\(animated).\(index)"] = finished
                if finished {
                    timings.append(["animated": animated, "operation": index == 0 ? "open" : "switch", "target": key,
                        "clickToDidShowMS": (fixture.lastDidShowTime - start) * 1_000])
                }
            }
            fixture.presenter.close()
            _ = await wait { fixture.closed }
        }
        let report: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks,
            "statusButtonActions": fixture.actions, "userSettingsChanged": false, "realCredentialReads": false,
            "timings": timings, "timingBoundary": "status-button action to NSPopover.didShowNotification; fixture content",
            "inputMode": "native-status-button-actions-and-own-window-mouse-events"]
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: destination) }
    }
    private static func waitShown(_ fixture: Fixture, _ key: String) async -> Bool { await wait { fixture.shows(key) } }

    @MainActor private final class Fixture: NSObject {
        let popover = NSPopover()
        var items: [String: NSStatusItem] = [:]
        var actions: [String] = []
        var completedShows = 0
        var lastDidShowTime: TimeInterval = 0
        private var shownObserver: NSObjectProtocol?
        lazy var presenter = StatusItemPopoverPresenter(popover: popover, button: { [weak self] in self?.items[$0]?.button }, content: { key in
            let controller = NSViewController()
            controller.representedObject = key
            let label = NSTextField(labelWithString: key == "weather" ? String(localized: "Hava Durumu") : key == "ai" ? String(localized: "AI Kotaları") : String(localized: "Sistem durumu"))
            label.frame = NSRect(x: 20, y: 40, width: 260, height: 30)
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            controller.view.addSubview(label)
            return controller
        }, didClose: {})
        override init() {
            super.init()
            popover.behavior = .transient
            shownObserver = NotificationCenter.default.addObserver(forName: NSPopover.didShowNotification, object: popover, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.completedShows += 1
                    self?.lastDidShowTime = ProcessInfo.processInfo.systemUptime
                }
            }
            for (key, symbol) in [("weather", "cloud.sun"), ("ai", "sparkle"), ("grouped", "chart.bar")] {
                let item = NSStatusBar.system.statusItem(withLength: 28)
                item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                item.button?.target = self; item.button?.action = #selector(toggle(_:))
                item.button?.sendAction(on: .leftMouseUp)
                items[key] = item
            }
        }
        @objc private func toggle(_ sender: NSStatusBarButton) {
            guard let key = items.first(where: { $0.value.button === sender })?.key else { return }
            actions.append(key)
            presenter.toggle(key)
        }
        func click(_ key: String) {
            guard let button = items[key]?.button else { return }
            NSApp.sendAction(button.action!, to: button.target, from: button)
        }
        func mouseClick(_ key: String) async -> Bool {
            guard let button = items[key]?.button, let window = button.window else { return false }
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let before = actions.count
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { return false }
                NSApp.postEvent(event, atStart: false)
            }
            try? await Task.sleep(for: .milliseconds(150))
            return actions.count == before + 1
        }
        func shows(_ key: String) -> Bool { popover.isShown && presenter.owner == key && popover.contentViewController?.representedObject as? String == key }
        var closed: Bool { !popover.isShown && presenter.owner == nil && popover.contentViewController == nil }
        func removeItems() {
            if let shownObserver { NotificationCenter.default.removeObserver(shownObserver) }
            shownObserver = nil
            presenter.close()
            for item in items.values { NSStatusBar.system.removeStatusItem(item) }
            items.removeAll()
        }
    }
}
#endif

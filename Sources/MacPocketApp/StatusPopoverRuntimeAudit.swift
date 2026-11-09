#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

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
        NSApp.setActivationPolicy(.regular)
        let fixture = Fixture()
        defer { fixture.removeItems() }
        var checks: [String: Bool] = [:]
        checks["statusAnchorsReady"] = await wait { fixture.items.values.allSatisfy { $0.button?.window?.isVisible == true } }
        NSApp.activate(ignoringOtherApps: true)
        let hostActiveBeforeInput = NSApp.isActive
        try? await Task.sleep(for: .milliseconds(150))
        for animated in [true, false] {
            fixture.popover.animates = animated
            let prefix = animated ? "animated." : "immediate."
            fixture.click("weather")
            checks[prefix + "firstClickOpensWeather"] = await wait { fixture.shows("weather") }
            let firstWindow = fixture.popover.contentViewController?.view.window
            let closesBeforeSwitch = fixture.completedCloses
            fixture.click("ai")
            checks[prefix + "oneClickWeatherToAI"] = await wait { fixture.shows("ai") }
            checks[prefix + "switchKeepsSameWindow"] = fixture.popover.contentViewController?.view.window === firstWindow
            checks[prefix + "switchDoesNotDismiss"] = fixture.completedCloses == closesBeforeSwitch
            checks[prefix + "newContentSizeApplied"] = await wait { abs(fixture.popover.contentSize.height - 120) < 1 }
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
        let closesBeforeMouseSwitch = fixture.completedCloses
        let mouseWindow = fixture.popover.contentViewController?.view.window
        let aiClick = await fixture.mouseClick("ai")
        let aiShown = await waitShown(fixture, "ai")
        checks["localMouseClickSwitchesToAI"] = aiClick && aiShown
        checks["localMouseSwitchKeepsOpenWindow"] = fixture.completedCloses == closesBeforeMouseSwitch && fixture.popover.contentViewController?.view.window === mouseWindow
        let closesBeforeSameItem = fixture.completedCloses
        _ = await fixture.mouseClick("ai")
        let sameItemClosed = await wait { fixture.closed }
        checks["localMouseSameItemCloses"] = sameItemClosed && fixture.completedCloses > closesBeforeSameItem
        let showsBeforeEscape = fixture.completedShows
        fixture.click("weather")
        _ = await wait { fixture.shows("weather") && fixture.completedShows > showsBeforeEscape }
        await fixture.outsideClick()
        checks["outsideMouseClickDismisses"] = await wait { fixture.closed }
        fixture.click("weather")
        _ = await wait { fixture.shows("weather") }
        fixture.pressEscape()
        checks["escapeDismisses"] = await wait { fixture.closed }
        fixture.presenter.close()
        checks["finalCloseReleasesContent"] = await wait { fixture.closed }
        var timings: [[String: Any]] = []
        for animated in [true, false] {
            fixture.popover.animates = animated
            for (index, key) in ["weather", "ai", "weather", "ai", "weather", "ai", "weather", "ai", "weather", "ai"].enumerated() {
                let previousShows = fixture.completedShows
                let previousCloses = fixture.completedCloses
                let originalWindow = fixture.popover.contentViewController?.view.window
                let start = ProcessInfo.processInfo.systemUptime
                fixture.click(key)
                let finished = await wait { fixture.shows(key) && (index > 0 || fixture.completedShows > previousShows) }
                checks["timed.\(animated).\(index)"] = finished
                if finished {
                    let elapsed = ((index == 0 ? fixture.lastDidShowTime : ProcessInfo.processInfo.systemUptime) - start) * 1_000
                    timings.append(["animated": animated, "operation": index == 0 ? "open" : "switch", "target": key,
                        "elapsedMS": elapsed, "boundary": index == 0 ? "didShow" : "target-view-attached",
                        "sameWindow": index > 0 && fixture.popover.contentViewController?.view.window === originalWindow,
                        "closes": fixture.completedCloses - previousCloses])
                }
            }
            fixture.presenter.close()
            _ = await wait { fixture.closed }
        }
        let report: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks,
            "statusButtonActions": fixture.actions, "userSettingsChanged": false, "realCredentialReads": false,
            "hostActiveBeforeInput": hostActiveBeforeInput,
            "timings": timings, "timingBoundary": "open: didShow; switch: new target view attached to same visible window (not animation completion); fixture content",
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
        var completedCloses = 0
        private var shownObserver: NSObjectProtocol?
        private var closedObserver: NSObjectProtocol?
        lazy var presenter = StatusItemPopoverPresenter(popover: popover, buttons: { [weak self] in self?.items.compactMapValues(\.button) ?? [:] }, content: { key in
            if key == "grouped" {
                let hosting = NSHostingController(rootView: Text("Sistem durumu").frame(width: 300, height: 180))
                hosting.sizingOptions = [.preferredContentSize]
                hosting.representedObject = key
                return hosting
            }
            let controller = NSViewController()
            controller.representedObject = key
            let label = NSTextField(labelWithString: key == "weather" ? String(localized: "Hava Durumu") : key == "ai" ? String(localized: "AI Kotaları") : String(localized: "Sistem durumu"))
            label.frame = NSRect(x: 20, y: 40, width: 260, height: 30)
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: key == "weather" ? 220 : 120))
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
            closedObserver = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.completedCloses += 1 }
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
        func outsideClick() async {
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 160, height: 100), styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.orderFront(nil)
            defer { window.close() }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 40, y: 40), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        func pressEscape() {
            guard let window = popover.contentViewController?.view.window else { return }
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
        }
        func shows(_ key: String) -> Bool {
            popover.isShown && presenter.owner == key && popover.contentViewController?.representedObject as? String == key
                && popover.contentViewController?.view.window?.isVisible == true
        }
        var closed: Bool { !popover.isShown && presenter.owner == nil && popover.contentViewController == nil }
        func removeItems() {
            if let shownObserver { NotificationCenter.default.removeObserver(shownObserver) }
            if let closedObserver { NotificationCenter.default.removeObserver(closedObserver) }
            shownObserver = nil
            presenter.close()
            for item in items.values { NSStatusBar.system.removeStatusItem(item) }
            items.removeAll()
        }
    }
}
#endif

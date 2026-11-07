import AppKit
import Foundation

@MainActor final class FixtureWindow: NSWindow {
    var contentMouseEvents = 0
    override func sendEvent(_ event: NSEvent) {
        if (event.type == .leftMouseDown || event.type == .leftMouseUp),
           contentView?.bounds.contains(event.locationInWindow) == true { contentMouseEvents += 1 }
        super.sendEvent(event)
    }
}

/// A separate, owned acceptance target. Commands operate only on windows created here.
@MainActor final class WindowSwitcherFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let folder: URL
    var windows: [String: NSWindow] = [:]
    var sequence = 0
    var timer: Timer?
    var closing = false
    var exitRequested = false
    var repaint = false
    var fullscreenPhase: [ObjectIdentifier: String] = [:]
    init(folder: URL) { self.folder = folder }
    func applicationDidFinishLaunching(_ notification: Notification) {
        windows["A"] = makeWindow("A", color: NSColor(srgbRed: 0.85, green: 0.08, blue: 0.08, alpha: 1))
        windows["B"] = makeWindow("B", color: NSColor(srgbRed: 0.08, green: 0.75, blue: 0.12, alpha: 1))
        windows["A"]?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        writeState()
    }
    func makeWindow(_ key: String, color: NSColor) -> NSWindow {
        let window = FixtureWindow(contentRect: NSRect(x: 140, y: 190, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.tabbingMode = .disallowed; window.delegate = self
        window.title = String(localized: "MacPocket · Masaüstü testi")
        window.collectionBehavior = [.fullScreenPrimary]
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        content.wantsLayer = true; content.layer?.backgroundColor = color.cgColor
        let label = NSTextField(labelWithString: key)
        label.font = .systemFont(ofSize: 32, weight: .bold); label.textColor = .white
        label.frame = NSRect(x: 24, y: 262, width: 100, height: 42)
        content.addSubview(label); window.contentView = content
        window.orderFront(nil)
        fullscreenPhase[ObjectIdentifier(window)] = "windowed"
        return window
    }
    func tick() {
        if let data = try? Data(contentsOf: folder.appendingPathComponent("command.json")),
           let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let next = command["sequence"] as? Int, next > sequence, let action = command["action"] as? String {
            sequence = next
            let key = command["key"] as? String ?? "A"
            let window = windows[key]
            switch action {
            case "create": windows[key] = makeWindow(key, color: .systemPurple)
            case "focus": NSApp.unhideWithoutActivation(); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
            case "move":
                if let x = command["x"] as? Double, let y = command["y"] as? Double { window?.setFrameOrigin(CGPoint(x: x,y: y)) }
            case "badge": NSApp.dockTile.badgeLabel = command["label"] as? String;NSApp.dockTile.display()
            case "repaint":
                repaint.toggle()
                window?.contentView?.layer?.backgroundColor = (repaint
                    ? NSColor(srgbRed: 0.08, green: 0.12, blue: 0.85, alpha: 1)
                    : NSColor(srgbRed: 0.85, green: 0.08, blue: 0.08, alpha: 1)).cgColor
                window?.displayIfNeeded()
            case "tabs":
                if let a = windows["A"], let b = windows["B"] {
                    a.tabbingMode = .preferred; b.tabbingMode = .preferred
                    a.addTabbedWindow(b, ordered: .above); a.tabGroup?.selectedWindow = a
                }
            case "rename": window?.title = String(localized: "MacPocket · Masaüstü testi") + " · " + key
            case "close": window?.close() // Intentionally retain the NSWindow/backing surface.
            case "release": window?.close(); windows[key] = nil
            case "reopen": window?.makeKeyAndOrderFront(nil)
            case "fullscreen": window?.toggleFullScreen(nil)
            case "exit": exitRequested = true
            default: break
            }
        }
        if exitRequested {
            if let fullscreen = windows.values.first(where: { $0.styleMask.contains(.fullScreen) }) {
                if !closing { closing = true; fullscreen.toggleFullScreen(nil) }
            } else if !closing {
                timer?.invalidate(); timer = nil
                for window in windows.values { window.close() }
                windows.removeAll(); writeState(); NSApp.terminate(nil); return
            }
        }
        writeState()
    }
    private func phase(_ value: String, _ notification: Notification) {
        if let window = notification.object as? NSWindow { fullscreenPhase[ObjectIdentifier(window)] = value }
        writeState()
    }
    func windowWillEnterFullScreen(_ notification: Notification) { phase("entering", notification) }
    func windowDidEnterFullScreen(_ notification: Notification) { phase("fullscreen", notification) }
    func windowWillExitFullScreen(_ notification: Notification) { phase("exiting", notification) }
    func windowDidExitFullScreen(_ notification: Notification) { closing = false; phase("windowed", notification) }
    func writeState() {
        var state: [String: Any] = ["pid": getpid(), "sequence": sequence, "active": NSApp.isActive, "hidden": NSApp.isHidden,
                                  "repaint": repaint, "processUptime": ProcessInfo.processInfo.systemUptime]
        state["dockBadge"] = NSApp.dockTile.badgeLabel ?? ""
        state["windows"] = windows.mapValues { window -> [String: Any] in
            ["id": window.windowNumber, "title": window.title, "visible": window.isVisible,
             "minimized": window.isMiniaturized, "fullscreen": window.styleMask.contains(.fullScreen),
             "fullscreenPhase": fullscreenPhase[ObjectIdentifier(window)] ?? "unknown",
             "x": window.frame.minX, "y": window.frame.minY,
             "width": window.frame.width, "height": window.frame.height,
             "contentMouseEvents": (window as? FixtureWindow)?.contentMouseEvents ?? -1,
             "screenID": (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
             "key": window.isKeyWindow, "main": window.isMainWindow,
             "tabs": window.tabGroup?.windows.map(\.windowNumber) ?? [],
             "selectedTab": window.tabGroup?.selectedWindow?.windowNumber ?? -1]
        }
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("state.json"), options: .atomic)
        }
    }
}

@main struct FixtureApplication {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let driver = WindowSwitcherFixture(folder: folder)
        let application = NSApplication.shared
        application.setActivationPolicy(.regular); application.delegate = driver
        withExtendedLifetime(driver) { application.run() }
    }
}

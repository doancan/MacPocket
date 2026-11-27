import AppKit
import SwiftUI

@main @MainActor struct VisibilitySmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
    @MainActor final class Delegate: NSObject, NSApplicationDelegate {
        var visible = false
        var transitions: [Bool] = []
        func applicationDidFinishLaunching(_ notification: Notification) { Task { await run(); NSApp.terminate(nil) } }
        private func wait(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<100 {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return condition()
        }
        private func run() async {
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 240, height: 140), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            let controller = NSHostingController(rootView: Color.blue.frame(width: 240, height: 140).background(MainWindowVisibility { [weak self] in
                self?.visible = $0
                self?.transitions.append($0)
            }.frame(width: 1, height: 1).allowsHitTesting(false)))
            controller.sizingOptions = []
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 240, height: 140))
            var checks: [String: Bool] = [:]
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            checks["shown"] = await wait { visible }
            func probe(_ view: NSView) -> NSView? {
                if view is MainWindowVisibility.Probe { return view }
                return view.subviews.compactMap(probe).first
            }
            let initial: [String: Any] = ["windowVisible":window.isVisible,"occlusion":window.occlusionState.rawValue,
                "appHidden":NSApp.isHidden,"probeAttached":probe(controller.view)?.window != nil]
            window.orderOut(nil)
            checks["orderedOut"] = await wait { !visible }
            window.makeKeyAndOrderFront(nil)
            checks["orderedBack"] = await wait { visible }
            window.miniaturize(nil)
            checks["minimized"] = await wait { !visible && window.isMiniaturized }
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            checks["restored"] = await wait { visible && !window.isMiniaturized }
            let cover = NSWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
            cover.isReleasedWhenClosed = false
            cover.backgroundColor = .black
            cover.isOpaque = true
            cover.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
            cover.orderFrontRegardless()
            checks["covered"] = await wait { !visible }
            cover.close()
            checks["uncovered"] = await wait { visible }
            NSApp.hide(nil)
            checks["applicationHidden"] = await wait { !visible && NSApp.isHidden }
            NSApp.unhide(nil)
            window.makeKeyAndOrderFront(nil)
            checks["applicationUnhidden"] = await wait { visible && !NSApp.isHidden }
            window.close()
            checks["closed"] = await wait { !visible }
            window.contentViewController = nil
            let report: [String: Any] = ["passed":checks.values.allSatisfy { $0 },"checks":checks,"transitions":transitions,"initial":initial,"userPreferencesChanged":false]
            if CommandLine.arguments.count > 1, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
        }
    }
}

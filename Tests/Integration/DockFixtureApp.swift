import AppKit

/// A disposable external application for the Dock integration audit. Contains no user data.
@MainActor
private final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        for index in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: 100 + index * 100, y: 180 + index * 80, width: 480, height: 280),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Dock Fixture \(index + 1)"
            let label = NSTextField(wrappingLabelWithString: "Temporary MacPocket Dock preview test document \(index + 1).")
            label.frame = NSRect(x: 30, y: 100, width: 420, height: 80)
            label.font = .systemFont(ofSize: 22)
            window.contentView?.addSubview(label)
            windows.append(window)
            window.orderFront(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
private struct DockFixtureApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = FixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

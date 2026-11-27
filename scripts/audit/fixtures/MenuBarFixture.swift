import AppKit
import Foundation

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 32)
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor(deviceRed: 1, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 8, height: 16).fill()
        NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1).setFill()
        NSRect(x: 8, y: 0, width: 8, height: 16).fill()
        image.unlockFocus()
        image.isTemplate = false
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(pressed)
        item.button?.setAccessibilityLabel("MacPocket owned menu fixture")
        self.item = item
    }
    @objc private func pressed() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--pressed-receipt"), args.indices.contains(index + 1) else { return }
        try? Data("pressed".utf8).write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
    }
}
@main enum MenuBarFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

import AppKit
import Quartz

/// Own an embedded Quick Look view instead of taking control of the system's shared preview panel.
@MainActor
final class ShelfFilePreview: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var preview: QLPreviewView?
    private var urls: [URL] = []
    private var index = 0
    private let title = NSTextField(labelWithString: "")
    private var previous: NSButton?
    private var next: NSButton?
    var isVisible: Bool { panel?.isVisible == true && preview?.previewItem != nil }

    func show(_ urls: [URL], near source: NSWindow?) {
        guard !urls.isEmpty else { return }
        if isVisible { close(); return }
        self.urls = urls
        index = 0
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = String(localized: "Raf Önizlemesi")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.minSize = NSSize(width: 400, height: 320)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let root = NSView()
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.shouldCloseWithWindow = false
        preview.autostarts = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        let previous = NSButton(title: String(localized: "Önceki"), target: self, action: #selector(showPrevious))
        let next = NSButton(title: String(localized: "Sonraki"), target: self, action: #selector(showNext))
        previous.keyEquivalent = "\u{F702}"; previous.keyEquivalentModifierMask = []
        next.keyEquivalent = "\u{F703}"; next.keyEquivalentModifierMask = []
        let done = NSButton(title: String(localized: "Kapat"), target: self, action: #selector(closePreview))
        done.keyEquivalent = "\u{1B}"
        done.keyEquivalentModifierMask = []
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [previous, title, next, done])
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(preview)
        root.addSubview(controls)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor), preview.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            preview.topAnchor.constraint(equalTo: root.topAnchor), preview.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        panel.contentView = root
        self.panel = panel
        self.preview = preview
        self.previous = previous
        self.next = next
        update()
        if let screen = source?.screen ?? NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let width = min(panel.frame.width, area.width)
            let height = min(panel.frame.height, area.height)
            panel.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        preview?.previewItem = nil
        preview?.close()
        preview = nil
        urls = []
        previous = nil
        next = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }
    @objc private func closePreview() { close() }
    @objc private func showPrevious() { if index > 0 { index -= 1; update() } }
    @objc private func showNext() { if index + 1 < urls.count { index += 1; update() } }
    private func update() {
        guard urls.indices.contains(index) else { return }
        preview?.previewItem = urls[index] as NSURL
        title.stringValue = urls[index].lastPathComponent
        title.toolTip = title.stringValue
        panel?.title = title.stringValue
        previous?.isEnabled = index > 0
        next?.isEnabled = index + 1 < urls.count
    }
    #if DEBUG
    var diagnosticWindow: NSWindow? { panel }
    var diagnosticURL: URL? { preview?.previewItem?.previewItemURL ?? nil }
    #endif
}

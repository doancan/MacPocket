import AppKit
import MacPocketCore

/// The optional Disk Röntgeni menu bar item: System Data size, free space or just the icon, from the last scan.
/// It owns its own status item, separate from the app's main ones, and only exists while the user has switched it on.
@MainActor
final class SystemDataMenuBarController: NSObject {
    static let shared = SystemDataMenuBarController()

    private(set) var statusItem: NSStatusItem?
    private var shown: (style: SystemDataMenuBarStyle, summary: SystemDataSummary?)?
    private let statusBar: NSStatusBar
    private let defaults: UserDefaults
    private let openTool: () -> Void

    init(statusBar: NSStatusBar = .system, defaults: UserDefaults = .standard,
         openTool: @escaping () -> Void = { SystemDataRouting.open(tab: nil) }) {
        self.statusBar = statusBar; self.defaults = defaults; self.openTool = openTool
    }

    /// Cheap enough for the monitoring loop: nothing is touched unless the style or the numbers changed.
    func refresh() {
        let style = SystemDataMenuBarStyle.load(from: defaults)
        let summary = SystemDataSummary.load(from: defaults)
        if let shown, shown.style == style, shown.summary == summary { return }
        shown = (style, summary)
        guard style.showsItem else { remove(); return }
        let item = statusItem ?? statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "scope", accessibilityDescription: String(localized: "Disk Röntgeni"))
        button.imagePosition = style.title(for: summary) == nil ? .imageOnly : .imageLeading
        button.title = style.title(for: summary).map { " " + $0 } ?? ""
        button.toolTip = tooltip(summary)
        item.menu = menu(summary)
    }

    func remove() {
        if let statusItem { statusBar.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func tooltip(_ summary: SystemDataSummary?) -> String {
        guard let summary else { return String(localized: "Disk Röntgeni: henüz tarama yok") }
        func size(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file, spellsOutZero: false)) }
        return String(localized: "Sistem Verisi \(size(summary.systemDataBytes)), güvenle boşaltılabilir \(size(summary.safeBytes)), boş alan \(size(summary.freeBytes))")
    }

    private func menu(_ summary: SystemDataSummary?) -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: String(localized: "Disk Röntgeni’ni Aç"), action: #selector(openPage), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if let summary {
            menu.addItem(.separator())
            let info = NSMenuItem(title: tooltip(summary), action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            let date = NSMenuItem(title: String(localized: "Son tarama: \(summary.date.formatted(date: .abbreviated, time: .shortened))"), action: nil, keyEquivalent: "")
            date.isEnabled = false
            menu.addItem(date)
        }
        return menu
    }

    @objc private func openPage() { openTool() }
}

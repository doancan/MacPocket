import AppKit
import Combine
import MacPocketCore
import SwiftUI

/// An AppKit status item owns the popover independently of the main window.
@MainActor
final class PocketStatusItemController: NSObject {
    private let model: PocketModel
    private var items: [String: NSStatusItem] = [:]
    private var itemOrder: [String] = []
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(model: PocketModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 500)
        popover.contentViewController = NSHostingController(rootView: PocketMenuBarView(model: model))
        refresh()
        model.$system.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .pocketQuickLook)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.showPopover() }
            }.store(in: &subscriptions)
    }

    private func refresh() {
        let defaults = UserDefaults.standard
        switch PocketAppearance(rawValue: defaults.string(forKey: "MacPocket.appearance") ?? "dark") {
        case .dark: popover.appearance = NSAppearance(named: .darkAqua)
        case .light: popover.appearance = NSAppearance(named: .aqua)
        case .system, .none: popover.appearance = nil
        }
        let visible = defaults.object(forKey: "MacPocket.showMenuBar") as? Bool ?? true
        let metrics = StatusMetric.ordered(defaults).filter { $0.enabled(defaults) && ($0 != .battery || model.system?.power.batteryPresent == true) }
        let separate = defaults.string(forKey: "MacPocket.bar.layout") == "separate"
        let keys = !visible ? [] : separate && !metrics.isEmpty ? metrics.map(\.rawValue) : ["combined"]
        if keys != itemOrder {
            popover.close()
            for item in items.values { NSStatusBar.system.removeStatusItem(item) }
            items = [:]; itemOrder = keys
            // macOS places successive new items to the left of the previous one.
            for key in keys.reversed() {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(togglePopover(_:))
                items[key] = item
            }
        }
        for key in keys {
            guard let button = items[key]?.button else { continue }
            let selected = key == "combined" ? metrics : metrics.filter { $0.rawValue == key }
            let descriptions = selected.map { statusMetricValue($0, snapshot: model.system, defaults: defaults).detail }
            let summary = descriptions.isEmpty ? "MacPocket" : descriptions.joined(separator: "\n")
            button.image = render(selected, defaults: defaults)
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = summary + (model.paused ? "\nİzleme duraklatıldı" : "")
            button.setAccessibilityLabel("MacPocket · " + summary)
        }
    }

    private func render(_ metrics: [StatusMetric], defaults: UserDefaults) -> NSImage {
        guard !metrics.isEmpty else {
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MacPocket") ?? NSImage()
            image.isTemplate = true
            return image
        }
        let style = defaults.string(forKey: "MacPocket.bar.style") ?? "text"
        let labels = defaults.object(forKey: "MacPocket.bar.labels") as? Bool ?? true
        let icons = defaults.object(forKey: "MacPocket.bar.icons") as? Bool ?? true
        let gap: CGFloat = defaults.bool(forKey: "MacPocket.bar.compact") ? 5 : 12
        let storedFont = defaults.double(forKey: "MacPocket.bar.fontSize")
        let font = NSFont.monospacedDigitSystemFont(ofSize: storedFont == 0 ? 12 : min(14, max(10, storedFont)), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let segments = metrics.map { metric -> (StatusMetric, StatusMetricValue, String, CGFloat) in
            let value = statusMetricValue(metric, snapshot: model.system, defaults: defaults)
            let showValue = style != "gaugeOnly" || value.fraction == nil
            let text = (labels ? metric.title + (showValue ? " " : "") : "") + (showValue ? value.text : "")
            let isPercent = metric == .cpu || metric == .battery
                || (metric == .memory && defaults.bool(forKey: "MacPocket.bar.memoryPercent"))
                || (metric == .disk && defaults.bool(forKey: "MacPocket.bar.diskPercent"))
            let reserveValue = isPercent ? (defaults.bool(forKey: "MacPocket.bar.decimals") ? "100.0%" : "100%") : metric == .power ? "Pil ↓" : "999.99 GB"
            let reserveText = (labels ? metric.title + (showValue ? " " : "") : "") + (showValue ? reserveValue : "")
            let width = max((text as NSString).size(withAttributes: attributes).width,
                            (reserveText as NSString).size(withAttributes: attributes).width)
                + (icons ? 19 : 0) + (style != "text" && value.fraction != nil ? 22 : 0)
            return (metric, value, text, max(12, width))
        }
        let width = segments.reduce(CGFloat(0)) { $0 + $1.3 } + gap * CGFloat(max(0, segments.count - 1))
        let image = NSImage(size: NSSize(width: ceil(width), height: 20), flipped: false) { _ in
            var x: CGFloat = 0
            for (metric, value, text, width) in segments {
                let segmentStart = x
                if icons {
                    NSImage(systemSymbolName: metric.symbol, accessibilityDescription: nil)?.draw(in: NSRect(x: x, y: 3, width: 15, height: 14))
                    x += 19
                }
                if style != "text", let fraction = value.fraction {
                    let outer = NSBezierPath(roundedRect: NSRect(x: x, y: 5, width: 17, height: 10), xRadius: 2, yRadius: 2)
                    NSColor.black.setStroke(); outer.lineWidth = 1; outer.stroke()
                    NSColor.black.setFill()
                    NSBezierPath(rect: NSRect(x: x + 2, y: 7, width: 13 * min(1, max(0, fraction)), height: 6)).fill()
                    x += 22
                }
                (text as NSString).draw(at: NSPoint(x: x, y: (20 - font.boundingRectForFont.height) / 2 - font.descender), withAttributes: attributes)
                x = segmentStart + width + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover(anchor: sender) }
    }

    private func showPopover(anchor: NSStatusBarButton? = nil) {
        guard let button = anchor ?? itemOrder.first.flatMap({ items[$0]?.button }), !popover.isShown else { return }
        if let view = popover.contentViewController?.view {
            popover.contentSize = NSSize(width: 330, height: min(680, max(420, view.fittingSize.height)))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

}

@MainActor
final class PocketApplicationState: ObservableObject {
    let model: PocketModel
    let loginItem: LoginItemController
    let statusItem: PocketStatusItemController

    init() {
        let model = PocketModel()
        self.model = model
        _ = WindowSwitcherHotkeyController.shared
        loginItem = LoginItemController()
        statusItem = PocketStatusItemController(model: model)
    }
}

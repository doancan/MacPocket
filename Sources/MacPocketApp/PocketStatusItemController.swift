import AppKit
import Combine
import MacPocketCore
import SwiftUI

/// An AppKit status item owns the popover independently of the main window.
@MainActor
final class PocketStatusItemController: NSObject {
    private let model: PocketModel
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(model: PocketModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 420)
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
        guard visible else {
            popover.close()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item?.button?.target = self
            item?.button?.action = #selector(togglePopover)
        }
        guard let button = item?.button else { return }
        let showCPU = defaults.object(forKey: "MacPocket.menuBarCPU") as? Bool ?? true
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MacPocket")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = showCPU ? .imageLeading : .imageOnly
        button.title = showCPU ? " " + model.cpuLabel : ""
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.toolTip = "MacPocket · CPU \(model.cpuLabel)"
        button.setAccessibilityLabel("MacPocket · CPU \(model.cpuLabel)")
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = item?.button, !popover.isShown else { return }
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
        loginItem = LoginItemController()
        statusItem = PocketStatusItemController(model: model)
    }
}

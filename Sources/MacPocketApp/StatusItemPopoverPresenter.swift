import AppKit

/// Serializes a shared popover's animated close and its next status-item presentation.
@MainActor
final class StatusItemPopoverPresenter: NSObject, NSPopoverDelegate {
    let popover: NSPopover
    private(set) var owner: String?
    private var closing = false
    private var pendingOwner: String?
    private let button: (String) -> NSStatusBarButton?
    private let content: (String) -> NSViewController?
    private let didClose: () -> Void

    init(popover: NSPopover, button: @escaping (String) -> NSStatusBarButton?,
         content: @escaping (String) -> NSViewController?, didClose: @escaping () -> Void) {
        self.popover = popover; self.button = button; self.content = content; self.didClose = didClose
        super.init()
        popover.delegate = self
    }

    func toggle(_ key: String) {
        if closing {
            if pendingOwner == key { pendingOwner = nil }
            else if pendingOwner != nil || owner != key { pendingOwner = key }
        } else if let owner {
            pendingOwner = owner == key ? nil : key
            beginClose()
        } else { present(key) }
    }

    func show(_ key: String) {
        if closing { pendingOwner = key }
        else if let owner {
            guard owner != key else { return }
            pendingOwner = key
            beginClose()
        } else { present(key) }
    }

    /// Also cancels a queued handoff, e.g. before a right-click menu or status-item rebuild.
    func close() {
        pendingOwner = nil
        if owner != nil && !closing { beginClose() }
    }

    private func beginClose() {
        // Mark it before AppKit can call the delegate synchronously (animations may be disabled).
        closing = true
        popover.performClose(nil)
    }

    private func present(_ key: String) {
        guard let anchor = button(key), anchor.window != nil, let controller = content(key) else { return }
        owner = key
        popover.contentViewController = controller
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        guard popover.isShown else { owner = nil; popover.contentViewController = nil; return }
        anchor.highlight(true)
        controller.view.window?.makeKey()
    }

    func popoverWillClose(_ notification: Notification) {
        // A transient popover can start closing on mouse-down, before the other item's action.
        closing = true
    }

    func popoverDidClose(_ notification: Notification) {
        if let owner { button(owner)?.highlight(false) }
        popover.contentViewController = nil
        didClose()
        // Leave the close notification before showing again. Keep the pending selection mutable
        // until then, so another click or a rebuild can replace/cancel it without a stale reopen.
        closing = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let next = self.pendingOwner
            self.pendingOwner = nil
            self.owner = nil
            self.closing = false
            if let next { self.present(next) }
        }
    }
}

import AppKit

/// Retargets the visible popover in place; queues requests only during an actual dismissal.
@MainActor
final class StatusItemPopoverPresenter: NSObject, NSPopoverDelegate {
    let popover: NSPopover
    private(set) var owner: String?
    private var closing = false
    private var pendingOwner: String?
    private let buttons: () -> [String: NSStatusBarButton]
    private let content: (String) -> NSViewController?
    private let didClose: () -> Void

    init(popover: NSPopover, buttons: @escaping () -> [String: NSStatusBarButton],
         content: @escaping (String) -> NSViewController?, didClose: @escaping () -> Void) {
        self.popover = popover
        self.buttons = buttons
        self.content = content
        self.didClose = didClose
        super.init()
        popover.delegate = self
    }

    func toggle(_ key: String) {
        if closing {
            if pendingOwner == key { pendingOwner = nil }
            else if pendingOwner != nil || owner != key { pendingOwner = key }
        } else if let owner {
            if owner == key { beginClose() }
            else { present(key) }
        } else { present(key) }
    }

    func show(_ key: String) {
        if closing { pendingOwner = key }
        else if let owner {
            guard owner != key else { return }
            present(key)
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
        let anchors = buttons()
        guard let anchor = anchors[key], anchor.window?.isVisible == true, let controller = content(key) else { return }
        let preferred = controller.preferredContentSize
        let fitting = preferred.width > 0 && preferred.height > 0 ? preferred : controller.view.fittingSize
        let targetSize = fitting.width > 0 && fitting.height > 0 ? fitting : controller.view.frame.size
        let previousOwner = owner
        owner = key
        popover.contentViewController = controller
        if targetSize.width > 0 && targetSize.height > 0 { popover.contentSize = targetSize }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        guard popover.isShown else { owner = nil; popover.contentViewController = nil; return }
        if let previousOwner, previousOwner != key { anchors[previousOwner]?.highlight(false) }
        anchor.highlight(true)
        controller.view.window?.makeKey()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard !closing else { return true }
        // The owning button keeps AppKit's normal click-to-dismiss behavior. Only another
        // MacPocket button needs protection from transient dismissal before its action.
        let anchors = buttons().filter { $0.key != owner }.values
        // Prefer the live pointer during global mouse-down handling: currentEvent may still
        // describe the previous status-item click when the new click is in another application.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            let point = NSEvent.mouseLocation
            return !anchors.contains(where: { button in
                guard let window = button.window, window.isVisible else { return false }
                return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
            })
        }
        // Keep the panel alive until our status button's mouse-up action can retarget it.
        if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp,
           ProcessInfo.processInfo.systemUptime - event.timestamp < 0.25,
           let window = event.window,
           anchors.contains(where: { button in
               button.window === window && button.bounds.contains(button.convert(event.locationInWindow, from: nil))
           }) { return false }
        return true
    }

    func popoverWillClose(_ notification: Notification) {
        // A transient popover can start closing on mouse-down, before the other item's action.
        closing = true
    }

    func popoverDidClose(_ notification: Notification) {
        if let owner { buttons()[owner]?.highlight(false) }
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

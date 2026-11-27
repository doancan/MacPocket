import AppKit
import SwiftUI

/// Tracks the containing window, including Hide, minimization and complete occlusion. `opened` reports only
/// whether the window is open at all (closed vs. shown), for work that must stop once it is closed.
struct MainWindowVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void
    var opened: (Bool) -> Void = { _ in }
    func makeNSView(context: Context) -> Probe { Probe(changed: changed, opened: opened) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.opened = opened }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }

    final class Probe: NSView {
        var changed: (Bool) -> Void
        var opened: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastVisible: Bool?
        private var lastOpen: Bool?
        init(changed: @escaping (Bool) -> Void, opened: @escaping (Bool) -> Void) {
            self.changed = changed
            self.opened = opened
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didExposeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                })
            }
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report(false)
                    self?.reportOpen(false)
                }
            })
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                })
            }
            evaluate()
        }
        private func evaluate() {
            guard let window else { report(false); return }
            report(window.isVisible && !window.isMiniaturized && !NSApp.isHidden && window.occlusionState.contains(.visible))
            // Minimized or covered windows stay open: rebuilding their page would lose its state.
            reportOpen(window.isVisible || window.isMiniaturized)
        }
        private func reportOpen(_ open: Bool) {
            guard open != lastOpen else { return }
            lastOpen = open
            opened(open)
        }
        private func report(_ visible: Bool) {
            guard visible != lastVisible else { return }
            lastVisible = visible
            changed(visible)
        }
        func stop() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            report(false)
        }
    }
}

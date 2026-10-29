import AppKit
import Combine
import SwiftUI

/// Own-app input shielding only. This never installs a global event tap or changes OS permissions.
@MainActor
final class ScreenCleaningController: ObservableObject {
    static let shared = ScreenCleaningController()
    enum Phase { case idle, countdown, active }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var remaining = 0
    @Published private(set) var failure: String?
    private var panels: [CleaningPanel] = []
    private var inputMonitor: Any?
    private var sessionID: UUID?
    private var session: Task<Void, Never>?
    private var hold: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private init() {
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            }.store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }.store(in: &subscriptions)
    }
    func start(seconds: Int) {
        guard phase == .idle else { return }
        failure = nil
        let duration = min(60, max(10, seconds))
        let id = UUID()
        sessionID = id
        phase = .countdown; remaining = 3
        session = Task { [weak self] in
            guard let self else { return }
            do {
                for value in (1...3).reversed() {
                    remaining = value
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                guard NSApp.isActive, !NSScreen.screens.isEmpty else { stop(); return }
                remaining = duration
                phase = .active
                present()
                let deadline = ProcessInfo.processInfo.systemUptime + Double(duration)
                while !Task.isCancelled {
                    remaining = max(0, Int(ceil(deadline - ProcessInfo.processInfo.systemUptime)))
                    if remaining == 0 { break }
                    try await Task.sleep(for: .milliseconds(200))
                }
            } catch { /* Cancellation is an exit path, never a reason to keep the overlay. */ }
            if sessionID == id { stop() }
        }
    }
    func stop() {
        sessionID = nil
        session?.cancel(); session = nil
        hold?.cancel(); hold = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels = []
        phase = .idle; remaining = 0
    }
    private func present() {
        for screen in NSScreen.screens {
            let panel = CleaningPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .black; panel.isOpaque = true; panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = true
            panel.contentView = NSHostingView(rootView: CleaningOverlayView(controller: self))
            panel.setFrame(screen.frame, display: true)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        panels.first?.makeKey()
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
            .otherMouseUp, .scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            let blocked = MainActor.assumeIsolated {
                guard let self, self.phase == .active else { return false }
                if event.type == .keyDown && event.keyCode == 53 { self.stop(); return true }
                if event.type == .leftMouseDown {
                    self.hold?.cancel()
                    self.hold = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation(); self?.stop() }
                        catch { }
                    }
                } else if event.type == .leftMouseUp {
                    self.hold?.cancel(); self.hold = nil
                }
                return true
            }
            return blocked ? nil : event
        }
        guard inputMonitor != nil else {
            failure = "Yerel giriş koruması başlatılamadı. Ekran temizleme modu kapatıldı."
            stop(); return
        }
    }
}

@MainActor
private final class CleaningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct CleaningOverlayView: View {
    @ObservedObject var controller: ScreenCleaningController
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Text("Ekran Temizleme").font(.headline)
                Text("\(controller.remaining) saniye sonra kapanır").monospacedDigit()
                Text("Esc ile çık · Fareyi 2 saniye basılı tutarak çık")
                Text("Sistem kısayolları kullanılabilir; başka uygulamaya geçmek bu modu kapatır.")
                    .font(.caption)
            }.font(.callout).foregroundStyle(.white.opacity(0.72)).padding(48)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).ignoresSafeArea()
    }
}

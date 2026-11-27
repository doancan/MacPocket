import AppKit
import ApplicationServices
import Combine
import MacPocketCore
import SwiftUI

extension CleaningColor {
    var nsColor: NSColor {
        switch self {
        case .black: .black
        case .white: .white
        case .gray: NSColor(white: 0.5, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var localizedTitle: String {
        switch self {
        case .black: String(localized: "Siyah")
        case .white: String(localized: "Beyaz")
        case .gray: String(localized: "Gri")
        }
    }
}

/// By default the shield is own-app input only. Only when the user turns on "lock input" (Accessibility
/// access) does a system-wide event tap run, and it always ends with Esc, the time limit, or leaving the app.
@MainActor
final class ScreenCleaningController: ObservableObject {
    static let shared = ScreenCleaningController()
    enum Phase { case idle, countdown, active }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var remaining = 0
    @Published private(set) var failure: String?
    @Published var settings = ScreenCleaningSettings.load(from: .standard) {
        didSet { if settings != oldValue { settings.save(to: .standard) } }
    }
    private var lockTap: CFMachPort?
    private var lockSource: CFRunLoopSource?
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
        if settings.locksInput, !AXIsProcessTrusted() {
            failure = String(localized: "Girişi kilitlemek için Erişilebilirlik izni gerekir. İzin verip tekrar dene ya da kilidi kapat.")
            return
        }
        let duration = min(60, max(10, seconds))
        let id = UUID()
        sessionID = id
        phase = .countdown
        remaining = 3
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
        session?.cancel()
        session = nil
        hold?.cancel()
        hold = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        removeLock()
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels = []
        phase = .idle
        remaining = 0
    }
    private func present() {
        for screen in NSScreen.screens {
            let panel = CleaningPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = settings.color.nsColor
            panel.isOpaque = true
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = true
            panel.contentView = NSHostingView(rootView: CleaningOverlayView(controller: self))
            panel.setFrame(screen.frame, display: true)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        panels.first?.makeKey()
        if settings.locksInput, !installLock() {
            failure = String(localized: "Giriş kilidi başlatılamadı. Ekran temizleme modu kapatıldı.")
            stop()
            return
        }
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
                    self.hold?.cancel()
                    self.hold = nil
                }
                return true
            }
            return blocked ? nil : event
        }
        guard inputMonitor != nil else {
            failure = String(localized: "Yerel giriş koruması başlatılamadı. Ekran temizleme modu kapatıldı.")
            stop()
            return
        }
    }
}


extension ScreenCleaningController {
    private static let systemDefinedMask = 1 << 14  // media, volume and brightness keys

    /// Drops keyboard and pointer input for every app until the session ends. The tap's source lives on the
    /// main run loop, so the callback runs on the main thread. Returns whether the tap is running.
    fileprivate func installLock() -> Bool {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                    .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(Self.systemDefinedMask) { $0 | (1 << Int($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<ScreenCleaningController>.fromOpaque(context).takeUnretainedValue()
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // A tap macOS switched off no longer blocks anything: end the session instead of pretending
                // it still does.
                Task { @MainActor in controller.stop() }
            case .keyDown, .keyUp:
                let decision = CleaningInputPolicy.decision(isKeyDown: type == .keyDown,
                                                            keyCode: event.getIntegerValueField(.keyboardEventKeycode))
                if decision == .exit { Task { @MainActor in controller.stop() } }
            default:
                break
            }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lockTap = tap
        lockSource = source
        return true
    }

    fileprivate func removeLock() {
        if let lockTap { CGEvent.tapEnable(tap: lockTap, enable: false) }
        if let lockSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), lockSource, .commonModes) }
        lockTap = nil
        lockSource = nil
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
        let color = controller.settings.color
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Text("Ekran Temizleme").font(.headline)
                Text("\(controller.remaining) saniye sonra kapanır").monospacedDigit()
                if controller.settings.locksInput {
                    Text("Klavye ve fare kilitli · Yalnız Esc ile çık")
                } else {
                    Text("Esc ile çık · Fareyi 2 saniye basılı tutarak çık")
                    Text("Sistem kısayolları kullanılabilir; başka uygulamaya geçmek bu modu kapatır.")
                        .font(.subheadline)
                }
            }
            .font(.callout)
            .foregroundStyle((color.usesDarkText ? Color.black : Color.white).opacity(0.72))
            .padding(48)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(color.color).ignoresSafeArea()
    }
}

import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

/// Intercepts ⌘Q / ⌘W system-wide (an active CGEvent tap, which needs Accessibility access) and lets them
/// through only when held long enough or pressed twice, as `QuitGuard` decides.
@MainActor
final class QuitGuardService: ObservableObject {
    static let shared = QuitGuardService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("QuitGuardService")
    #endif
    private(set) var moduleRunning = false

    @Published var settings: QuitGuardSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            configure()
        }
    }
    @Published private(set) var tapActive = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var machine = QuitGuard()
    private var ticker: Timer?
    private let hud = QuitGuardHUD()
    /// Marks the shortcut MacPocket sends after the guard is satisfied, so the tap lets it pass.
    private static let marker: Int64 = 0x4D50_5147

    private init() {
        settings = QuitGuardSettings.load(from: .standard)
    }

    func stopForModule() {
        moduleRunning = false
        remove()
        tapActive = false
    }

    func start() {
        guard !moduleRunning, PocketModule.quitGuard.isAvailable() else { return }
        moduleRunning = true
        configure()
    }

    /// Installs or removes the tap to match the settings and permission. Called again when the app activates,
    /// so granting Accessibility later takes effect without a relaunch.
    func configure() {
        let wanted = moduleRunning && settings.isActive && AXIsProcessTrusted()
        if wanted && tap == nil { install() }
        if !wanted && tap != nil { remove() }
        tapActive = tap != nil
    }

    private func install() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<QuitGuardService>.fromOpaque(context).takeUnretainedValue()
            // The tap's source is on the main run loop, so this runs on the main thread.
            let keep: Bool = MainActor.assumeIsolated { service.handle(type, event) }
            return keep ? Unmanaged.passUnretained(event) : nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func remove() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        stopTicker()
        hud.hide()
        machine = QuitGuard()
    }

    /// Returns false to drop the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .keyDown:
            let source = event.getIntegerValueField(.eventSourceUserData)
            // Its own re-sent shortcut, and keystrokes a macro posts on purpose, pass untouched.
            guard source != Self.marker, source != MacroService.marker,
                  let shortcut = Self.shortcut(of: event),
                  settings.protects(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return true }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return apply(machine.handle(.keyDown(shortcut, isRepeat: isRepeat, at: ProcessInfo.processInfo.systemUptime),
                                        mode: settings.mode(for:), holdDuration: settings.holdDuration,
                                        doublePressInterval: settings.doublePressInterval))
        case .keyUp:
            if machine.isHolding, Self.shortcut(ofKeyCode: event) != nil { release() }
            return true
        case .flagsChanged:
            if machine.isHolding, !event.flags.contains(.maskCommand) { release() }
            return true
        default:
            return true
        }
    }

    private func release() {
        _ = apply(machine.handle(.released(at: ProcessInfo.processInfo.systemUptime), mode: settings.mode(for:),
                                 holdDuration: settings.holdDuration, doublePressInterval: settings.doublePressInterval))
    }

    /// Carries out effects; returns whether the original event goes through.
    @discardableResult
    private func apply(_ effects: [QuitGuard.Effect]) -> Bool {
        var keep = true
        for effect in effects {
            switch effect {
            case .pass: keep = true
            case .swallow: keep = false; startTicker()
            case let .hint(shortcut, mode, progress): hud.show(shortcut, mode: mode, progress: progress)
            case .hideHint: hud.hide()
            case let .fire(shortcut): Self.send(shortcut)
            }
        }
        return keep
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.machine.handle(.tick(at: ProcessInfo.processInfo.systemUptime), mode: self.settings.mode(for:),
                                               holdDuration: self.settings.holdDuration,
                                               doublePressInterval: self.settings.doublePressInterval))
                if !self.machine.isHolding && !self.hud.isVisible { self.stopTicker() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// ⌘ alone plus Q or W.
    private static func shortcut(of event: CGEvent) -> GuardedShortcut? {
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard modifiers == .maskCommand else { return nil }
        return shortcut(ofKeyCode: event)
    }

    private static func shortcut(ofKeyCode event: CGEvent) -> GuardedShortcut? {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        return GuardedShortcut.allCases.first { $0.keyCode == code }
    }

    private static func send(_ shortcut: GuardedShortcut) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

// MARK: - HUD

/// A small glass pill under the menu bar: "Hold ⌘Q to quit" with progress, or "Press ⌘W again".
@MainActor
final class QuitGuardHUD {
    private var panel: NSPanel?
    private let state = QuitGuardHUDState()

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ shortcut: GuardedShortcut, mode: QuitGuardMode, progress: Double?) {
        state.shortcut = shortcut
        state.mode = mode
        state.progress = progress ?? 0
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 340, height: 64)
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24,
                              width: size.width, height: size.height), display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: QuitGuardHUDView(state: state))
        return panel
    }
}

@MainActor
private final class QuitGuardHUDState: ObservableObject {
    @Published var shortcut = GuardedShortcut.quit
    @Published var mode = QuitGuardMode.hold
    @Published var progress = 0.0
}

private struct QuitGuardHUDView: View {
    @ObservedObject var state: QuitGuardHUDState

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            ZStack {
                if state.mode == .hold {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
                    Circle().trim(from: 0, to: state.progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(verbatim: state.shortcut.symbol).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 34, height: 34)
            Text(message).font(.callout.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, PocketSpacing.l)
        .frame(height: 52)
        .modifier(QuitGuardHUDSurface())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        switch (state.shortcut, state.mode) {
        case (.quit, .hold): String(localized: "Çıkmak için ⌘Q’yu basılı tut")
        case (.quit, _): String(localized: "Çıkmak için ⌘Q’ya tekrar bas")
        case (.closeWindow, .hold): String(localized: "Kapatmak için ⌘W’yi basılı tut")
        case (.closeWindow, _): String(localized: "Kapatmak için ⌘W’ye tekrar bas")
        }
    }
}

/// Functional layer floating over any app: Liquid Glass.
private struct QuitGuardHUDSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .capsule)
    }
}

#if DEBUG
extension QuitGuardService {
    var moduleDiagnosticResources: [String: Int] { ["tap": tap == nil ? 0 : 1, "timer": ticker?.isValid == true ? 1 : 0] }
}
#endif

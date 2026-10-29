import AppKit
@preconcurrency import Carbon
import Combine
import SwiftUI

/// One opt-in, reversible Carbon registration; no passive key logging or permission grant.
@MainActor
final class WindowSwitcherHotkeyController: NSObject, ObservableObject {
    static let shared = WindowSwitcherHotkeyController()
    @Published private(set) var registrationMessage = "Global kısayol kapalı."
    private var keyRefs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var defaultsObserver: AnyCancellable?
    private var monitor: Any?
    private var panel: NSPanel?
    private var summoning = false
    private var pendingSteps = 0
    private let model = WindowSwitcherModel()
    private var registeredPreset = ""
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var configuredModifiers: NSEvent.ModifierFlags = []
    private var configuredKeyCode: UInt16 = 0
    private var lastInvocationTime: TimeInterval = -.infinity
    private var lastInvocationSource = ""
    private var lastInvocationBackwards = false

    private override init() {
        super.init()
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4D505357 else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<WindowSwitcherHotkeyController>.fromOpaque(context).takeUnretainedValue()
            let backwards = id.id == 2
            let timestamp = GetEventTime(event)
            Task { @MainActor in controller.receiveShortcut(backwards: backwards, source: "carbon", timestamp: timestamp) }
            return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.configure() } }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                // Carbon dispatch is global; direct-to-application input can arrive only
                // as NSEvent. Handle the same registered chord locally in that case.
                if event.type == .keyDown, self.matchesRegisteredShortcut(event) {
                    self.receiveShortcut(backwards: event.modifierFlags.contains(.shift), source: "local", timestamp: event.timestamp)
                    return true
                }
                guard let panel = self.panel, panel.isKeyWindow else { return false }
                if event.type == .flagsChanged {
                    let releaseToChoose = UserDefaults.standard.object(forKey: "switcher.releaseToChoose") as? Bool ?? true
                    if releaseToChoose && !self.heldModifiers.isEmpty && event.modifierFlags.intersection(self.heldModifiers).isEmpty {
                        self.activateSelection(); return true
                    }
                    return false
                }
                switch event.keyCode {
                case UInt16(kVK_Escape): self.dismiss(); return true
                case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter): self.activateSelection(); return true
                case UInt16(kVK_DownArrow), UInt16(kVK_RightArrow): self.model.cycle(backwards: false); return true
                case UInt16(kVK_UpArrow), UInt16(kVK_LeftArrow): self.model.cycle(backwards: true); return true
                case UInt16(kVK_Tab): self.model.cycle(backwards: event.modifierFlags.contains(.shift)); return true
                default: return false
                }
            }
            return consumed ? nil : event
        }
        configure()
    }

    private func configure() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "switcher.globalEnabled")
        let preset = defaults.string(forKey: "switcher.shortcut") ?? "controlOptionSpace"
        let key = enabled ? preset : "disabled"
        guard key != registeredPreset else { return }
        registeredPreset = key
        for ref in keyRefs { UnregisterEventHotKey(ref) }; keyRefs = []
        guard enabled else { registrationMessage = "Global kısayol kapalı."; return }
        let code: UInt32, modifiers: UInt32
        switch preset {
        case "optionTab": code = UInt32(kVK_Tab); modifiers = UInt32(optionKey); configuredModifiers = .option
        case "controlTab": code = UInt32(kVK_Tab); modifiers = UInt32(controlKey); configuredModifiers = .control
        default: code = UInt32(kVK_Space); modifiers = UInt32(controlKey | optionKey); configuredModifiers = [.control, .option]
        }
        configuredKeyCode = UInt16(code)
        guard handler != nil else { registrationMessage = "macOS kısayol dinleyicisini başlatamadı."; return }
        for (id, extra) in [(UInt32(1), UInt32(0)), (UInt32(2), UInt32(shiftKey))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, modifiers | extra, EventHotKeyID(signature: 0x4D505357, id: id), GetEventDispatcherTarget(), 0, &ref)
            guard status == noErr, let ref else {
                for existing in keyRefs { UnregisterEventHotKey(existing) }; keyRefs = []
                registrationMessage = "Kısayol kaydedilemedi (\(status)). AltTab veya başka bir uygulama bu kısayolu kullanıyor olabilir."
                return
            }
            keyRefs.append(ref)
        }
        registrationMessage = "macOS kısayol kaydı etkin. Shift ile ters yönde gezin. Escape ile vazgeç."
    }

    private func matchesRegisteredShortcut(_ event: NSEvent) -> Bool {
        guard keyRefs.count == 2, UserDefaults.standard.bool(forKey: "switcher.globalEnabled"),
              event.keyCode == configuredKeyCode else { return false }
        let pressed = event.modifierFlags.intersection([.control, .option, .command, .shift]).subtracting(.shift)
        return pressed == configuredModifiers
    }

    private func receiveShortcut(backwards: Bool, source: String, timestamp: TimeInterval) {
        // Counts only accepted switcher chords, never general key activity/content.
        let defaults = UserDefaults.standard
        guard keyRefs.count == 2, defaults.bool(forKey: "switcher.globalEnabled") else { return }
        let key = "switcher.diagnostics." + source + "Events"
        defaults.set(min(Int.max - 1, defaults.integer(forKey: key)) + 1, forKey: key)
        // Some delivery paths provide both Carbon and NSEvent for one physical press.
        if source != lastInvocationSource && backwards == lastInvocationBackwards && abs(timestamp - lastInvocationTime) < 0.05 { return }
        lastInvocationTime = timestamp; lastInvocationSource = source; lastInvocationBackwards = backwards
        summon(backwards: backwards)
    }

    func show() { summon(backwards: false, fromShortcut: false) }
    private func summon(backwards: Bool, fromShortcut: Bool = true) {
        if summoning { pendingSteps += backwards ? -1 : 1; return }
        if panel?.isVisible == true { if panel?.attachedSheet == nil { model.cycle(backwards: backwards) }; return }
        heldModifiers = fromShortcut ? configuredModifiers : []
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "MacPocket · Pencere Geçişi"; panel.level = .floating; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 780, height: 580)
            panel.contentViewController = NSHostingController(rootView: WindowSwitcherView(model: model, overlay: true, onActivated: { [weak self] in self?.dismiss() }))
            self.panel = panel
        }
        // Capture the foreground app before activating our panel; useful for current-app filtering.
        model.foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        summoning = true; pendingSteps = 0
        Task { [weak self] in
            guard let self else { return }
            defer { summoning = false }
            await model.refresh()
            let rows = model.filtered
            if !rows.isEmpty {
                // Advance from the actual foreground row; MacPocket itself is excluded.
                // When no foreground row is in the filtered list, start at the first/last.
                if fromShortcut, let front = rows.firstIndex(where: { $0.frontmost }) {
                    model.selection = rows[(front + (backwards ? -1 : 1) + rows.count) % rows.count].id
                } else { model.selection = (backwards ? rows.last : rows.first)?.id }
                if let index = rows.firstIndex(where: { $0.id == model.selection }) {
                    model.selection = rows[(index + pendingSteps % rows.count + rows.count) % rows.count].id
                }
            }
            panel?.center(); panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            if !heldModifiers.isEmpty && NSEvent.modifierFlags.intersection(heldModifiers).isEmpty
                && (UserDefaults.standard.object(forKey: "switcher.releaseToChoose") as? Bool ?? true) { activateSelection() }
        }
    }
    private func activateSelection() {
        // Close first so activation does not race our floating panel becoming key again.
        dismiss()
        Task { await model.focus() }
    }
    private func dismiss() { panel?.orderOut(nil) }
}

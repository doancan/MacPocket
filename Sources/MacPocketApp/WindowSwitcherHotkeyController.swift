import AppKit
@preconcurrency import Carbon
import Combine
import MacPocketCore
import SwiftUI

/// Opt-in, reversible Carbon hotkey registrations; no passive key logging. Up to nine shortcuts, each with
/// its own filters. While the panel is key, a local monitor handles navigation, search and window actions.
@MainActor
final class WindowSwitcherHotkeyController: NSObject, ObservableObject {
    static let shared = WindowSwitcherHotkeyController()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("WindowSwitcherHotkeyController")
    #endif

    @Published private(set) var registrationMessage = String(localized: "Global kısayol kapalı.")
    @Published private(set) var shortcuts: [SwitcherShortcut] = []
    @Published private(set) var layout = SwitcherLayout.compute(count: 1, style: .thumbnails, available: CGSize(width: 1440, height: 900), autoSize: true)
    @Published private(set) var activeShortcut: SwitcherShortcut?
    @Published private(set) var suspendedForApplication: String?

    let model = WindowSwitcherModel()
    private var keyRefs: [EventHotKeyRef] = []
    /// Carbon hotkey id → (shortcut index, reverse).
    private var hotkeyMap: [UInt32: (index: Int, backwards: Bool)] = [:]
    private var handler: EventHandlerRef?
    private var registeredSignature = ""
    private var recordingShortcut = false
    private var subscriptions = Set<AnyCancellable>()
    private var monitor: Any?

    private var previousApplication: NSRunningApplication?
    private var panel: NSPanel?
    private var previewPanel: SwitcherPreviewPanel?
    private var sessionID: UUID?
    private var preparing = false
    private var commitWhenReady = false
    private var pendingSteps = 0
    private var sessionBackwards = false
    /// Foreground PID captured before the panel takes focus; nil when opened from settings.
    private var sessionForegroundPID: Int32?
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var sessionScreen: NSScreen?
    private var openedAtMouse = NSPoint.zero
    private var openingTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var lastInvocationTime: TimeInterval = -.infinity
    private var lastInvocationSource = ""
    private var lastInvocationBackwards = false
    private var lastPrewarm = Date.distantPast
    private var gestureFingers = -1

    private static let signature: OSType = 0x4D505357 // 'MPSW'

    private override init() {
        super.init()
    }

    private(set) var moduleRunning = false

    func start() {
        guard !moduleRunning, PocketModule.windowSwitcher.isAvailable() else { return }
        moduleRunning = true
        model.startObserving()
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "switcher.cardOverlayConfigured") {
            defaults.set(true, forKey: "switcher.globalEnabled")
            defaults.set(true, forKey: "switcher.cardOverlayConfigured")
        }
        shortcuts = SwitcherShortcutStore.load(defaults)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.dismiss() } }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                Task { @MainActor [weak self] in self?.applicationActivated(bundleID) }
            }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.configure() } }
            .store(in: &subscriptions)
        // Card count changes (search, refresh) resize the panel around its center.
        model.$windows.combineLatest(model.$sessionSearch)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in MainActor.assumeIsolated { self?.listChanged() } }
            .store(in: &subscriptions)
        model.$selection
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.selectionChanged() } }
            .store(in: &subscriptions)

        installCarbonHandler()
        installLocalMonitor()
        configure()
        Task { [weak self] in await self?.model.refresh() }
    }

    func stopForModule() {
        moduleRunning = false
        dismiss()
        subscriptions = []
        for ref in keyRefs { UnregisterEventHotKey(ref) }
        keyRefs = []
        hotkeyMap = [:]
        registeredSignature = ""
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if gestureFingers > 0 { TrackpadSwipeMonitor.shared.stop() }
        gestureFingers = -1
        model.stopObserving()
    }

    // MARK: Settings

    var style: SwitcherStyle { SwitcherStyle(rawValue: UserDefaults.standard.string(forKey: "switcher.style") ?? "") ?? .thumbnails }
    private var autoSize: Bool { UserDefaults.standard.object(forKey: "switcher.autoSize") as? Bool ?? true }
    private var sizeScale: Double { UserDefaults.standard.object(forKey: "switcher.size") as? Double ?? 1 }
    private var previewSelectedEnabled: Bool { UserDefaults.standard.object(forKey: "switcher.previewSelected") as? Bool ?? true }
    private var liveThumbnails: Bool { UserDefaults.standard.object(forKey: "switcher.liveThumbnails") as? Bool ?? true }
    var hoverSelects: Bool { UserDefaults.standard.object(forKey: "switcher.hoverSelects") as? Bool ?? true }
    private var disabledBundleIDs: Set<String> {
        Set((UserDefaults.standard.string(forKey: "switcher.disabledApps") ?? "").split(separator: "\n").map(String.init))
    }

    func saveShortcuts(_ list: [SwitcherShortcut]) {
        SwitcherShortcutStore.save(list)
        shortcuts = SwitcherShortcutStore.load()
        configure()
    }

    /// The recorder needs raw key events, so registered hotkeys are released while it listens.
    func setRecording(_ recording: Bool) {
        recordingShortcut = recording
        configure()
    }

    var sessionHint: String {
        // Narrow panels (few windows, search) get a short form so the hint is never truncated.
        if layout.panelSize.width < 900 {
            let symbols = activeShortcut?.modifiers.symbols ?? ""
            let choose = activeShortcut.map { !heldModifiers.isEmpty && $0.releaseToChoose && model.sessionSearch.isEmpty } == true
                ? String(localized: "\(symbols) bırak") : String(localized: "↩ seç")
            return String(localized: "⇥ gezin · \(choose) · yaz: ara · esc")
        }
        var parts = [String(localized: "⇥ ilerle"), String(localized: "⇧⇥ geri")]
        if let shortcut = activeShortcut, !heldModifiers.isEmpty, shortcut.releaseToChoose, model.sessionSearch.isEmpty {
            let symbols = shortcut.modifiers.symbols
            parts.append(String(localized: "\(symbols) bırak: seç"))
        } else {
            parts.append(String(localized: "↩ seç"))
        }
        parts += [String(localized: "yaz: ara"), String(localized: "⌘W kapat"), String(localized: "⌘M küçült"),
                  String(localized: "⌘Q çık"), "esc"]
        return parts.joined(separator: " · ")
    }

    // MARK: Registration

    private func installCarbonHandler() {
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == WindowSwitcherHotkeyController.signature else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<WindowSwitcherHotkeyController>.fromOpaque(context).takeUnretainedValue()
            let hotkey = id.id
            let timestamp = GetEventTime(event)
            Task { @MainActor in controller.receiveHotkey(hotkey, source: "carbon", timestamp: timestamp) }
            return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func configure() {
        guard moduleRunning else { return }
        let defaults = UserDefaults.standard
        let fingers = defaults.integer(forKey: "switcher.gestureFingers")
        if fingers != gestureFingers {
            gestureFingers = fingers
            TrackpadSwipeMonitor.shared.configure(fingers: fingers)
        }
        let stored = SwitcherShortcutStore.load(defaults)
        if stored != shortcuts { shortcuts = stored }
        let enabled = defaults.bool(forKey: "switcher.globalEnabled")
        let active = enabled && !recordingShortcut && suspendedForApplication == nil
        let signature = active ? (try? JSONEncoder().encode(shortcuts)).map { String(decoding: $0, as: UTF8.self) } ?? "" : "off"
        guard signature != registeredSignature else { return }
        registeredSignature = signature
        for ref in keyRefs { UnregisterEventHotKey(ref) }
        keyRefs = []; hotkeyMap = [:]
        guard enabled else { registrationMessage = String(localized: "Global kısayol kapalı."); return }
        if recordingShortcut { registrationMessage = String(localized: "Kısayol kaydediliyor…"); return }
        if let app = suspendedForApplication { registrationMessage = String(localized: "\(app) öndeyken kısayollar devre dışı."); return }
        guard handler != nil else { registrationMessage = String(localized: "macOS kısayol dinleyicisini başlatamadı."); return }
        let problems = SwitcherShortcutValidation.problems(shortcuts)
        var failures: [String] = []
        for (index, shortcut) in shortcuts.enumerated() where index < SwitcherShortcut.maximumCount {
            for backwards in [false, true] {
                let id = UInt32(index * 2 + (backwards ? 2 : 1))
                var ref: EventHotKeyRef?
                let flags = shortcut.modifiers.carbonFlags | (backwards ? SwitcherModifiers.carbonShift : 0)
                let status = RegisterEventHotKey(UInt32(shortcut.keyCode), flags, EventHotKeyID(signature: Self.signature, id: id),
                                                 GetEventDispatcherTarget(), 0, &ref)
                if status == noErr, let ref {
                    keyRefs.append(ref); hotkeyMap[id] = (index, backwards)
                } else if !backwards {
                    failures.append("\(shortcut.displayName) (\(status))")
                }
            }
        }
        if !failures.isEmpty {
            let list = failures.joined(separator: ", ")
            registrationMessage = String(localized: "Kaydedilemedi: \(list). Başka bir uygulama (ör. AltTab) aynı kısayolu kullanıyor olabilir.")
        } else if !problems.isEmpty {
            registrationMessage = problems.joined(separator: " ")
        } else {
            let list = shortcuts.map(\.displayName).joined(separator: ", ")
            registrationMessage = String(localized: "\(list) etkin. Shift ile ters yönde gezin.")
        }
    }

    private func applicationActivated(_ bundleID: String?) {
        let disabled = bundleID.map { disabledBundleIDs.contains($0) } ?? false
        let name = disabled ? NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleID : nil
        if name != suspendedForApplication {
            suspendedForApplication = name
            configure()
        }
        // Keep the catalog warm so the switcher opens with current windows instantly. MacPocket itself
        // becoming active needs no rescan (nobody is switching), and the scan walks every app via AX.
        let isSelf = bundleID == Bundle.main.bundleIdentifier
        if sessionID == nil, !isSelf, !keyRefs.isEmpty, Date().timeIntervalSince(lastPrewarm) > 5 {
            lastPrewarm = Date()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                await self?.model.refresh()
            }
        }
    }

    // MARK: Input

    private func installLocalMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                if self.recordingShortcut { return false }
                // Carbon dispatch is global; input aimed at this app can arrive only as NSEvent.
                if event.type == .keyDown, let index = self.registeredShortcutIndex(for: event) {
                    self.receiveShortcut(index: index, backwards: event.modifierFlags.contains(.shift), source: "local", timestamp: event.timestamp)
                    return true
                }
                guard let panel = self.panel, panel.isKeyWindow, self.sessionID != nil else { return false }
                return event.type == .flagsChanged ? self.handleFlags(event) : self.handleKey(event)
            }
            return consumed ? nil : event
        }
    }

    private func registeredShortcutIndex(for event: NSEvent) -> Int? {
        guard !keyRefs.isEmpty else { return nil }
        let flags = event.modifierFlags
        let pressed: SwitcherModifiers = [flags.contains(.control) ? .control : [], flags.contains(.option) ? .option : [],
                                          flags.contains(.command) ? .command : []]
        return shortcuts.firstIndex { $0.keyCode == event.keyCode && $0.modifiers == pressed }
    }

    private func handleFlags(_ event: NSEvent) -> Bool {
        guard let shortcut = activeShortcut, shortcut.releaseToChoose, !heldModifiers.isEmpty,
              event.modifierFlags.intersection(heldModifiers).isEmpty, model.sessionSearch.isEmpty else { return false }
        requestCommit()
        return true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        switch Int(event.keyCode) {
        case kVK_Escape:
            if !model.sessionSearch.isEmpty { model.sessionSearch = "" } else { dismiss(restorePrevious: true) }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter: requestCommit(); return true
        case kVK_Tab: step(backwards: flags.contains(.shift)); return true
        case kVK_RightArrow: step(backwards: false); return true
        case kVK_LeftArrow: step(backwards: true); return true
        case kVK_DownArrow: step(backwards: false, by: layout.columns); return true
        case kVK_UpArrow: step(backwards: true, by: layout.columns); return true
        case kVK_Delete:
            if !model.sessionSearch.isEmpty { model.sessionSearch.removeLast() }
            return true
        default: break
        }
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        // ⌘-letter acts on the selected window unless ⌘ is the shortcut's own held modifier.
        if flags.contains(.command), !heldModifiers.contains(.command) {
            let action: WindowAction?
            switch characters {
            case "w": action = .close
            case "m": action = model.selected?.minimized == true ? .restore : .minimize
            case "f": action = .toggleFullScreen
            case "h": action = .hideApplication
            case "q": action = .quitApplication
            default: action = nil
            }
            if let action { perform(action) }
            return true
        }
        guard let character = event.charactersIgnoringModifiers, !character.isEmpty,
              character.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).union(.whitespaces).contains($0) })
        else { return false }
        model.sessionSearch += character
        return true
    }

    private func receiveHotkey(_ id: UInt32, source: String, timestamp: TimeInterval) {
        guard let entry = hotkeyMap[id] else { return }
        receiveShortcut(index: entry.index, backwards: entry.backwards, source: source, timestamp: timestamp)
    }

    private func receiveShortcut(index: Int, backwards: Bool, source: String, timestamp: TimeInterval) {
        guard !keyRefs.isEmpty, shortcuts.indices.contains(index) else { return }
        // Some delivery paths provide both Carbon and NSEvent for one physical press.
        if source != lastInvocationSource && backwards == lastInvocationBackwards && abs(timestamp - lastInvocationTime) < 0.05 { return }
        lastInvocationTime = timestamp; lastInvocationSource = source; lastInvocationBackwards = backwards
        summon(shortcut: shortcuts[index], backwards: backwards, holdsModifiers: true)
    }

    // MARK: Session

    /// Opens the switcher from the settings preview button.
    func show() {
        summon(shortcut: shortcuts.first ?? .defaultOptionTab, backwards: false, holdsModifiers: false)
    }

    /// Trackpad swipe: opens on the first step, moves on later steps, and selects when fingers lift.
    func gestureStep(backwards: Bool) {
        if sessionID == nil {
            var shortcut = shortcuts.first ?? .defaultOptionTab
            shortcut.releaseToChoose = false
            summon(shortcut: shortcut, backwards: backwards, holdsModifiers: false)
        } else { step(backwards: backwards) }
    }

    func gestureEnded() { requestCommit() }

    private func step(backwards: Bool, by count: Int = 1) {
        if preparing {
            pendingSteps += backwards ? -count : count
            model.selection = WindowSwitchSelection.initial(model.filtered, foregroundPID: sessionForegroundPID,
                                                            backwards: sessionBackwards, queuedSteps: pendingSteps)
        } else { model.cycle(backwards: backwards, by: count) }
    }

    private func summon(shortcut: SwitcherShortcut, backwards: Bool, holdsModifiers: Bool) {
        guard moduleRunning else { return }
        if sessionID != nil { step(backwards: backwards); return }
        let id = UUID()
        sessionID = id; preparing = true; commitWhenReady = false
        activeShortcut = shortcut
        heldModifiers = holdsModifiers ? Self.eventFlags(shortcut.modifiers) : []
        previousApplication = NSWorkspace.shared.frontmostApplication
        let foregroundPID = previousApplication?.processIdentifier
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        sessionScreen = screen
        openedAtMouse = NSEvent.mouseLocation
        model.foregroundPID = foregroundPID
        model.sessionSearch = ""
        model.failure = nil
        model.sessionFilter = shortcut.filter
        model.sessionDisplayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        model.clearThumbnails()
        // The cached list (kept warm in the background) appears immediately; a fresh snapshot follows.
        pendingSteps = 0
        sessionBackwards = backwards
        sessionForegroundPID = holdsModifiers ? foregroundPID : nil
        model.selection = WindowSwitchSelection.initial(model.filtered, foregroundPID: sessionForegroundPID,
                                                        backwards: backwards, queuedSteps: 0)
        presentPanel(sessionID: id)
        openingTask = Task { [weak self] in
            guard let self else { return }
            await model.refresh()
            guard !Task.isCancelled, sessionID == id else { return }
            model.selection = WindowSwitchSelection.initial(model.filtered, foregroundPID: sessionForegroundPID,
                                                            backwards: sessionBackwards, queuedSteps: pendingSteps)
            preparing = false
            let released = !heldModifiers.isEmpty && NSEvent.modifierFlags.intersection(heldModifiers).isEmpty
            if commitWhenReady || (released && shortcut.releaseToChoose) { activateSelection(); return }
            startThumbnails()
        }
    }

    private func presentPanel(sessionID id: UUID) {
        if panel == nil {
            let panel = SwitcherCardPanel(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = String(localized: "MacPocket · Pencere Geçişi")
            panel.setAccessibilityLabel(String(localized: "MacPocket pencere geçişi"))
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.level = .popUpMenu; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
            panel.animationBehavior = .utilityWindow
            self.panel = panel
        }
        relayout(force: true)
        panel?.contentView = NSHostingView(rootView: WindowSwitcherOverlayView(model: model, controller: self, choose: { [weak self] target in
            self?.model.selection = target; self?.requestCommit()
        }).id(id))
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Search or refresh can filter out the selected window; keep a valid selection so ↩ always has a target.
    private func listChanged() {
        relayout()
        guard sessionID != nil else { return }
        let visible = model.filtered
        if !visible.contains(where: { $0.id == model.selection }) { model.selection = visible.first?.id }
    }

    private func relayout(force: Bool = false) {
        guard force || sessionID != nil else { return }
        let area = (sessionScreen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let next = SwitcherLayout.compute(count: max(1, model.filtered.count), style: style, available: area.size,
                                          autoSize: autoSize, scale: sizeScale)
        if next != layout { layout = next }
        guard let panel else { return }
        let size = next.panelSize
        let frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true, animate: panel.isVisible && !PocketReduceMotion.isEnabled) }
    }

    private func startThumbnails() {
        thumbnailTask?.cancel()
        guard style != .titles else { return }
        let scale = sessionScreen?.backingScaleFactor ?? 2
        let size = CGSize(width: layout.itemSize.width * scale, height: layout.itemSize.height * scale)
        let live = liveThumbnails
        thumbnailTask = Task { [weak self] in await self?.model.runThumbnails(maxPixels: size, live: live) }
    }

    private func selectionChanged() {
        guard sessionID != nil else { return }
        if let window = model.selected, NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: "\(window.application), \(window.title)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        updatePreview()
    }

    /// Shows the selected window at its real position and size behind the switcher.
    private func updatePreview() {
        previewTask?.cancel()
        guard sessionID != nil, previewSelectedEnabled, let window = model.selected, let frame = window.frame, !window.minimized else {
            previewPanel?.orderOut(nil); return
        }
        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(Self.cocoaRect(frame)) } ?? NSScreen.main)
        let scale = screenFrame?.backingScaleFactor ?? 2
        previewTask = Task { [weak self] in
            guard let self else { return }
            await model.loadSelectedPreview(maxPixels: CGSize(width: frame.width * scale, height: frame.height * scale))
            guard !Task.isCancelled, sessionID != nil, let preview = model.selectedPreview, preview.id == window.id else {
                if !Task.isCancelled { previewPanel?.orderOut(nil) }
                return
            }
            if previewPanel == nil { previewPanel = SwitcherPreviewPanel() }
            previewPanel?.show(preview.image, at: Self.cocoaRect(frame))
        }
    }

    private func requestCommit() {
        guard sessionID != nil else { return }
        if preparing { commitWhenReady = true } else { activateSelection() }
    }

    private func activateSelection() {
        guard let target = model.selected?.id else { dismiss(); return }
        dismiss()
        Task { [weak self] in
            guard let self else { return }
            await model.focus(id: target)
            if let failure = model.failure { registrationMessage = failure }
        }
    }

    private func perform(_ action: WindowAction) {
        guard let target = model.selected else { return }
        Task { [weak self] in
            guard let self else { return }
            await model.action(action, id: target.id)
            // Keep the panel key: hiding or quitting an app may move focus elsewhere.
            if sessionID != nil { panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
            if !model.filtered.contains(where: { $0.id == model.selection }) { model.selection = model.filtered.first?.id }
        }
    }

    /// Mouse hover selects only after the pointer actually moves, so a resting cursor under the panel
    /// does not override the keyboard's initial selection.
    func hover(_ id: String) {
        guard hoverSelects, sessionID != nil else { return }
        let location = NSEvent.mouseLocation
        guard hypot(location.x - openedAtMouse.x, location.y - openedAtMouse.y) > 3 else { return }
        model.selection = id
    }

    func act(_ action: WindowAction, on id: String) {
        model.selection = id
        perform(action)
    }

    private func dismiss(restorePrevious: Bool = false) {
        let previous = restorePrevious ? previousApplication : nil
        sessionID = nil; preparing = false; commitWhenReady = false
        openingTask?.cancel(); openingTask = nil
        thumbnailTask?.cancel(); thumbnailTask = nil
        previewTask?.cancel(); previewTask = nil
        activeShortcut = nil
        model.sessionFilter = nil
        model.sessionSearch = ""
        model.clearThumbnails()
        previewPanel?.orderOut(nil)
        panel?.orderOut(nil)
        if let previous, !previous.isTerminated, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier { previous.activate(options: []) }
    }

    private static func eventFlags(_ modifiers: SwitcherModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    /// CoreGraphics (top-left origin) → AppKit (bottom-left origin) global coordinates.
    static func cocoaRect(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
private final class SwitcherCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Click-through, borderless window that draws the selected window's image over its real frame.
@MainActor
final class SwitcherPreviewPanel: NSPanel {
    private let imageView = NSImageView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        imageView.alphaValue = 0.94
        contentView = imageView
        setAccessibilityElement(false)
    }

    func show(_ image: NSImage, at frame: NSRect) {
        imageView.image = image
        setFrame(frame, display: true)
        orderFront(nil)
    }
}

#if DEBUG
extension WindowSwitcherHotkeyController {
    var moduleDiagnosticResources: [String: Int] { ["hotKeys": keyRefs.count, "handler": handler == nil ? 0 : 1, "monitor": monitor == nil ? 0 : 1, "subscriptions": subscriptions.count] }
}
#endif

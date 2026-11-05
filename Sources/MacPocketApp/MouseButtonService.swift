import AppKit
import ApplicationServices
import Carbon
import MacPocketCore

/// A weak resolver lets scrolling yield a mapped side wheel without instantiating a disabled module.
@MainActor enum MouseInputClaims {
    private static var owner: ObjectIdentifier?
    private static var resolver: ((CGEvent) -> Bool)?
    static func install(owner: AnyObject, resolver: @escaping (CGEvent) -> Bool) {
        self.owner = ObjectIdentifier(owner); self.resolver = resolver
    }
    static func remove(owner: AnyObject) {
        if self.owner == ObjectIdentifier(owner) { self.owner = nil; resolver = nil }
    }
    static func claims(_ event: CGEvent) -> Bool { resolver?(event) == true }
}

@MainActor
final class MouseButtonService: ObservableObject {
    static let shared = MouseButtonService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("MouseButtonService")
    #endif
    @Published var settings: MouseButtonSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults); generation &+= 1; configureTap(resetFailure: true)
        }
    }
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var tapActive = false
    @Published private(set) var failure: String?
    @Published private(set) var capturing = false
    @Published private(set) var detected: MouseButtonInput?
    var recordingShortcut = false { didSet { generation &+= 1 } }
    private(set) var moduleRunning = false
    private let defaults: UserDefaults
    private let usesHardware: Bool
    private let dispatchAction: ((MouseButtonBinding) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var captureMonitor: Any?
    private var captureTimer: Timer?
    private var router = MouseButtonRouter()
    private var generation: UInt64 = 0
    private var sessionActive = true
    private var sleeping = false
    private var creationFailed = false
    nonisolated static let marker: Int64 = 0x4D50_4D42

    init(defaults: UserDefaults = .standard, usesHardware: Bool = true, dispatchAction: ((MouseButtonBinding) -> Void)? = nil) {
        self.defaults = defaults; self.usesHardware = usesHardware; self.dispatchAction = dispatchAction
        settings = MouseButtonSettings.load(from: defaults)
    }
    func start() {
        guard !moduleRunning else { return }
        moduleRunning = true; sessionActive = true; sleeping = false
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.contextChanged(name) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap(resetFailure: true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopCapture() }
        })
        configureTap(resetFailure: true)
    }
    func stopForModule() {
        moduleRunning = false; generation &+= 1; recordingShortcut = false
        stopCapture(); configureTap()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []; router.reset(); failure = nil
    }
    func refreshPermission() { configureTap(resetFailure: true) }

    private func contextChanged(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.sessionDidResignActiveNotification: sessionActive = false
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionActive = true
        case NSWorkspace.willSleepNotification: sleeping = true
        case NSWorkspace.didWakeNotification: sleeping = false
        default: return
        }
        if !sessionActive || sleeping { generation &+= 1; stopCapture() }
        configureTap(resetFailure: true)
    }

    private func configureTap(resetFailure: Bool = false) {
        let wasTrusted = trusted
        trusted = AXIsProcessTrusted()
        if resetFailure || trusted != wasTrusted { creationFailed = false; failure = nil }
        let enabled = moduleRunning && settings.enabled && sessionActive && !sleeping
        let wanted = enabled && trusted && !IsSecureEventInputEnabled() && usesHardware
        if wanted, tap == nil, !creationFailed {
            let callback: CGEventTapCallBack = { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<MouseButtonService>.fromOpaque(context).takeUnretainedValue()
                let keep = MainActor.assumeIsolated { owner.handle(type, event) }
                return keep ? Unmanaged.passUnretained(event) : nil
            }
            let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
            let mask = types.reduce(CGEventMask(0)) {
                $0 | CGEventMask(1 << $1.rawValue)
            }
            if let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
               let source = CFMachPortCreateRunLoopSource(nil, created, 0) {
                tap = created; self.source = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: created, enable: true)
                MouseInputClaims.install(owner: self) { [weak self] event in self?.claimedWheel(event) == true }
            } else {
                creationFailed = true
                failure = String(localized: "Fare olayları alınamadı. Erişilebilirlik iznini kontrol edip yeniden dene.")
            }
        } else if !wanted {
            let removed = tap != nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            tap = nil; source = nil
            if removed || !enabled || usesHardware { router.reset() }
            MouseInputClaims.remove(owner: self)
        }
        tapActive = tap != nil
        if enabled && permissionTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.configureTap() } }
            timer.tolerance = 0.3; RunLoop.main.add(timer, forMode: .common); permissionTimer = timer
        } else if !enabled { permissionTimer?.invalidate(); permissionTimer = nil }
    }

    static func wheelInput(_ event: CGEvent) -> MouseButtonInput? {
        let points = (event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let fixed = (event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
        let lines = (Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)), Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)))
        let delta = points.0 != 0 || points.1 != 0 ? points : (fixed.0 != 0 || fixed.1 != 0 ? fixed : lines)
        return .wheel(vertical: delta.0, horizontal: delta.1, continuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0)
    }
    private var acceptsInput: Bool {
        moduleRunning && settings.enabled && sessionActive && !sleeping && !recordingShortcut && !capturing && (dispatchAction != nil || (trusted && !IsSecureEventInputEnabled()))
    }
    private func resolved(_ input: MouseButtonInput) -> MouseButtonBinding? {
        guard acceptsInput else { return nil }
        let binding = settings.binding(for: input, application: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        guard binding.isExecutable, actionAvailable(binding.action) else { return nil }
        return binding
    }
    func actionAvailable(_ action: MouseButtonAction) -> Bool {
        switch action {
        case .commandBar: PocketModule.commandBar.isAvailable(in: defaults)
        case .clipboard: PocketModule.clipboard.isAvailable(in: defaults) && ClipboardSettings.load(from: defaults).enabled
        case .shelf: PocketModule.shelf.isAvailable(in: defaults)
        default: true
        }
    }
    private func claimedWheel(_ event: CGEvent) -> Bool {
        !isSynthetic(event) && Self.wheelInput(event).flatMap(resolved) != nil
    }
    private func isSynthetic(_ event: CGEvent) -> Bool {
        let value = event.getIntegerValueField(.eventSourceUserData)
        return value == Self.marker || value == MouseScrollService.marker
    }
    /// No AX queries, panel creation, key posting, or other potentially slow work runs inside the event tap.
    @discardableResult func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            router.reset(); generation &+= 1
            if acceptsInput, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard !isSynthetic(event) else { return true }
        let decision: MouseButtonRouter.Decision
        if type == .scrollWheel {
            guard let input = Self.wheelInput(event) else { return true }
            decision = router.wheel(input, at: Double(event.timestamp) / 1_000_000_000, proposed: resolved(input))
        } else {
            let phase: MouseButtonRouter.Phase
            switch type { case .otherMouseDown: phase = .down; case .otherMouseUp: phase = .up; case .otherMouseDragged: phase = .drag; default: return true }
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            decision = router.button(button, phase: phase, proposed: MouseButtonInput(rawValue: button).flatMap(resolved))
        }
        switch decision {
        case .pass: return true
        case .consume: return false
        case .perform(let binding):
            let app = NSWorkspace.shared.frontmostApplication
            let pid = app?.processIdentifier, launch = app?.launchDate
            let expectedGeneration = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, expectedGeneration == self.generation, self.acceptsInput, self.actionAvailable(binding.action),
                      let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == pid, front.launchDate == launch else { return }
                self.perform(binding)
            }
            return false
        }
    }
    private func perform(_ binding: MouseButtonBinding) {
        if let dispatchAction { dispatchAction(binding); return }
        if binding.keyCombo != nil {
            for event in Self.keyEvents(for: binding) { event.post(tap: .cgSessionEventTap) }
        } else {
            switch binding.action {
            case .commandBar: CommandBarService.shared.show()
            case .clipboard: ClipboardService.shared.togglePanel()
            case .shelf: ShelfService.shared.show()
            default: break
            }
        }
    }
    /// Built-in command characters must not turn into ğ/ü on a Turkish layout. Recorded shortcuts retain
    /// their physical key codes and current layout interpretation; only built-in menu commands override text.
    static func keyEvents(for binding: MouseButtonBinding) -> [CGEvent] {
        guard binding.isExecutable, let combo = binding.keyCombo else { return [] }
        let events = keyEvents(for: combo)
        let character: String?
        switch binding.action {
        case .back: character = "["
        case .forward: character = "]"
        case .copy: character = "c"
        case .paste: character = "v"
        default: character = nil
        }
        if let character {
            let units = Array(character.utf16)
            units.withUnsafeBufferPointer { pointer in
                for event in events where event.type == .keyDown {
                    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: pointer.baseAddress)
                }
            }
        }
        return events
    }
    static func keyEvents(for combo: KeyCombo) -> [CGEvent] {
        guard SwitcherKeys.isSupported(combo.keyCode), combo.modifiers.rawValue & ~15 == 0,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) else { return [] }
        var flags: CGEventFlags = []
        if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if combo.modifiers.contains(.control) { flags.insert(.maskControl) }
        if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
        for event in [down, up] { event.flags = flags; event.setIntegerValueField(.eventSourceUserData, value: Self.marker) }
        return [down, up]
    }

    func beginCapture() {
        stopCapture(); guard moduleRunning else { return }
        capturing = true; detected = nil; generation &+= 1
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            let consumed: Bool = MainActor.assumeIsolated {
                let input = event.type == .otherMouseDown ? MouseButtonInput(rawValue: event.buttonNumber) : event.cgEvent.flatMap(Self.wheelInput)
                guard let input else { return false }
                self.detected = input; self.stopCapture(); return true
            }
            return consumed ? nil : event
        }
        let timer = Timer(timeInterval: 10, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.stopCapture() } }
        RunLoop.main.add(timer, forMode: .common); captureTimer = timer
    }
    func stopCapture() {
        if let captureMonitor { NSEvent.removeMonitor(captureMonitor) }
        captureMonitor = nil; captureTimer?.invalidate(); captureTimer = nil; capturing = false
    }
    func clearDetected(_ input: MouseButtonInput) { if detected == input { detected = nil } }
    #if DEBUG
    func diagnosticContextChanged(_ name: Notification.Name) { contextChanged(name) }
    func diagnosticInstallClaims() {
        guard !usesHardware else { return }
        MouseInputClaims.install(owner: self) { [weak self] event in self?.claimedWheel(event) == true }
    }
    var moduleDiagnosticResources: [String: Int] {
        ["observers": observers.count, "tap": tap == nil ? 0 : 1, "source": source == nil ? 0 : 1,
         "timer": permissionTimer?.isValid == true ? 1 : 0, "capture": captureMonitor == nil ? 0 : 1,
         "captureTimer": captureTimer?.isValid == true ? 1 : 0, "pressed": router.pressed.count]
    }
    #endif
}

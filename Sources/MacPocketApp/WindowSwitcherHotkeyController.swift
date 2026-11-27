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
    @Published private(set) var activePresentation: SwitcherPresentation?
    @Published private(set) var activeNavigation: SwitcherNavigationOptions?
    private(set) var activeCursorPolicy: SwitcherCursorPolicy?
    @Published private(set) var actionBindings = SwitcherActionBinding.defaults
    @Published private(set) var shortcutEditingError: String?
    @Published private(set) var actionEditingError: String?
    @Published private(set) var suspendedForApplication: String?

    let model: WindowSwitcherModel
    private let foregroundApplication: @MainActor () -> NSRunningApplication?
    private let currentModifierFlags: @MainActor () -> NSEvent.ModifierFlags
    private var keyRefs: [EventHotKeyRef] = []
    /// Carbon hotkey id → (shortcut index, reverse).
    private var hotkeyMap: [UInt32: (index: Int, backwards: Bool)] = [:]
    private var handler: EventHandlerRef?
    private var registeredSignature = ""
    private var nativeKeyLease: (any SwitcherNativeKeyOwning)?
    private let registration: SwitcherHotkeyRegistration
    private let shortcutSettings: UserDefaults
    private var nativeKeyTimer: Timer?
    private var nativeFailureSignature: String?
    private var nativeFailureMessage: String?
    @Published private(set) var recordingShortcut = false
    private var subscriptions = Set<AnyCancellable>()
    private var monitor: Any?

    private var previousApplication: NSRunningApplication?
    private var panel: NSPanel?
    private var previewPanel: SwitcherPreviewPanel?
    private var sessionID: UUID?
    private var preparing = false
    private enum PreparationOrigin { case opening, retaining(String?) }
    private var preparationOrigin = PreparationOrigin.opening
    private var commitWhenReady = false
    private var pendingNavigation: [WindowNavigationIntent] = []
    private var sessionBackwards = false
    /// Foreground PID captured before the panel takes focus; nil when opened from settings.
    private var sessionForegroundPID: Int32?
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var sessionScreen: NSScreen?
    private var openedAtMouse = NSPoint.zero
    private var openingTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var badgeTask: Task<Void,Never>?
    private var previewTask: Task<Void, Never>?
    private var invocations = SwitcherInvocationDeduplicator()
    private var lastPrewarm = Date.distantPast
    private var environmentGeneration = UUID()
    private var preparedEnvironment: UUID?
    private var prewarmTask: Task<Void, Never>?
    private var prewarmID: UUID?
    private struct ConditionalExceptionContext: Equatable {
        let application: SwitcherForegroundApplication
        let rules: [SwitcherExceptionRule]
    }
    private var conditionalExceptionContext: ConditionalExceptionContext?
    private var conditionalExceptionTask: Task<Void, Never>?
    private var conditionalFullscreen: Bool?
    private let exceptionApplication: @MainActor () -> SwitcherForegroundApplication?
    private let fullscreenReader: @Sendable (SwitcherForegroundApplication) async -> Bool?
    private let gestureMonitor: any SwitcherGestureMonitoring
    private let gestureSettings: UserDefaults
    private let gestureFeedback: @MainActor () -> Void
    private var configuredGestureOptions: SwitcherGestureOptions?
    private var gestureOwner: (id: UUID,session: UUID,haptics: Bool)?
    private var blockedGestureID: UUID?
    private var gestureFeedbackSelection: String?
    private var showTask: Task<Void, Never>?
    /// Reused across sessions; each session replaces only the root view (new `.id`, fresh state).
    private var hostingView: NSHostingView<WindowSwitcherPanelRoot>?
    private var focusTask: Task<Void, Never>?
    private var focusID: UUID?
    private var thumbnailsWanted = false
    private var modifierTimer: Timer?
    private var outsideClickMonitor: Any?
#if DEBUG
    private var syntheticAuditInput = false
    var onCarbonInvocationForAudit: ((UInt32,UUID?) -> Void)?
    var onModifierReleaseCommitForAudit: ((UUID) -> Void)?
    private var auditNativeKeysLost = false
    private var auditReduceTransparency: Bool?
#endif
    private var transparencyOverride: Bool? {
#if DEBUG
        return auditReduceTransparency
#else
        return nil
#endif
    }
    private var watchesExternalClicks: Bool {
#if DEBUG
        if syntheticAuditInput { return false }
#endif
        return true
    }
    /// A quick tap switches without ever drawing the panel, like the system switcher.

    private static let signature: OSType = 0x4D505357 // 'MPSW'

    init(model: WindowSwitcherModel = WindowSwitcherModel(),
         foregroundApplication: @escaping @MainActor () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
         modifierFlags: @escaping @MainActor () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
         exceptionApplication: (@MainActor () -> SwitcherForegroundApplication?)? = nil,
         gestureMonitor: any SwitcherGestureMonitoring = TrackpadSwipeMonitor.shared,
         gestureSettings: UserDefaults = .standard,
         gestureFeedback: @escaping @MainActor () -> Void = { NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime: .now) },
         registration: SwitcherHotkeyRegistration = .system,
         shortcutSettings: UserDefaults = .standard,
         fullscreenReader: @escaping @Sendable (SwitcherForegroundApplication) async -> Bool? = { await SwitcherForegroundWindowReader.shared.isFullscreen($0) }) {
        self.model = model
        self.registration = registration
        self.shortcutSettings = shortcutSettings
        self.gestureMonitor = gestureMonitor
        self.gestureSettings = gestureSettings
        self.gestureFeedback = gestureFeedback
        self.foregroundApplication = foregroundApplication
        self.currentModifierFlags = modifierFlags
        self.fullscreenReader = fullscreenReader
        self.exceptionApplication = exceptionApplication ?? {
            guard let app = foregroundApplication(), !app.isTerminated else { return nil }
            return SwitcherForegroundApplication(app)
        }
        super.init()
    }

    private(set) var moduleRunning = false

    func start() {
        guard !moduleRunning, PocketModule.windowSwitcher.isAvailable() else { return }
        moduleRunning = true
        model.startObserving()
        let defaults = shortcutSettings
        if !defaults.bool(forKey: "switcher.cardOverlayConfigured") {
            defaults.set(true, forKey: "switcher.globalEnabled")
            defaults.set(true, forKey: "switcher.cardOverlayConfigured")
        }
        shortcuts = SwitcherShortcutStore.load(defaults)
        if defaults.data(forKey: SwitcherShortcutStore.key) == nil { SwitcherShortcutStore.save(shortcuts, defaults) }

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.dismiss() } }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                Task { @MainActor [weak self] in self?.applicationActivated(bundleID) }
            }
            .store(in: &subscriptions)
        observeEnvironmentChanges()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.configure() } }
            .store(in: &subscriptions)
        observeModelChanges()

        installCarbonHandler()
        installLocalMonitor()
        configure()
        schedulePrewarm()
    }

    private func observeModelChanges() {
        // Card count changes (search, refresh) resize the panel around its center.
        observeModel({ [model] in (model.windows, model.sessionSearch) }) { controller, _, _ in controller.listChanged() }
        observeModel({ [model] in model.exceptionRules }) { controller, previous, _ in
            if previous != nil { controller.listChanged() }
        }
        observeModel({ [model] in model.selection }) { controller, previous, current in
            if previous.map({ $0 != current }) ?? true { controller.selectionChanged() }
        }
    }

    /// Runs `apply` on the main actor after each change of `value`, starting with its current value.
    /// `previous` is nil for that first delivery. The task ends with `subscriptions`.
    private func observeModel<Value: Sendable>(_ value: @escaping @MainActor @Sendable () -> Value,
                                               apply: @escaping @MainActor (WindowSwitcherHotkeyController, Value?, Value) -> Void) {
        let task = Task { @MainActor [weak self] in
            var previous: Value?
            for await current in Observations(value) {
                guard let self else { return }
                apply(self, previous, current)
                previous = current
            }
        }
        subscriptions.insert(AnyCancellable { task.cancel() })
    }

    private func observeEnvironmentChanges() {
        NotificationCenter.default.publisher(for: WindowLifecycleObservation.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.environmentChanged(screensChanged: false) } }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.environmentChanged(screensChanged: false) } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.environmentChanged(screensChanged: true) } }
            .store(in: &subscriptions)
    }

    /// Refresh only an open session; a closed switcher does no new AX scan for these events.
    /// Preparation begins immediately, so releasing Option during the debounce cannot choose
    /// from the old Space. A burst of environment notifications owes one fresh scan.
    func environmentChanged(screensChanged: Bool) {
        guard moduleRunning else { return }
        configure()
        environmentGeneration = UUID()
        lastPrewarm = .distantPast
        cancelPrewarm()
        model.invalidateSnapshot()
        guard let id = sessionID else { return }
        if !preparing { preparationOrigin = .retaining(model.selection); pendingNavigation = [] }
        preparing = true
        openingTask?.cancel()
        if screensChanged {
            let currentID = model.sessionDisplayID
            sessionScreen = NSScreen.screens.first { Self.displayID($0) == currentID } ?? screenForSession()
            model.sessionDisplayID = sessionScreen.flatMap(Self.displayID)
            openedAtMouse = NSEvent.mouseLocation
            relayout(force: true)
        }
        // Do not leave a full-size image at coordinates belonging to a removed display/old Space.
        previewTask?.cancel()
        previewTask = nil
        previewPanel?.orderOut(nil)
        openingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, sessionID == id else { return }
            await model.refresh()
            guard !Task.isCancelled, sessionID == id else { return }
            completePreparation(sessionID: id)
        }
    }

    private static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func preparationSelection() -> String? {
        let base: String?
        switch preparationOrigin {
        case .opening:
            base = WindowSwitchSelection.initial(model.filtered, foregroundPID: sessionForegroundPID, backwards: sessionBackwards)
        case .retaining(let id): base = WindowSwitchSelection.refreshed(model.filtered, preserving: id)
        }
        return WindowSwitchSelection.applying(pendingNavigation,to: model.filtered,preserving: base,columns: layout.columns)
    }

    private func completePreparation(sessionID id: UUID) {
        relayout()
        model.selection = preparationSelection()
        preparing = false
        provideGestureFeedback()
        preparedEnvironment = environmentGeneration
        if commitWhenReady { activateSelection(); return }
        handleModifierState(currentModifierFlags())
        guard sessionID == id else { return }
        if panel?.isVisible == true { startThumbnails() } else { thumbnailsWanted = true }
        updatePreview()
    }

    func stopForModule() {
        cancelFocus()
        moduleRunning = false
        cancelConditionalExceptions()
        suspendedForApplication = nil
        cancelPrewarm()
        environmentGeneration = UUID()
        preparedEnvironment = nil
        recordingShortcut = false
        dismiss(animated: false)
#if DEBUG
        syntheticAuditInput = false
        auditNativeKeysLost = false
        auditReduceTransparency = nil
#endif
        subscriptions = []
        nativeKeyTimer?.invalidate()
        nativeKeyTimer = nil
        if nativeKeyLease?.stop() == true { nativeKeyLease = nil }
        nativeFailureSignature = nil
        nativeFailureMessage = nil
        for ref in keyRefs { registration.unregister(ref) }
        keyRefs = []
        hotkeyMap = [:]
        registeredSignature = ""
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if configuredGestureOptions != nil { gestureMonitor.stop() }
        configuredGestureOptions = nil
        blockedGestureID = nil
        gestureFeedbackSelection = nil
        model.stopObserving()
    }

    // MARK: Settings

    var presentation: SwitcherPresentation { activePresentation ?? SwitcherPresentation.load() }
    var style: SwitcherStyle { presentation.effectiveStyle }
    private var autoSize: Bool { presentation.autoSize }
    private var sizeScale: Double { presentation.sizeScale }
    private var previewSelectedEnabled: Bool { presentation.previewSelected }
    private var colorScheme: ColorScheme? {
        switch presentation.theme { case .system: nil; case .light: .light; case .dark: .dark }
    }
    private var liveThumbnails: Bool { UserDefaults.standard.object(forKey: "switcher.liveThumbnails") as? Bool ?? true }
    var hoverSelects: Bool { UserDefaults.standard.object(forKey: "switcher.hoverSelects") as? Bool ?? true }

    func saveShortcuts(_ list: [SwitcherShortcut]) {
        let problems = SwitcherShortcutValidation.problems(list)
        guard problems.isEmpty else { shortcutEditingError = problems.joined(separator: " "); return }
        shortcutEditingError = nil
        SwitcherShortcutStore.save(list,shortcutSettings)
        shortcuts = SwitcherShortcutStore.load(shortcutSettings)
        configure()
    }

    func saveActionBindings(_ bindings: [SwitcherActionBinding]) {
        let problems = SwitcherActionBindings.problems(bindings)
        guard problems.isEmpty else { actionEditingError = problems.joined(separator: " "); return }
        actionEditingError = nil
        SwitcherActionBindings.save(bindings,shortcutSettings)
        actionBindings = SwitcherActionBindings.load(shortcutSettings)
    }

    /// The recorder needs raw key events, so registered hotkeys are released while it listens.
    @discardableResult func setRecording(_ recording: Bool) -> Bool {
        // Grant a single recorder even before SwiftUI has redrawn disabled sibling buttons.
        if recording && recordingShortcut { return false }
        recordingShortcut = recording
        configure()
        return true
    }

    var sessionHint: String {
        let choose: String
        if gestureOwner != nil { choose = String(localized: "Parmakları kaldır: seç") }
        else if let shortcut = activeShortcut, !heldModifiers.isEmpty, !model.isSearching, shortcut.releaseBehavior != .hold {
            let symbols = shortcut.effectiveHoldModifiers.symbols
            choose = shortcut.releaseBehavior == .search ? String(localized: "\(symbols) bırak: ara") : String(localized: "\(symbols) bırak: seç")
        } else if let binding = actionBindings.first(where: { $0.action == .choose && $0.keyCode != nil }) {
            choose = String(localized: "\(binding.displayName) seç")
        } else { choose = String(localized: "Tıklayarak seç") }
        if activeNavigation?.vim == true, !model.isSearching {
            return String(localized: "Vim · ⇥ gezin · yaz: ara · \(choose) · esc")
        }
        if layout.panelSize.width < 900 { return String(localized: "⇥ gezin · \(choose) · yaz: ara · esc") }
        var parts = [String(localized: "⇥ ilerle"), String(localized: "⇧⇥ geri"), choose, String(localized: "yaz: ara")]
        for action in [SwitcherActiveAction.close, .minimizeRestore, .quit] {
            if let binding = actionBindings.first(where: { $0.action == action && $0.keyCode != nil }) {
                parts.append("\(binding.displayName) \(action.localizedTitle)")
            }
        }
        parts.append("esc")
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
        model.reloadExceptions()
        updateShortcutExceptions()
#if DEBUG
        // Owned fixture audits exercise the policy without taking global keys or trackpad input.
        if syntheticAuditInput { return }
#endif
        let defaults = shortcutSettings
        let bindings = SwitcherActionBindings.load(defaults)
        if bindings != actionBindings { actionBindings = bindings }
        let stored = SwitcherShortcutStore.load(defaults)
        if stored != shortcuts { shortcuts = stored }
        let enabled = defaults.bool(forKey: "switcher.globalEnabled")
        let active = enabled && !recordingShortcut && suspendedForApplication == nil
        let gestures = SwitcherGestureOptions.load(gestureSettings)
        configureGestureInput(active ? gestures : .init())
        let wantsNativeKeys = active && shortcuts.contains(where: Self.usesNativeCommandTab)
        configureNativeKeyWatch(enabled: wantsNativeKeys)
        let signature = active ? shortcuts.map { "\($0.id):\($0.keyCode):\($0.modifiers.rawValue)" }.joined(separator: ",") : "off"
        if !enabled { registrationMessage = String(localized: "Global kısayol kapalı.") }
        else if recordingShortcut { registrationMessage = String(localized: "Kısayol kaydediliyor…") }
        else if let app = suspendedForApplication { registrationMessage = String(localized: "\(app) öndeyken kısayollar devre dışı.") }
        guard signature != registeredSignature else { return }
        registeredSignature = signature
        if nativeFailureSignature != signature { nativeFailureSignature = nil;nativeFailureMessage = nil }
        // Restore system switching before releasing our Carbon pair, including recorders,
        // exceptions and module shutdown. A guardian still exiting cannot overlap a new owner.
        if nativeKeyLease?.stop() == true { nativeKeyLease = nil }
        if !active,activeShortcut.map(Self.usesNativeCommandTab) == true { dismiss(animated: false) }
        for ref in keyRefs { registration.unregister(ref) }
        keyRefs = []
        hotkeyMap = [:]
        guard enabled else { registrationMessage = String(localized: "Global kısayol kapalı."); return }
        if recordingShortcut { registrationMessage = String(localized: "Kısayol kaydediliyor…"); return }
        if let app = suspendedForApplication { registrationMessage = String(localized: "\(app) öndeyken kısayollar devre dışı."); return }
        guard handler != nil else { registrationMessage = String(localized: "macOS kısayol dinleyicisini başlatamadı."); return }
        let problems = SwitcherShortcutValidation.problems(shortcuts)
        guard problems.isEmpty else { registrationMessage = problems.joined(separator: " "); return }
        var failures: [String] = []
        var nativeErrors: [String] = []
        for (index, shortcut) in shortcuts.enumerated() where index < SwitcherShortcut.maximumCount {
            let commandTab = Self.usesNativeCommandTab(shortcut)
            if commandTab,nativeFailureSignature == signature,let message = nativeFailureMessage {
                nativeErrors.append(message)
                continue
            }
            var pair: [(id: UInt32, ref: EventHotKeyRef, backwards: Bool)] = []
            var failed = false
            for backwards in [false, true] {
                let id = UInt32(index * 2 + (backwards ? 2 : 1))
                let flags = shortcut.modifiers.carbonFlags | (backwards ? SwitcherModifiers.carbonShift : 0)
                let (status,ref) = registration.register(shortcut.keyCode,flags,EventHotKeyID(signature: Self.signature,id: id))
                if status == noErr, let ref {
                    pair.append((id, ref, backwards))
                } else {
                    failed = true
                    failures.append("\(backwards ? "⇧" : "")\(shortcut.displayName) (\(status))")
                }
            }
            if !failed,commandTab {
                do {
                    guard nativeKeyLease == nil else { throw SwitcherNativeKeyError.unavailable }
                    nativeKeyLease = try registration.acquireNative()
                } catch {
                    failed = true
                    nativeFailureSignature = signature
                    nativeFailureMessage = error.localizedDescription
                    nativeErrors.append(error.localizedDescription)
                }
            }
            if failed { for entry in pair { registration.unregister(entry.ref) } }
            else { for entry in pair { keyRefs.append(entry.ref); hotkeyMap[entry.id] = (index, entry.backwards) } }
        }
        if !failures.isEmpty {
            let list = failures.joined(separator: ", ")
            registrationMessage = String(localized: "Kaydedilemedi: \(list). Başka bir uygulama aynı kısayolu kullanıyor olabilir.")
        } else {
            let list = shortcuts.map(\.displayName).joined(separator: ", ")
            registrationMessage = String(localized: "\(list) etkin. Shift ile ters yönde gezin.")
        }
        if !nativeErrors.isEmpty {
            let ordinaryFailure = failures.isEmpty ? "" : registrationMessage + " "
            registrationMessage = ordinaryFailure + nativeErrors.joined(separator: " ")
        }
    }

    private static func usesNativeCommandTab(_ shortcut: SwitcherShortcut) -> Bool {
        shortcut.keyCode == SwitcherKeys.tab && shortcut.modifiers == .command
    }

    private func ownsNativeKeys(for shortcut: SwitcherShortcut) -> Bool {
        guard Self.usesNativeCommandTab(shortcut) else { return true }
#if DEBUG
        if syntheticAuditInput { return !auditNativeKeysLost }
#endif
        return nativeKeyLease?.isActive == true
    }

    var canRetryNativeKeys: Bool { nativeFailureMessage != nil }
    func retryNativeKeys() {
        nativeFailureSignature = nil
        nativeFailureMessage = nil
        registeredSignature = ""
        configure()
    }

    private func configureNativeKeyWatch(enabled: Bool) {
        guard enabled else { nativeKeyTimer?.invalidate();nativeKeyTimer = nil;return }
        guard nativeKeyTimer == nil else { return }
        let timer = Timer(timeInterval: 1,repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNativeKeys() }
        }
        timer.tolerance = 0.2
        nativeKeyTimer = timer
        RunLoop.main.add(timer,forMode: .common)
    }

    private func checkNativeKeys() {
        guard moduleRunning else { return }
        guard let lease = nativeKeyLease,!lease.pulse() else { return }
        // Do not restart an unexpectedly dead guardian repeatedly. A preference
        // transition permits another acquisition; ordinary Option shortcuts remain registered.
        nativeFailureSignature = registeredSignature
        nativeFailureMessage = SwitcherNativeKeyError.unavailable.localizedDescription
        registeredSignature = ""
        if activeShortcut.map(Self.usesNativeCommandTab) == true { dismiss(animated: false) }
        configure()
    }

    private func applicationActivated(_ bundleID: String?) {
        configure()
        // Keep the catalog warm so the switcher opens with current windows instantly. MacPocket itself
        // becoming active needs no rescan (nobody is switching), and the scan walks every app via AX.
        let isSelf = bundleID == Bundle.main.bundleIdentifier
        if sessionID == nil, !isSelf, !keyRefs.isEmpty, Date().timeIntervalSince(lastPrewarm) > 5 {
            lastPrewarm = Date()
            schedulePrewarm(delay: .milliseconds(400))
        }
    }

    private var mayObserveConditionalExceptions: Bool {
#if DEBUG
        if syntheticAuditInput { return !recordingShortcut }
#endif
        return !recordingShortcut && shortcutSettings.bool(forKey: "switcher.globalEnabled")
    }

    private func cancelConditionalExceptions() {
        conditionalExceptionTask?.cancel()
        conditionalExceptionTask = nil
        conditionalExceptionContext = nil
        conditionalFullscreen = nil
    }

    /// Recomputed on startup, preference edits, application/Space changes and conditional samples.
    /// Only a matching fullscreen rule owns a timer; unknown AX state leaves keys available.
    private func updateShortcutExceptions() {
        guard let application = exceptionApplication() else {
            cancelConditionalExceptions()
            suspendedForApplication = nil
            return
        }
        let rules = model.exceptionRules.filter { $0.matches(bundleIdentifier: application.bundleIdentifier, applicationPath: application.applicationPath) }
        let always = rules.contains { $0.shortcuts == .alwaysDisable }
        let conditional = rules.filter { $0.shortcuts == .fullscreen }
        if always || conditional.isEmpty || !mayObserveConditionalExceptions {
            cancelConditionalExceptions()
        } else {
            let context = ConditionalExceptionContext(application: application, rules: conditional)
            if context != conditionalExceptionContext {
                cancelConditionalExceptions()
                conditionalExceptionContext = context
                conditionalExceptionTask = Task { [weak self, fullscreenReader] in
                    while !Task.isCancelled {
                        let sample = await fullscreenReader(application)
                        guard !Task.isCancelled, self?.acceptConditionalSample(sample, context: context) == true else { return }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            }
        }
        let disabled = rules.contains { $0.disablesShortcuts(bundleIdentifier: application.bundleIdentifier, applicationPath: application.applicationPath, fullscreen: conditionalFullscreen) }
        let name = disabled ? (application.name ?? application.bundleIdentifier ?? String(localized: "Uygulama")) : nil
        if suspendedForApplication != name { suspendedForApplication = name }
    }

    private func acceptConditionalSample(_ fullscreen: Bool?, context: ConditionalExceptionContext) -> Bool {
        guard moduleRunning, conditionalExceptionContext == context else { return false }
        guard exceptionApplication() == context.application else {
            configure()
            return false
        }
        if conditionalFullscreen != fullscreen {
            conditionalFullscreen = fullscreen
            configure()
        }
        return conditionalExceptionContext == context
    }

    private func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
        prewarmID = nil
    }

    private func schedulePrewarm(delay: Duration = .zero) {
        cancelPrewarm()
        let id = UUID(), environment = environmentGeneration
        prewarmID = id
        prewarmTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            defer { if prewarmID == id { prewarmTask = nil; prewarmID = nil } }
            guard !Task.isCancelled, moduleRunning, sessionID == nil, environment == environmentGeneration else { return }
            await model.refresh()
            guard !Task.isCancelled, moduleRunning, sessionID == nil, environment == environmentGeneration else { return }
            preparedEnvironment = environment
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
        return shortcuts.indices.first { index in
            shortcuts[index].keyCode == event.keyCode && shortcuts[index].modifiers == pressed
                && ownsNativeKeys(for: shortcuts[index])
                && hotkeyMap.values.contains(where: { $0.index == index })
        }
    }

    private func handleFlags(_ event: NSEvent) -> Bool {
        handleModifierState(event.modifierFlags)
    }

    @discardableResult private func handleModifierState(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard sessionID != nil, let shortcut = activeShortcut, !heldModifiers.isEmpty,
              flags.intersection(heldModifiers).isEmpty else { return false }
        guard ownsNativeKeys(for: shortcut) else { dismiss(animated: false);return true }
        heldModifiers = []
        modifierTimer?.invalidate()
        modifierTimer = nil
        switch SwitcherReleaseDecision.resolve(shortcut.releaseBehavior, isSearching: model.isSearching) {
        case .choose:
#if DEBUG
            if let id = sessionID { onModifierReleaseCommitForAudit?(id) }
#endif
            requestCommit()
        case .beginSearch:
            revealHeldPanel()
            model.beginSearch()
        case .keepOpen: revealHeldPanel()
        }
        return true
    }

    private func revealHeldPanel() {
        guard let id = sessionID, panel?.isVisible != true else { return }
        showTask?.cancel()
        showTask = nil
        presentPanel(sessionID: id)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if !heldModifiers.isEmpty,let shortcut = activeShortcut,!ownsNativeKeys(for: shortcut) {
            dismiss(animated: false)
            return true
        }
        let flags = event.modifierFlags
        let command = SwitcherPanelInput.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
            modifiers: Self.switcherModifiers(flags), shift: flags.contains(.shift), held: Self.switcherModifiers(heldModifiers),
            isSearching: model.isSearching, options: activeNavigation ?? SwitcherNavigationOptions.load(), bindings: actionBindings)
        if let command {
            switch command {
            case .move(let backwards, let count): step(backwards: backwards, by: count)
            case .row(let backwards): stepRow(backwards: backwards)
            case .ignore: break
            case .action(let action):
                switch action {
                case .choose: requestCommit()
                case .previous: step(backwards: true)
                case .cancel: cancelOrClearSearch()
                case .search: model.beginSearch()
                case .close: perform(.close)
                case .minimizeRestore: perform(model.selected?.minimized == true ? .restore : .minimize)
                case .fullScreen: perform(.toggleFullScreen)
                case .hide: perform(.hideApplication)
                case .quit: perform(.quitApplication)
                }
            }
            return true
        }
        switch Int(event.keyCode) {
        case kVK_Delete:
            if !model.sessionSearch.isEmpty { model.sessionSearch.removeLast() }
            return true
        default: break
        }
        if flags.contains(.command), !heldModifiers.contains(.command) { return true }
        guard let character = event.charactersIgnoringModifiers, !character.isEmpty,
              character.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).union(.whitespaces).contains($0) })
        else { return false }
        model.beginSearch()
        model.sessionSearch += character
        return true
    }

    private func cancelOrClearSearch() {
        if !model.sessionSearch.isEmpty { model.sessionSearch = "" } else { dismiss(restorePrevious: true) }
    }

    private func receiveHotkey(_ id: UInt32, source: String, timestamp: TimeInterval) {
        guard let entry = hotkeyMap[id] else { return }
        receiveShortcut(index: entry.index, backwards: entry.backwards, source: source, timestamp: timestamp)
#if DEBUG
        if source == "carbon" { onCarbonInvocationForAudit?(id,sessionID) }
#endif
    }

    private func receiveShortcut(index: Int, backwards: Bool, source: String, timestamp: TimeInterval) {
        guard !keyRefs.isEmpty, shortcuts.indices.contains(index) else { return }
        guard ownsNativeKeys(for: shortcuts[index]) else { return }
        // Some delivery paths provide both Carbon and NSEvent for one physical press.
        guard invocations.accepts(id: shortcuts[index].id, backwards: backwards, source: source, timestamp: timestamp) else { return }
        summon(shortcut: shortcuts[index], backwards: backwards, holdsModifiers: true)
    }

    // MARK: Session

    var commandPanelVisible: Bool { panel?.isVisible == true }
    func hideFromCommand() { cancelFocus();dismiss(animated: false) }
    func showFromCommand(profile: Int) -> Bool {
        guard moduleRunning,!recordingShortcut,shortcuts.indices.contains(profile-1) else { return false }
        let target = shortcuts[profile-1]
        // Repeated show is idempotent: it must not cycle the selection like another Tab press.
        if sessionID != nil,activeShortcut == target,activePresentation == target.presentation.resolve(over: SwitcherPresentation.load()) { return true }
        show(shortcut: target)
        return sessionID != nil
    }

    /// Opens the switcher from the settings preview button.
    func show(shortcut: SwitcherShortcut? = nil) {
        let target = shortcut ?? shortcuts.first ?? .defaultOptionTab
        if sessionID != nil, activeShortcut != target || activePresentation != target.presentation.resolve(over: SwitcherPresentation.load()) {
            dismiss(animated: false)
        }
        summon(shortcut: target, backwards: false, holdsModifiers: false)
    }

    private var gestureInputAllowed: Bool {
        moduleRunning && !recordingShortcut && suspendedForApplication == nil
            && gestureSettings.bool(forKey: "switcher.globalEnabled")
    }

    private func configureGestureInput(_ options: SwitcherGestureOptions) {
        guard options != configuredGestureOptions else { return }
        if gestureOwner != nil { dismiss(animated: false) }
        configuredGestureOptions = options
        if options.enabled {
            gestureMonitor.configure(options: options) { [weak self] in self?.receiveGesture($0) }
        } else { gestureMonitor.stop() }
    }

    /// A gesture owns only the panel it opened. Lift/cancel cannot commit an unrelated keyboard
    /// session, and Escape suppresses subsequent frames of that same held gesture.
    private func receiveGesture(_ event: SwitcherGestureEvent) {
        switch event {
        case .step(let id,let axis,let backwards,let count):
            guard gestureInputAllowed,let options = configuredGestureOptions,options.enabled,
                  options.axis == axis,(1...32).contains(count),blockedGestureID != id else { return }
            var remaining = count
            if gestureOwner == nil {
                guard sessionID == nil else { blockedGestureID = id;return }
                var shortcut = shortcuts.first ?? .defaultOptionTab
                shortcut.releaseBehavior = .hold
                summon(shortcut: shortcut,backwards: backwards,holdsModifiers: false,skipsForeground: true)
                guard let sessionID else { blockedGestureID = id;return }
                gestureOwner = (id,sessionID,options.haptics)
                gestureFeedbackSelection = nil
                remaining -= 1
            }
            guard gestureOwner?.id == id,gestureOwner?.session == sessionID else { return }
            if remaining > 0 {
                if axis == .horizontal { step(backwards: backwards,by: remaining) }
                else { for _ in 0..<remaining { stepRow(backwards: backwards) } }
            }
            provideGestureFeedback()
        case .ended(let id):
            if blockedGestureID == id { blockedGestureID = nil }
            guard gestureOwner?.id == id,gestureOwner?.session == sessionID else { return }
            gestureOwner = nil
            gestureFeedbackSelection = nil
            guard gestureInputAllowed else { dismiss(animated: false);return }
            // Typing/search intentionally retains the HUD on keyboard modifier release too.
            // Lifting fingers must not commit a partially entered query.
            guard !model.isSearching else { return }
            requestCommit()
        case .cancelled(let id):
            if blockedGestureID == id { blockedGestureID = nil }
            guard gestureOwner?.id == id,gestureOwner?.session == sessionID else { return }
            gestureOwner = nil
            gestureFeedbackSelection = nil
            dismiss(animated: false)
        }
    }

    private func provideGestureFeedback() {
        guard let owner = gestureOwner,owner.session == sessionID,owner.haptics,!preparing,
              let selection = model.selected?.id,selection != gestureFeedbackSelection else { return }
        gestureFeedbackSelection = selection
        gestureFeedback()
    }

    private func step(backwards: Bool, by count: Int = 1) {
        if let id = sessionID, panel?.isVisible != true { showTask?.cancel(); presentPanel(sessionID: id) }
        if preparing {
            pendingNavigation.append(.linear(backwards ? -count : count))
            model.selection = preparationSelection()
        } else { model.cycle(backwards: backwards, by: count) }
    }

    private func stepRow(backwards: Bool) {
        if let id = sessionID, panel?.isVisible != true { showTask?.cancel(); presentPanel(sessionID: id) }
        if preparing {
            pendingNavigation.append(.row(backwards: backwards))
            model.selection = preparationSelection()
        } else { model.moveRow(backwards: backwards,columns: layout.columns) }
    }

    private func summon(shortcut: SwitcherShortcut, backwards: Bool, holdsModifiers: Bool,skipsForeground: Bool = false) {
        guard moduleRunning else { return }
        if sessionID != nil {
            var current = activeShortcut
            // Gestures retain the HUD until fingers lift, but the keyboard must recover the
            // profile's original release behavior when taking over that same session.
            if gestureOwner != nil { current?.releaseBehavior = shortcut.releaseBehavior }
            if current == shortcut, activePresentation == shortcut.presentation.resolve(over: SwitcherPresentation.load()) {
                if holdsModifiers {
                    if let owner = gestureOwner { blockedGestureID = owner.id }
                    gestureOwner = nil
                    gestureFeedbackSelection = nil
                    activeShortcut = shortcut
                    heldModifiers = Self.eventFlags(shortcut.effectiveHoldModifiers)
                    startModifierWatch(shortcut)
                }
                step(backwards: backwards)
                if holdsModifiers { handleModifierState(currentModifierFlags()) }
                return
            }
            dismiss()
        }
        cancelFocus()
        let id = UUID()
        sessionID = id
        preparing = true
        commitWhenReady = false
        preparationOrigin = .opening
        activeShortcut = shortcut
        activePresentation = shortcut.presentation.resolve(over: SwitcherPresentation.load())
        activeNavigation = SwitcherNavigationOptions.load()
        activeCursorPolicy = SwitcherCursorPolicy.load()
        heldModifiers = holdsModifiers ? Self.eventFlags(shortcut.effectiveHoldModifiers) : []
        previousApplication = foregroundApplication()
        let foregroundPID = previousApplication?.processIdentifier
        let screen = screenForSession()
        sessionScreen = screen
        openedAtMouse = NSEvent.mouseLocation
        model.captureSessionPointer(at: Self.coreGraphicsPoint(openedAtMouse))
        model.foregroundPID = foregroundPID
        model.resetSessionSearch()
        model.failure = nil
        model.sessionFilter = shortcut.filter
        model.sessionOrder = presentation.order
        model.sessionDisplayID = screen.flatMap(Self.displayID)
        model.clearThumbnails()
        // The cached list (kept warm in the background) appears immediately; a fresh snapshot follows.
        pendingNavigation = []
        sessionBackwards = backwards
        sessionForegroundPID = holdsModifiers || skipsForeground ? foregroundPID : nil
        model.selection = WindowSwitchSelection.initial(model.filtered, foregroundPID: sessionForegroundPID,
                                                        backwards: backwards, queuedSteps: 0)
        if holdsModifiers, !model.filtered.isEmpty {
            let delay = presentation.openingDelayMilliseconds
            showTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self, sessionID == id else { return }
                presentPanel(sessionID: id)
            }
        } else { presentPanel(sessionID: id) }
        startModifierWatch(shortcut)
        openingTask = Task { [weak self] in
            guard let self else { return }
            await model.refresh()
            guard !Task.isCancelled, sessionID == id else { return }
            completePreparation(sessionID: id)
        }
    }

    private func presentPanel(sessionID id: UUID) {
        if panel == nil {
            // Non-activating: the app in front stays active, so nothing flickers and MacPocket's own windows
            // never come forward. The panel still becomes key to receive navigation and search keys.
            let panel = SwitcherCardPanel(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
            panel.title = String(localized: "MacPocket · Pencere Geçişi")
            panel.setAccessibilityLabel(String(localized: "MacPocket pencere geçişi"))
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
            self.panel = panel
        }
        // Closing may have left the window-server fade behaviour set; ordering in uses our own fade.
        panel?.animationBehavior = .none
        panel?.ignoresMouseEvents = false
        relayout(force: true)
        switch presentation.theme {
        case .system: panel?.appearance = nil
        case .light: panel?.appearance = NSAppearance(named: .aqua)
        case .dark: panel?.appearance = NSAppearance(named: .darkAqua)
        }
        installRoot(WindowSwitcherOverlayView(model: model, controller: self, choose: { [weak self] target in
            self?.model.selection = target
            self?.requestCommit()
        }, thumbnailSessionID: model.thumbnailSessionID, reduceTransparencyOverride: transparencyOverride), session: id)
        let duration = SwitcherMotionPlan(presentation: presentation, reduceMotion: PocketReduceMotion.isEnabled).opening
        NSAnimationContext.runAnimationGroup { context in context.duration = 0; panel?.animator().alphaValue = duration > 0 ? 0 : 1 }
        panel?.makeKeyAndOrderFront(nil)
        if duration > 0 { NSAnimationContext.runAnimationGroup { $0.duration = duration; panel?.animator().alphaValue = 1 } }
        if outsideClickMonitor == nil, watchesExternalClicks {
            // Clicks inside the panel are local events; anything reaching this monitor landed elsewhere.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in self?.dismiss() }
            }
        }
        startApplicationBadges()
        if thumbnailsWanted || !preparing { thumbnailsWanted = false; startThumbnails() }
        updatePreview()
    }

    /// Releasing the held modifiers chooses, even before the panel is visible or key (`flagsChanged` alone
    /// misses fast taps). `NSEvent.modifierFlags` needs no permission.
    private func startModifierWatch(_ shortcut: SwitcherShortcut) {
        modifierTimer?.invalidate()
        modifierTimer = nil
        guard !heldModifiers.isEmpty, shortcut.releaseBehavior != .hold else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleModifierState(self.currentModifierFlags())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    /// Search or refresh can filter out the selected window; keep a valid selection so ↩ always has a target.
    private func listChanged() {
        relayout()
        guard sessionID != nil else { return }
        let visible = model.filtered
        if !visible.contains(where: { $0.id == model.selection }) { model.selection = visible.first?.id }
        model.requestThumbnails()
    }

    private func screenForSession() -> NSScreen? {
        let screens = NSScreen.screens
        let descriptors = screens.compactMap { screen in Self.displayID(screen).map { ($0, screen.frame) } }
        var activeFrame: CGRect?
        if presentation.screen == .activeWindow, let pid = previousApplication?.processIdentifier {
            let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
            for row in rows {
                guard row[kCGWindowOwnerPID as String] as? Int32 == pid, row[kCGWindowLayer as String] as? Int == 0,
                      let bounds = row[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                      frame.width > 40, frame.height > 40 else { continue }
                activeFrame = Self.cocoaRect(frame)
                break
            }
        }
        let id = presentation.screen.displayID(screens: descriptors, pointer: NSEvent.mouseLocation,
            activeWindowFrame: activeFrame, primaryDisplayID: CGMainDisplayID())
        return screens.first { Self.displayID($0) == id } ?? screens.first
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
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func startApplicationBadges() {
        badgeTask?.cancel()
        badgeTask = nil
        model.stopApplicationBadges()
        guard sessionID != nil,panel?.isVisible == true,presentation.showBadges else { return }
        let epoch = model.beginApplicationBadges()
        badgeTask = Task { [weak self] in await self?.model.runApplicationBadges(session: epoch) }
    }

    private func startThumbnails() {
        thumbnailTask?.cancel()
        guard style == .thumbnails else { return }
        let scale = sessionScreen?.backingScaleFactor ?? 2
        let size = CGSize(width: layout.itemSize.width * scale, height: layout.itemSize.height * scale)
        let live = liveThumbnails
        thumbnailTask = Task { [weak self] in await self?.model.runThumbnails(maxPixels: size, live: live) }
    }

    private func selectionChanged() {
        guard sessionID != nil else { return }
        model.requestThumbnails()
        if let window = model.selected, NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: "\(window.application), \(window.title)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        updatePreview()
    }

    /// Shows the selected window at its real position and size behind the switcher.
    private func updatePreview() {
        previewTask?.cancel()
        // Hide the old target immediately, including while the new target's capture is pending.
        previewPanel?.orderOut(nil)
        guard sessionID != nil, previewSelectedEnabled, let window = model.selected, let frame = window.frame, !window.minimized else {
            previewPanel?.orderOut(nil)
            return
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
            let duration = SwitcherMotionPlan(presentation: presentation, reduceMotion: PocketReduceMotion.isEnabled).preview
            previewPanel?.show(preview.image, at: Self.cocoaRect(frame), animationDuration: duration)
        }
    }

    private func requestCommit() {
        guard sessionID != nil else { return }
        // A warm cache is usable only within the same Space/display environment. Changes while
        // closed also require a fresh scan before release can choose from a nonempty cached list.
        if preparing && (model.filtered.isEmpty || preparedEnvironment != environmentGeneration) {
            commitWhenReady = true
        } else { activateSelection() }
    }

    private func activateSelection() {
        guard let target = model.selected?.id else { dismiss(); return }
        let cursorPolicy = activeCursorPolicy ?? .never
        dismiss()
        cancelFocus()
        let id = UUID()
        focusID = id
        focusTask = Task { [weak self] in
            guard !Task.isCancelled, let self, focusID == id else { return }
            defer { if focusID == id { focusTask = nil; focusID = nil } }
            await model.focus(id: target,cursorPolicy: cursorPolicy)
            guard !Task.isCancelled, focusID == id else { return }
            if let failure = model.failure { registrationMessage = failure }
        }
    }

    private func cancelFocus() { focusTask?.cancel(); focusTask = nil; focusID = nil }

    private func perform(_ action: WindowAction) {
        guard let target = model.selected, !model.actionBusy, let actionSession = sessionID else { return }
        Task { [weak self] in
            guard let self else { return }
            await model.action(action, id: target.id)
            // Keep the panel key: hiding or quitting an app may move focus elsewhere.
            guard sessionID == actionSession else { return }
            panel?.makeKeyAndOrderFront(nil)
            if !model.filtered.contains(where: { $0.id == model.selection }) { model.selection = model.filtered.first?.id }
        }
    }

    /// Mouse hover selects only after the pointer moves, so a resting cursor under the panel
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

    /// One hosting view per panel, as AppKit/SwiftUI guidance recommends for reused content: a session swaps
    /// the root view instead of rebuilding the hosting view, renderer and layer tree. The panel frame is set
    /// explicitly by `relayout`, so the hosting view needs no size constraints (`sizingOptions = []`).
    private func installRoot(_ overlay: WindowSwitcherOverlayView, session: UUID) {
        let root = WindowSwitcherPanelRoot(overlay: overlay, colorScheme: colorScheme, session: session)
        if let hostingView, panel?.contentView === hostingView {
            hostingView.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            view.sizingOptions = []
            hostingView = view
            panel?.contentView = view
        }
    }

    private func dismiss(restorePrevious: Bool = false, animated: Bool = true) {
        let fadesOut = animated && SwitcherMotionPlan(presentation: presentation, reduceMotion: PocketReduceMotion.isEnabled).closing > 0
        let previous = restorePrevious ? previousApplication : nil
        if let owner = gestureOwner { blockedGestureID = owner.id }
        gestureOwner = nil
        gestureFeedbackSelection = nil
        sessionID = nil
        preparing = false
        commitWhenReady = false
        pendingNavigation = []
        model.cancelActionReconciliation()
        preparationOrigin = .opening
        openingTask?.cancel()
        openingTask = nil
        showTask?.cancel()
        showTask = nil
        modifierTimer?.invalidate()
        modifierTimer = nil
        thumbnailsWanted = false
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        badgeTask?.cancel()
        badgeTask = nil
        model.stopApplicationBadges()
        previewTask?.cancel()
        previewTask = nil
        activeShortcut = nil
        activePresentation = nil
        activeNavigation = nil
        activeCursorPolicy = nil
        model.sessionFilter = nil
        model.sessionOrder = nil
        model.captureSessionPointer(at: nil)
        model.resetSessionSearch()
        model.clearThumbnails()
        previewPanel?.orderOut(nil)
        // AppKit orders the panel out (and releases key status) synchronously; with `.utilityWindow` the
        // window server then fades its last frame on the GPU. The previous owned snapshot re-rendered the
        // whole panel on the CPU (`cacheDisplay`, blurring every card shadow): ~390 ms on the main thread
        // with 24 windows.
        panel?.animationBehavior = fadesOut ? .utilityWindow : .none
        panel?.orderOut(nil)
        if let previous, !previous.isTerminated, !previous.isActive,
           previous.processIdentifier != ProcessInfo.processInfo.processIdentifier { previous.activate(options: []) }
    }

    private static func eventFlags(_ modifiers: SwitcherModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    private static func switcherModifiers(_ flags: NSEvent.ModifierFlags) -> SwitcherModifiers {
        [flags.contains(.control) ? .control : [], flags.contains(.option) ? .option : [], flags.contains(.command) ? .command : []]
    }

    /// CoreGraphics (top-left origin) → AppKit (bottom-left origin) global coordinates.
    static func cocoaRect(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func coreGraphicsPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
}

/// The panel's root: a new `session` id gives each opening fresh view state inside the reused hosting view.
struct WindowSwitcherPanelRoot: View {
    let overlay: WindowSwitcherOverlayView
    let colorScheme: ColorScheme?
    let session: UUID
    var body: some View { overlay.preferredColorScheme(colorScheme).id(session) }
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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
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

    func show(_ image: NSImage, at frame: NSRect, animationDuration: TimeInterval = 0) {
        imageView.image = image
        setFrame(frame, display: true)
        NSAnimationContext.runAnimationGroup { $0.duration = 0; animator().alphaValue = animationDuration > 0 ? 0 : 1 }
        orderFront(nil)
        if animationDuration > 0 { NSAnimationContext.runAnimationGroup { $0.duration = animationDuration; animator().alphaValue = 1 } }
    }
}

#if DEBUG
extension WindowSwitcherHotkeyController {
    func beginPhysicalInputAudit() {
        guard !moduleRunning else { return }
        moduleRunning = true
        observeModelChanges()
        observeEnvironmentChanges()
        installCarbonHandler()
        installLocalMonitor()
        configure()
    }
    func beginRegistrationAudit() {
        guard !moduleRunning else { return }
        moduleRunning = true
        installCarbonHandler()
        configure()
    }
    func refreshRegistrationForAudit() { configure() }
    func checkNativeKeysForAudit() { checkNativeKeys() }
    func loseNativeKeysForAudit() { guard syntheticAuditInput else { return };auditNativeKeysLost = true }
    var moduleDiagnosticResources: [String: Int] { ["nativeKeyLease": nativeKeyLease?.isRunning == true ? 1 : 0, "nativeKeyTimer": nativeKeyTimer == nil ? 0 : 1, "hotKeys": keyRefs.count, "handler": handler == nil ? 0 : 1, "monitor": monitor == nil ? 0 : 1, "subscriptions": subscriptions.count, "prewarmTask": prewarmTask == nil ? 0 : 1, "focusTask": focusTask == nil ? 0 : 1, "conditionalExceptionTask": conditionalExceptionTask == nil ? 0 : 1, "gestureMonitor": configuredGestureOptions?.enabled == true && gestureMonitor.isRunning ? 1 : 0, "badgeTask": badgeTask == nil ? 0 : 1] }
    func beginGestureAudit() {
        syntheticAuditInput = true
        auditReduceTransparency = true
        moduleRunning = true
        if subscriptions.isEmpty { observeModelChanges();observeEnvironmentChanges() }
        if monitor == nil { installLocalMonitor() }
        shortcuts = SwitcherShortcutStore.load(gestureSettings)
        configureGestureInput(gestureInputAllowed ? SwitcherGestureOptions.load(gestureSettings) : .init())
    }
    func updateGestureSettingsForAudit() {
        configureGestureInput(gestureInputAllowed ? SwitcherGestureOptions.load(gestureSettings) : .init())
    }
    var gestureOwnedForAudit: Bool { gestureOwner != nil }
    func updateExceptionsForAudit() {
        syntheticAuditInput = true
        moduleRunning = true
        if subscriptions.isEmpty { observeEnvironmentChanges() }
        configure()
    }
    func schedulePrewarmForAudit(delay: Duration) { moduleRunning = true; schedulePrewarm(delay: delay) }

    /// Isolated visual fixture: ordinary overlay and event monitor, no global hotkey registration,
    /// no catalog refresh, and no handles that could mutate other applications' windows.
    func beginVisualAudit(reduceTransparency: Bool, shortcut: SwitcherShortcut = .defaultOptionTab) -> NSPanel? {
        syntheticAuditInput = true
        auditReduceTransparency = reduceTransparency
        cancelFocus()
        moduleRunning = true
        if subscriptions.isEmpty { observeModelChanges(); observeEnvironmentChanges() }
        if monitor == nil { installLocalMonitor() }
        let id = UUID()
        sessionID = id
        activeShortcut = shortcut
        activePresentation = shortcut.presentation.resolve(over: SwitcherPresentation.load())
        activeNavigation = SwitcherNavigationOptions.load()
        activeCursorPolicy = SwitcherCursorPolicy.load()
        previousApplication = foregroundApplication()
        sessionScreen = screenForSession()
        model.sessionDisplayID = sessionScreen.flatMap(Self.displayID)
        openedAtMouse = NSEvent.mouseLocation
        model.captureSessionPointer(at: Self.coreGraphicsPoint(openedAtMouse))
        model.sessionFilter = shortcut.filter
        model.sessionOrder = presentation.order
        presentPanel(sessionID: id)
        installRoot(WindowSwitcherOverlayView(model: model, controller: self, choose: { _ in },
                                              thumbnailSessionID: model.thumbnailSessionID,
                                              reduceTransparencyOverride: reduceTransparency), session: UUID())
        return panel
    }

    var auditPanel: NSPanel? { panel }
    func beginHeldAudit(shortcut: SwitcherShortcut) {
        syntheticAuditInput = true
        auditReduceTransparency = true
        moduleRunning = true
        if subscriptions.isEmpty { observeModelChanges(); observeEnvironmentChanges() }
        if monitor == nil { installLocalMonitor() }
        summon(shortcut: shortcut, backwards: false, holdsModifiers: true)
    }
    func dismissForAudit() { dismiss() }
    func commitForAudit() { requestCommit() }
    var previewVisibleForAudit: Bool { previewPanel?.isVisible == true }
    var closingFadeRequestedForAudit: Bool { panel?.animationBehavior == .utilityWindow }
    var preparingForAudit: Bool { preparing }
    func releaseModifiersForAudit() {
        guard let activeShortcut else { return }
        heldModifiers = Self.eventFlags(activeShortcut.effectiveHoldModifiers)
        handleModifierState([])
    }
}
#endif

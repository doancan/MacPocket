import Carbon.HIToolbox
import MacPocketCore

/// One system-wide shortcut. All instances share a single Carbon handler under their own signature, so they
/// coexist with the window switcher's hotkeys (which use another signature and pass ours through).
@MainActor
final class PocketGlobalHotKey {
    private static let signature: OSType = 0x4D50_484B // 'MPHK'
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handler: EventHandlerRef?
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: () -> Void
    private var reference: EventHotKeyRef?
    private(set) var registered: KeyCombo?

    init(action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action
    }

    isolated deinit { unregister() }

    /// Registers `combo`, replacing any previous one. Returns false when macOS refuses it (another app owns
    /// it).
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        if registered == combo, reference != nil { return true }
        unregister()
        Self.installHandler()
        guard combo.isValidGlobalShortcut, Self.handler != nil else { Self.removeUnusedHandler(); return false }
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonFlags, EventHotKeyID(signature: Self.signature, id: id),
                                         GetEventDispatcherTarget(), 0, &newReference)
        guard status == noErr, let newReference else { Self.removeUnusedHandler(); return false }
        reference = newReference
        registered = combo
        Self.actions[id] = action
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        registered = nil
        Self.actions[id] = nil
        Self.removeUnusedHandler()
    }

    private static func removeUnusedHandler() {
        guard actions.isEmpty, let handler else { return }
        RemoveEventHandler(handler)
        Self.handler = nil
    }

    #if DEBUG
    static var diagnosticResources: [String: Int] {
        ["actions": actions.count, "handler": handler == nil ? 0 : 1]
    }
    #endif

    private static func installHandler() {
        guard handler == nil else { return }
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard result == noErr, hotKey.signature == PocketGlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKey.id
            Task { @MainActor in PocketGlobalHotKey.actions[id]?() }
            return noErr
        }, 1, &specification, nil, &handler)
    }
}

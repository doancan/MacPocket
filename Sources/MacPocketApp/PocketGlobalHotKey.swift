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
    private var reference: EventHotKeyRef?
    private(set) var registered: KeyCombo?

    init(action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        Self.installHandler()
    }

    /// Registers `combo`, replacing any previous one. Returns false when macOS refuses it (another app owns it).
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        if registered == combo, reference != nil { return true }
        unregister()
        guard combo.isValidGlobalShortcut, Self.handler != nil else { return false }
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonFlags, EventHotKeyID(signature: Self.signature, id: id),
                                         GetEventDispatcherTarget(), 0, &newReference)
        guard status == noErr, let newReference else { return false }
        reference = newReference
        registered = combo
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        registered = nil
    }

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

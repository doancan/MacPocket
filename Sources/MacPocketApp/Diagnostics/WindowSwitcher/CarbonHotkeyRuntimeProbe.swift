#if DEBUG
import AppKit
@preconcurrency import Carbon
import MacPocketCore

/// Registers only two explicit unused function-key chords, posts marked owned events, and
/// records Carbon hotkey IDs. No event tap, raw keyboard listener or symbolic-hotkey setter.
@MainActor enum CarbonHotkeyRuntimeProbe {
    private final class Counter { var pressed: [UInt32] = [],released: [UInt32] = [] }
    private static let signature: OSType = 0x4D504350
    private static let marker: Int64 = 0x4D50_4341_5242
    static func run(fixturePID: Int32,activateFixture: () async throws -> Void) async throws -> ([String:Bool],[String:Any]) {
        let before = SecureKeyboardInputStatus.read(),nativeBefore = SwitcherNativeKeyGuard.currentState()
        var checks: [String:Bool] = [:]
        guard CGPreflightPostEventAccess() else { throw WindowCatalogError.permissionRequired }
        try await activateFixture()
        try await Task.sleep(for: .milliseconds(150))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID else { throw WindowCatalogError.focusFailed }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]).isEmpty else { throw WindowCatalogError.unsupported }
        let counter = Counter()
        var handler: EventHandlerRef?
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard),eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard),eventKind: UInt32(kEventHotKeyReleased))]
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _,event,context in
            guard let event,let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id) == noErr,
                  id.signature == CarbonHotkeyRuntimeProbe.signature else { return OSStatus(eventNotHandledErr) }
            let counter = Unmanaged<Counter>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyPressed) { counter.pressed.append(id.id) }
                else { counter.released.append(id.id) }
            }
            return noErr
        },types.count,&types,Unmanaged.passUnretained(counter).toOpaque(),&handler)
        guard installed == noErr,let handler else { throw WindowCatalogError.unsupported }
        var refs: [EventHotKeyRef] = []
        defer { refs.forEach { _ = UnregisterEventHotKey($0) };RemoveEventHandler(handler) }
        let base = UInt32(cmdKey | controlKey | optionKey)
        var selected: UInt16?
        for key: UInt16 in [111,103,109] {
            var pair: [EventHotKeyRef] = []
            for id: UInt32 in [1,2] {
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(UInt32(key),base | (id == 2 ? UInt32(shiftKey) : 0),EventHotKeyID(signature: signature,id: id),GetEventDispatcherTarget(),0,&ref)
                if status == noErr,let ref { pair.append(ref) }
            }
            if pair.count == 2 { selected = key;refs = pair;break }
            pair.forEach { _ = UnregisterEventHotKey($0) }
        }
        guard let key = selected else { throw WindowCatalogError.unsupported }
        for reverse in [false,true] {
            let source = CGEventSource(stateID: .privateState)
            for down in [true,false] {
                guard let event = CGEvent(keyboardEventSource: source,virtualKey: key,keyDown: down) else { throw WindowCatalogError.unsupported }
                event.flags = down ? (reverse ? [.maskCommand,.maskControl,.maskAlternate,.maskShift] : [.maskCommand,.maskControl,.maskAlternate]) : []
                event.setIntegerValueField(.eventSourceUserData,value: marker)
                event.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        checks["carbonReceivesForwardAndReversePressed"] = counter.pressed == [1,2]
        checks["carbonReceivesForwardAndReverseReleased"] = counter.released == [1,2]
        checks["carbonKeepsOwnedFixtureForeground"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID
        let after = SecureKeyboardInputStatus.read()
        checks["carbonDoesNotChangeSecureInput"] = before == after
        checks["carbonDoesNotChangeSymbolicKeys"] = nativeBefore != nil && nativeBefore == SwitcherNativeKeyGuard.currentState()
        checks["carbonGeneratedModifiersAreReleased"] = CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]).isEmpty
        return (checks,["input":"marked-generated-HID-events-to-registered-Carbon-hotkeys","pressed":counter.pressed,"released":counter.released,
            "keyCode":key,"secureInputEnabled":before.enabled,"secureInputOwnerPID":before.processID ?? 0,
            "nativeSettingsChanged":false,"eventTapInstalled":false,"physicalKeyboardVerified":false])
    }
}
#endif

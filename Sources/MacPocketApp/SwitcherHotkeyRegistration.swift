import AppKit
@preconcurrency import Carbon
import MacPocketCore

@MainActor protocol SwitcherNativeKeyOwning: AnyObject {
    var isActive: Bool { get }
    var isRunning: Bool { get }
    func pulse() -> Bool
    @discardableResult func stop() -> Bool
}

extension SwitcherNativeKeyLease: SwitcherNativeKeyOwning {}

/// The OS boundary is injectable so registration rollback can be exercised without taking keys
/// from another application. The controller retains the production registration policy.
@MainActor struct SwitcherHotkeyRegistration {
    var register: (UInt16,UInt32,EventHotKeyID) -> (status: OSStatus,reference: EventHotKeyRef?)
    var unregister: (EventHotKeyRef) -> Void
    var acquireNative: () throws -> any SwitcherNativeKeyOwning

    static var system: Self {
        .init(register: { key,flags,id in
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key),flags,id,GetEventDispatcherTarget(),0,&reference)
            return (status,reference)
        },unregister: { _ = UnregisterEventHotKey($0) },acquireNative: {
            guard let executable = Bundle.main.executableURL else { throw SwitcherNativeKeyError.unavailable }
            return try SwitcherNativeKeyLease.acquire(executable: executable)
        })
    }
}

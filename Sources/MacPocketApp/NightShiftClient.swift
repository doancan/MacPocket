import Darwin
import Foundation
import MacPocketCore
import ObjectiveC

/// Drives macOS Night Shift through the private CoreBrightness `CBBlueLightClient` class.
///
/// There is no public API for Night Shift, so the framework is loaded at runtime and each method
/// is called through its implementation pointer. If the class or any selector is missing the
/// client reports itself unavailable and every call is a no-op.
final class NightShiftClient: NightShiftControlling {
    private typealias SetBool = @convention(c) (AnyObject, Selector, Bool) -> Bool
    private typealias SetStrength = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
    private typealias GetStrength = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
    private typealias SetMode = @convention(c) (AnyObject, Selector, Int32) -> Bool
    private typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool

    private struct Bindings {
        let client: NSObject
        let setEnabled: SetBool
        let setStrength: SetStrength
        let getStrength: GetStrength
        let setMode: SetMode
        let getStatus: GetStatus
    }

    private static let setEnabledSelector = NSSelectorFromString("setEnabled:")
    private static let setStrengthSelector = NSSelectorFromString("setStrength:commit:")
    private static let getStrengthSelector = NSSelectorFromString("getStrength:")
    private static let setModeSelector = NSSelectorFromString("setMode:")
    private static let getStatusSelector = NSSelectorFromString("getBlueLightStatus:")

    /// `getBlueLightStatus:` fills `{ BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode;
    /// schedule; unsigned long long disableFlags; BOOL available; }` (40 bytes on arm64); the buffer
    /// is oversized so a grown struct cannot overrun it.
    private static let statusBufferSize = 64
    private static let enabledOffset = 1
    private static let modeOffset = 4

    private let bindings: Bindings?

    init() {
        bindings = Self.bind()
    }

    var isAvailable: Bool { bindings != nil }

    func snapshot() -> NightShiftState? {
        guard let b = bindings else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.statusBufferSize, alignment: 16)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: Self.statusBufferSize)
        guard b.getStatus(b.client, Self.getStatusSelector, buffer) else { return nil }
        var strength: Float = 0
        guard b.getStrength(b.client, Self.getStrengthSelector, &strength) else { return nil }
        let enabled = buffer.load(fromByteOffset: Self.enabledOffset, as: UInt8.self) != 0
        let mode = Int(buffer.load(fromByteOffset: Self.modeOffset, as: Int32.self))
        return NightShiftState(enabled: enabled, strength: Double(min(max(strength, 0), 1)), mode: (0...2).contains(mode) ? mode : 0)
    }

    func apply(enabled: Bool, strength: Double) {
        guard let b = bindings else { return }
        // Mode 0 switches off the macOS schedule so it does not override MacPocket.
        _ = b.setMode(b.client, Self.setModeSelector, 0)
        _ = b.setStrength(b.client, Self.setStrengthSelector, Float(min(max(strength, 0), 1)), true)
        _ = b.setEnabled(b.client, Self.setEnabledSelector, enabled)
    }

    func restore(_ state: NightShiftState) {
        guard let b = bindings else { return }
        _ = b.setStrength(b.client, Self.setStrengthSelector, Float(min(max(state.strength, 0), 1)), true)
        _ = b.setEnabled(b.client, Self.setEnabledSelector, state.enabled)
        _ = b.setMode(b.client, Self.setModeSelector, Int32(state.mode))
    }

    private static func bind() -> Bindings? {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        func implementation(_ selector: Selector) -> IMP? {
            class_getInstanceMethod(type, selector).map(method_getImplementation)
        }
        guard let setEnabled = implementation(setEnabledSelector),
              let setStrength = implementation(setStrengthSelector),
              let getStrength = implementation(getStrengthSelector),
              let setMode = implementation(setModeSelector),
              let getStatus = implementation(getStatusSelector) else { return nil }
        return Bindings(client: type.init(),
                        setEnabled: unsafeBitCast(setEnabled, to: SetBool.self),
                        setStrength: unsafeBitCast(setStrength, to: SetStrength.self),
                        getStrength: unsafeBitCast(getStrength, to: GetStrength.self),
                        setMode: unsafeBitCast(setMode, to: SetMode.self),
                        getStatus: unsafeBitCast(getStatus, to: GetStatus.self))
    }
}

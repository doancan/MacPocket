import AppKit
import Darwin

/// Three- or four-finger horizontal swipes drive the window switcher.
///
/// macOS has no public API for raw multi-finger trackpad input, so this loads the private
/// MultitouchSupport framework at runtime (as AltTab does). If the framework or a symbol is missing,
/// the feature reports itself unavailable instead of failing. Opt-in; off by default because macOS
/// uses three/four-finger swipes for Spaces unless the user changes that in Trackpad settings.
@MainActor
final class TrackpadSwipeMonitor {
    static let shared = TrackpadSwipeMonitor()

    private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void

    private struct Symbols {
        let createList: CreateList
        let register: Register
        let unregister: Register
        let start: Start
        let stop: Stop
    }

    private let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else { return nil }
        return Symbols(createList: unsafeBitCast(createList, to: CreateList.self),
                       register: unsafeBitCast(register, to: Register.self),
                       unregister: unsafeBitCast(unregister, to: Register.self),
                       start: unsafeBitCast(start, to: Start.self),
                       stop: unsafeBitCast(stop, to: Stop.self))
    }()

    private var devices: [UnsafeMutableRawPointer] = []
    var isAvailable: Bool { symbols != nil }
    var isRunning: Bool { !devices.isEmpty }

    /// Starts listening with the given finger count (3 or 4); 0 stops.
    func configure(fingers: Int) {
        stop()
        guard fingers == 3 || fingers == 4, let symbols,
              let list = symbols.createList()?.takeUnretainedValue() else { return }
        SwipeTracker.shared.reset(fingers: fingers)
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            symbols.register(device, swipeCallback)
            symbols.start(device, 0)
            devices.append(device)
        }
    }

    func stop() {
        guard let symbols else { return }
        for device in devices {
            symbols.unregister(device, swipeCallback)
            symbols.stop(device)
        }
        devices = []
    }
}

/// Runs on MultitouchSupport's thread; only plain values cross to the main actor.
private let swipeCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32 = { _, touches, count, _, _ in
    SwipeTracker.shared.process(touches: touches, count: Int(count))
    return 0
}

private final class SwipeTracker: @unchecked Sendable {
    static let shared = SwipeTracker()
    /// MTTouch layout: 96-byte stride, state Int32 at 20, normalized x Float at 32.
    private static let stride = 96
    private static let stateOffset = 20
    private static let xOffset = 32
    /// Normalized horizontal travel per switcher step.
    private static let threshold: Float = 0.07

    private let lock = NSLock()
    private var fingers = 3
    private var tracking = false
    private var anchorX: Float = 0
    private var steps = 0

    func reset(fingers: Int) {
        lock.lock(); self.fingers = fingers; tracking = false; steps = 0; lock.unlock()
    }

    func process(touches: UnsafeMutableRawPointer?, count: Int) {
        guard let touches else { return }
        var xs: [Float] = []
        for index in 0..<min(count, 10) {
            let base = touches + index * Self.stride
            let state = base.load(fromByteOffset: Self.stateOffset, as: Int32.self)
            // 4 = make touch, 5 = touching.
            guard state == 4 || state == 5 else { continue }
            xs.append(base.load(fromByteOffset: Self.xOffset, as: Float.self))
        }
        var events: [Bool?] = [] // true/false = step backwards/forwards, nil = ended
        lock.lock()
        if xs.count == fingers {
            let x = xs.reduce(0, +) / Float(xs.count)
            if !tracking { tracking = true; anchorX = x; steps = 0 }
            while x - anchorX > Self.threshold { anchorX += Self.threshold; steps += 1; events.append(false) }
            while anchorX - x > Self.threshold { anchorX -= Self.threshold; steps += 1; events.append(true) }
        } else if tracking, xs.count < fingers {
            tracking = false
            if steps > 0 { events.append(nil) }
        }
        lock.unlock()
        guard !events.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for event in events {
                    if let backwards = event { WindowSwitcherHotkeyController.shared.gestureStep(backwards: backwards) }
                    else { WindowSwitcherHotkeyController.shared.gestureEnded() }
                }
            }
        }
    }
}

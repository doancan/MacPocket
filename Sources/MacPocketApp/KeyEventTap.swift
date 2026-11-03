import CoreGraphics
import Foundation

/// A session event tap for key and media-key events on its own thread. It sees every key press, so `filter` runs on
/// the tap thread and must never wait for the main thread: it returns true to let an event through and false to
/// swallow it. A tap macOS disables for being slow is re-enabled.
final class KeyEventTap: @unchecked Sendable {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let filter: @Sendable (CGEventType, CGEvent) -> Bool

    /// Nil when the tap cannot be created (no Accessibility permission).
    init?(name: String, filter: @escaping @Sendable (CGEventType, CGEvent) -> Bool) {
        self.filter = filter
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << 14)) // 14: NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyEventTap>.fromOpaque(context).takeUnretainedValue()
            return tap.handle(type, event) ? Unmanaged.passUnretained(event) : nil
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        port = created
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let port = lock.withLock({ self.port }) else { ready.signal(); return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            lock.withLock { runLoop = CFRunLoopGetCurrent() }
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    deinit { stop() }

    func stop() {
        let (port, runLoop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            defer { self.port = nil; self.runLoop = nil }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port) // otherwise the disabled tap stays registered and a later one is added beside it
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = lock.withLock({ port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return true
        }
        return filter(type, event)
    }
}

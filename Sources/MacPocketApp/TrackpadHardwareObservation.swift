import AppKit
import IOKit

/// Registry notifications are delivered on the main run loop, alongside device reconfiguration.
/// Keeping the iterator drained rearms each notification; no device polling runs while idle.
@MainActor final class TrackpadHardwareObservation {
    private var port: IONotificationPortRef?
    private var source: CFRunLoopSource?
    private var iterators: [io_iterator_t] = []
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var pending: Timer?
    private var forceRestart = false
    private var sleeping = false
    private var receive: (@MainActor (Bool) -> Void)?
    private var willSleep: (@MainActor () -> Void)?

    @discardableResult func start(willSleep: @escaping @MainActor () -> Void = {},receive: @escaping @MainActor (Bool) -> Void) -> Bool {
        stop()
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        guard let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            IONotificationPortDestroy(port);return false
        }
        self.port = port;self.source = source;self.receive = receive;self.willSleep = willSleep
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        for notification in [kIOFirstMatchNotification,kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let status = IOServiceAddMatchingNotification(port,notification,IOServiceMatching("AppleMultitouchDevice"),
                { context,iterator in
                    MainActor.assumeIsolated {
                        TrackpadHardwareObservation.drain(iterator)
                        guard let context else { return }
                        Unmanaged<TrackpadHardwareObservation>.fromOpaque(context).takeUnretainedValue().schedule(force: false)
                    }
                },Unmanaged.passUnretained(self).toOpaque(),&iterator)
            guard status == KERN_SUCCESS else { stop();return false }
            iterators.append(iterator)
            Self.drain(iterator)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,object: nil,queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeping = false;self?.schedule(force: true) }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,object: nil,queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true;self.pending?.invalidate();self.pending = nil;self.forceRestart = false
                self.willSleep?()
            }
        }
        return true
    }

    private static func drain(_ iterator: io_iterator_t) {
        while true {
            let device = IOIteratorNext(iterator)
            guard device != 0 else { return }
            IOObjectRelease(device)
        }
    }

    private func schedule(force: Bool) {
        guard receive != nil,!sleeping else { return }
        forceRestart = forceRestart || force
        pending?.invalidate()
        let timer = Timer(timeInterval: 0.15,repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let force = self.forceRestart
                self.pending = nil;self.forceRestart = false
                self.receive?(force)
            }
        }
        pending = timer;RunLoop.main.add(timer,forMode: .common)
    }

    func stop() {
        pending?.invalidate();pending = nil;forceRestart = false;sleeping = false;receive = nil;willSleep = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        wakeObserver = nil;sleepObserver = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        source = nil
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    isolated deinit { stop() }

#if DEBUG
    var diagnosticResources: [String:Int] {
        ["port":port == nil ? 0 : 1,"source":source == nil ? 0 : 1,"iterators":iterators.count,
         "wakeObserver":wakeObserver == nil ? 0 : 1,"sleepObserver":sleepObserver == nil ? 0 : 1,"pending":pending == nil ? 0 : 1]
    }
#endif
}

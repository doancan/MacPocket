import AppKit
import Darwin
import MacPocketCore

@MainActor protocol SwitcherGestureMonitoring: AnyObject {
    var isAvailable: Bool { get }
    var isRunning: Bool { get }
    func configure(options: SwitcherGestureOptions,receive: @escaping @MainActor (SwitcherGestureEvent) -> Void)
    func stop()
}

/// Optional raw multi-touch input. Private framework symbols are loaded at runtime and checked;
/// absence disables this adapter. It observes contacts, without suppressing macOS Space gestures.
@MainActor final class TrackpadSwipeMonitor: SwitcherGestureMonitoring {
    static let shared = TrackpadSwipeMonitor()
    private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt, Double, UInt) -> Void
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
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",RTLD_NOW) else { return nil }
        guard let createList = dlsym(handle,"MTDeviceCreateList"),let register = dlsym(handle,"MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle,"MTUnregisterContactFrameCallback"),let start = dlsym(handle,"MTDeviceStart"),let stop = dlsym(handle,"MTDeviceStop") else {
            dlclose(handle);return nil
        }
        return Symbols(createList: unsafeBitCast(createList,to: CreateList.self),register: unsafeBitCast(register,to: Register.self),
                       unregister: unsafeBitCast(unregister,to: Register.self),start: unsafeBitCast(start,to: Start.self),stop: unsafeBitCast(stop,to: Stop.self))
    }()
    private var deviceList: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []
    private let hardwareObservation = TrackpadHardwareObservation()
    private var options: SwitcherGestureOptions?
    private var receiver: (@MainActor (SwitcherGestureEvent) -> Void)?
    var isAvailable: Bool { symbols != nil }
    var isRunning: Bool { !devices.isEmpty }
    func configure(options: SwitcherGestureOptions,receive: @escaping @MainActor (SwitcherGestureEvent) -> Void) {
        stop()
        guard options.enabled,symbols != nil else { return }
        self.options = options;receiver = receive
        hardwareObservation.start(willSleep: { [weak self] in
            TrackpadGestureRelay.shared.cancelForHardwareChange()
            TrackpadGestureRelay.shared.stop()
            self?.stopDevices()
        }) { [weak self] force in self?.refreshDevices(force: force) }
        refreshDevices(force: true)
    }
    func stop() {
        // Invalidate queued main-thread deliveries before unregistering. A late callback cannot reopen UI.
        hardwareObservation.stop();options = nil;receiver = nil
        TrackpadGestureRelay.shared.stop()
        stopDevices()
    }
    private func stopDevices() {
        if let symbols { for device in devices { symbols.unregister(device,swipeCallback);symbols.stop(device) } }
        devices = [];deviceList = nil
    }
    private func refreshDevices(force: Bool) {
        guard let symbols,let options,let receiver else { return }
        let list = symbols.createList()?.takeRetainedValue()
        let next = list.map { list in
            (0..<CFArrayGetCount(list)).compactMap { CFArrayGetValueAtIndex(list,$0).map { UnsafeMutableRawPointer(mutating: $0) } }
        } ?? []
        let keys = Set(next.map { UInt64(UInt(bitPattern: $0)) })
        guard force || keys != Set(devices.map { UInt64(UInt(bitPattern: $0)) }) else { return }
        // Losing hardware cancels an owned HUD; it must never look like an intentional finger lift.
        TrackpadGestureRelay.shared.cancelForHardwareChange()
        stopDevices()
        deviceList = list;devices = next
        TrackpadGestureRelay.shared.configure(options: options,devices: keys,receive: receiver)
        for device in devices { symbols.register(device,swipeCallback);symbols.start(device,0) }
    }
}

private let swipeCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt, Double, UInt) -> Void = { device,touches,count,_,_ in
    guard let device else { return }
    TrackpadGestureRelay.shared.process(device: UInt64(UInt(bitPattern: device)),contacts: TrackpadContactDecoder.decode(touches: touches,count: Int(clamping: count)))
}

/// Private MTTouch ABI: 96-byte records, path identity at 16, state at 20, normalized XY at 32/36.
/// Stage 3 makes contact, 4 stays touching; stage 5 is already breaking contact.
/// This bounded, synchronous copy never sends raw contact memory to the main queue.
enum TrackpadContactDecoder {
    static func decode(touches: UnsafeRawPointer?,count: Int) -> [SwitcherGestureContact]? {
        guard (0...10).contains(count) else { return nil }
        if count == 0 { return [] }
        guard let touches else { return nil }
        var result: [SwitcherGestureContact] = []
        for index in 0..<count {
            let base = touches + index * 96,state = base.loadUnaligned(fromByteOffset: 20,as: Int32.self)
            guard (0...7).contains(state) else { return nil }
            guard state == 3 || state == 4 else { continue }
            result.append(.init(id: base.loadUnaligned(fromByteOffset: 16,as: Int32.self),
                                x: Double(base.loadUnaligned(fromByteOffset: 32,as: Float.self)),
                                y: Double(base.loadUnaligned(fromByteOffset: 36,as: Float.self))))
        }
        return result
    }
}

/// One lock owns the recognizer and enqueue order. Only copied values cross threads. Receiver access
/// is main-actor isolated; a generation check drops work queued before stop/reconfiguration.
final class TrackpadGestureRelay: @unchecked Sendable {
    static let shared = TrackpadGestureRelay()
    private let lock = NSLock()
    private var generation = UUID()
    private var devices: Set<UInt64> = []
    private var tracker = SwitcherGestureTracker(options: .init())
    @MainActor private var receiver: (@MainActor (SwitcherGestureEvent) -> Void)?
    @MainActor private var deliveredGestureID: UUID?
    @MainActor func configure(options: SwitcherGestureOptions,devices: Set<UInt64>,receive: @escaping @MainActor (SwitcherGestureEvent) -> Void) {
        lock.lock();generation = UUID();self.devices = devices;tracker = .init(options: options);lock.unlock()
        deliveredGestureID = nil;receiver = receive
    }
    @MainActor func stop() {
        lock.lock();generation = UUID();devices = [];tracker = .init(options: .init());lock.unlock()
        receiver = nil;deliveredGestureID = nil
    }
    @MainActor func cancelForHardwareChange() {
        lock.lock()
        generation = UUID()
        for device in devices { _ = tracker.process(device: device,contacts: nil) }
        lock.unlock()
        let id = deliveredGestureID;deliveredGestureID = nil
        if let id { receiver?(.cancelled(id: id)) }
    }
    func process(device: UInt64,contacts: [SwitcherGestureContact]?) {
        lock.lock();defer { lock.unlock() }
        guard devices.contains(device) else { return }
        let events = tracker.process(device: device,contacts: contacts),epoch = generation
        guard !events.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock();let current = self.generation == epoch;self.lock.unlock()
            guard current else { return }
            for event in events {
                switch event {
                case .step(let id,_,_,_): self.deliveredGestureID = id
                case .ended(let id),.cancelled(let id):
                    if self.deliveredGestureID == id { self.deliveredGestureID = nil }
                }
                self.receiver?(event)
            }
        }
    }
}

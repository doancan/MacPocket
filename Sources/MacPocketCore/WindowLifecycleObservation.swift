import AppKit
import Darwin
import Foundation

public struct WindowLifecycleProvider: WindowLifecycleProviding {
    public init() {}
    public func snapshot(admitting identities: [WindowLifecycleIdentity]) async -> WindowLifecycleSnapshot {
        await WindowLifecycleService.shared.snapshot(admitting: identities)
    }
}

@MainActor public protocol WindowLifecycleObserving: AnyObject {
    func start()
    func stop()
}

/// Shared event observation for the HUD and Tools. Starting never requests TCC permission.
@MainActor public final class WindowLifecycleObservation: WindowLifecycleObserving {
    public static let didChangeNotification = Notification.Name("MacPocket.windowLifecycleDidChange")
    public static let snapshotKey = "snapshot"
    private let owner = UUID()
    public init() {}
    public func start() { WindowLifecycleService.shared.start(owner) }
    public func stop() { WindowLifecycleService.shared.stop(owner) }
    deinit {
        let owner = owner
        Task { @MainActor in WindowLifecycleService.shared.stop(owner) }
    }
#if DEBUG
    public static var diagnosticResources: [String: Int] { WindowLifecycleService.shared.diagnosticResources }
    public static func automaticallyResolvedForAudit(_ windowID: UInt32) -> Bool { WindowLifecycleService.shared.automaticallyResolved.contains(windowID) }
    public static func resolutionForAudit(_ windowID: UInt32) -> [String: String] { WindowLifecycleService.shared.resolutionTrace[windowID] ?? [:] }
#endif
}

typealias WindowLifecycleCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, UInt32) -> Void
private func receiveWindowLifecycle(_ event: UInt32, _ payload: UnsafeMutableRawPointer?, _ length: Int,
                                    _ context: UnsafeMutableRawPointer?, _ connection: UInt32) {
    guard let context,
          let message = WindowLifecycleMessage.decode(event: event, data: payload, length: length) else { return }
    Unmanaged<WindowLifecycleIngress>.fromOpaque(context).takeUnretainedValue().receive(message, connection: connection)
}

/// The C provider does not document callback quiescence after unregister. Retired contexts keep
/// only an inactive lock/timeline shell for process lifetime; late callbacks cannot enter a new
/// registration's history. No payload pointer or AppKit reference crosses the callback boundary.
final class WindowLifecycleIngress: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: UInt32
    private var active = false
    private var notificationPending = false
    private var timeline = WindowLifecycleTimeline()
    private var delivery: (@MainActor @Sendable (WindowLifecycleSnapshot) -> Void)?
    init(connection: UInt32) { self.connection = connection }
    func activate(delivery: @escaping @MainActor @Sendable (WindowLifecycleSnapshot) -> Void) {
        lock.withLock { active = true; self.delivery = delivery }
    }
    func deactivate() {
        lock.withLock { active = false; delivery = nil; notificationPending = false; timeline = .init() }
    }
    func receive(_ message: WindowLifecycleMessage, connection: UInt32) {
        let schedule = lock.withLock {
            guard active, self.connection == connection else { return false }
            timeline.record(message, at: Date())
            guard !notificationPending else { return false }
            notificationPending = true
            return true
        }
        guard schedule else { return }
        DispatchQueue.main.async { [self] in
            let pending = lock.withLock { () -> (WindowLifecycleSnapshot, (@MainActor @Sendable (WindowLifecycleSnapshot) -> Void)?) in
                notificationPending = false
                return (timeline.snapshot, active ? delivery : nil)
            }
            pending.1?(pending.0)
        }
    }
    func snapshot(admitting identities: [WindowLifecycleIdentity]) -> WindowLifecycleSnapshot {
        lock.withLock {
            guard active else { return .unavailable }
            timeline.admit(identities)
            return timeline.snapshot
        }
    }
}

@MainActor protocol WindowLifecycleBackend: AnyObject {
    var connection: UInt32 { get }
    func register(event: UInt32, callback: WindowLifecycleCallback, context: UnsafeMutableRawPointer) -> Bool
    func remove(event: UInt32, callback: WindowLifecycleCallback, context: UnsafeMutableRawPointer) -> Bool
    func request(windowIDs: [UInt32]) -> Bool
}

/// Optional ABI adapter; all mutations here concern our connection's subscriptions only.
@MainActor private final class WindowLifecycleFunctions: WindowLifecycleBackend {
    typealias MainConnection = @convention(c) () -> UInt32
    typealias Registration = @convention(c) (UInt32, WindowLifecycleCallback, UInt32, UnsafeMutableRawPointer?) -> Int32
    typealias Request = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, Int32) -> Int32
    // The shared backend and its library deliberately live for the process, including late callbacks.
    static let shared = load()
    let connection: UInt32
    private let library: UnsafeMutableRawPointer
    private let add: Registration, remove: Registration
    private let subscribe: Request
    private init(library: UnsafeMutableRawPointer, connection: UInt32, add: Registration, remove: Registration, subscribe: Request) {
        self.library = library
        self.connection = connection
        self.add = add
        self.remove = remove
        self.subscribe = subscribe
    }
    private static func load() -> WindowLifecycleFunctions? {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let main = dlsym(library, "CGSMainConnectionID"), let add = dlsym(library, "SLSRegisterConnectionNotifyProc"),
              let remove = dlsym(library, "SLSRemoveConnectionNotifyProc"), let request = dlsym(library, "SLSRequestNotificationsForWindows") else {
            dlclose(library)
            return nil
        }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        guard connection != 0 else { dlclose(library); return nil }
        return .init(library: library, connection: connection, add: unsafeBitCast(add, to: Registration.self),
                     remove: unsafeBitCast(remove, to: Registration.self), subscribe: unsafeBitCast(request, to: Request.self))
    }
    func register(event: UInt32, callback: WindowLifecycleCallback, context: UnsafeMutableRawPointer) -> Bool {
        add(connection, callback, event, context) == 0
    }
    func remove(event: UInt32, callback: WindowLifecycleCallback, context: UnsafeMutableRawPointer) -> Bool {
        remove(connection, callback, event, context) == 0
    }
    func request(windowIDs: [UInt32]) -> Bool {
        guard windowIDs.count <= Int(Int32.max) else { return false }
        var ids = windowIDs
        return ids.withUnsafeMutableBufferPointer { subscribe(connection, $0.baseAddress, Int32($0.count)) == 0 }
    }
}

@MainActor public final class WindowLifecycleService: WindowLifecycleProviding {
    public static let shared = WindowLifecycleService()
    // Immutable per-registration contexts make late/stopped callbacks safe. They retain no history
    // or handler after deactivate; this small ABI safety allocation is not an active subscription.
    private static var retiredContexts: [WindowLifecycleIngress] = []
    private var backend: (any WindowLifecycleBackend)?
    private let loadsBackend: Bool
    private let isProcessCurrent: @MainActor (WindowLifecycleIdentity) -> Bool
    private var owners = Set<UUID>()
    private var ingress: WindowLifecycleIngress?
    private var registered = Set<UInt32>()
    private var watched: [UInt32: WindowLifecycleIdentity] = [:]
    private var notifiedRevision: UInt64 = 0
    private var failed = false
#if DEBUG
    fileprivate var automaticallyResolved = Set<UInt32>()
    fileprivate var resolutionTrace: [UInt32: [String: String]] = [:]
#endif
    private init() { backend = nil; loadsBackend = true; isProcessCurrent = Self.currentProcess }
    init(backend: (any WindowLifecycleBackend)?, isProcessCurrent: @escaping @MainActor (WindowLifecycleIdentity) -> Bool = WindowLifecycleService.currentProcess) {
        self.backend = backend
        loadsBackend = false
        self.isProcessCurrent = isProcessCurrent
    }
    static func currentProcess(_ identity: WindowLifecycleIdentity) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: identity.processID), !app.isTerminated else { return false }
        return CatalogWindowIdentity.matchesProcessLaunch(expected: identity.launchedAt,
            actual: CatalogWindowIdentity.processLaunchDate(pid: identity.processID, applicationDate: app.launchDate))
    }

    func start(_ owner: UUID) {
        guard owners.insert(owner).inserted, owners.count == 1, !failed else { return }
        if loadsBackend, backend == nil { backend = WindowLifecycleFunctions.shared }
        guard let backend else { return }
        let sink = WindowLifecycleIngress(connection: backend.connection)
        ingress = sink
        notifiedRevision = 0
        let context = Unmanaged.passUnretained(sink).toOpaque()
        for event in [WindowLifecycleEvent.created, .destroyed] {
            guard backend.register(event: event.rawValue, callback: receiveWindowLifecycle, context: context) else {
                failed = true
                tearDown()
                return
            }
            registered.insert(event.rawValue)
        }
        sink.activate { [weak self, weak sink] snapshot in
            guard let self, let sink, self.ingress === sink, !self.owners.isEmpty else { return }
            self.deliver(snapshot)
        }
    }

    private func deliver(_ value: WindowLifecycleSnapshot) {
        let changed = value.entries.filter { $0.value.revision > notifiedRevision }
#if DEBUG
        for (id, entry) in changed {
            resolutionTrace[id] = ["event": entry.destroyed ? "destroyed" : (entry.creation != nil ? "created" : "ownerChanged"), "identityBound": String(entry.identity != nil)]
        }
        if resolutionTrace.count > 512 { resolutionTrace = resolutionTrace.filter { value.entries[$0.key]?.identity != nil } }
#endif
        notifiedRevision = value.revision
        var relevant = changed.contains { id, entry in
            entry.identity.map { $0.processID != getpid() } == true
                || (entry.destroyed && watched[id].map { $0.processID != getpid() } == true)
        }
        let createdIDs = changed.filter { !$0.value.destroyed && $0.value.identity == nil }.keys
        var newFacts: [WindowLifecycleIdentity] = []
        if !createdIDs.isEmpty {
            // Resolve only the named newborn surfaces, outside the C callback. No AX reads and
            // no catalog scan run while the HUD is closed. A window gone before resolution
            // remains unknown. Own panels/helpers must not invalidate the switcher opening.
            // This CoreGraphics API expects raw CGWindowID values in a CFArray with no element
            // callbacks, as returned by CGWindowListCreate. An NSArray of NSNumber is different.
            var pointers = createdIDs.map { UnsafeRawPointer(bitPattern: Int($0)) }
            let ids = pointers.withUnsafeMutableBufferPointer { CFArrayCreate(nil, $0.baseAddress, $0.count, nil) }
            let descriptions = ids.flatMap { CGWindowListCreateDescriptionFromArray($0) }
            let rows = descriptions as? [[String: Any]] ?? []
#if DEBUG
            for id in createdIDs { resolutionTrace[id]?["descriptionCount"] = String(rows.count) }
            for row in rows {
                guard let id = row[kCGWindowNumber as String] as? UInt32 else { continue }
                let pid = row[kCGWindowOwnerPID as String] as? Int32 ?? 0
                let app = NSRunningApplication(processIdentifier: pid)
                resolutionTrace[id]?["pid"] = String(pid)
                resolutionTrace[id]?["layer"] = String(describing: row[kCGWindowLayer as String])
                resolutionTrace[id]?["bounds"] = String(describing: row[kCGWindowBounds as String])
                resolutionTrace[id]?["application"] = String(app != nil)
                resolutionTrace[id]?["policy"] = String(describing: app?.activationPolicy)
            }
#endif
            for row in rows {
                // Creation precedes AppKit's geometry transaction: legitimate newborns can
                // still have a zero frame. Watch the verified owner now; only the ordinary
                // AX/WindowServer catalog may later admit a user-visible switch target.
                guard let id = row[kCGWindowNumber as String] as? UInt32,
                      let pid = row[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                      row[kCGWindowLayer as String] as? Int == 0,
                      let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, !app.isTerminated,
                      let launch = CatalogWindowIdentity.processLaunchDate(pid: pid, applicationDate: app.launchDate) else { continue }
                newFacts.append(.init(windowID: id, processID: pid, launchedAt: launch))
#if DEBUG
                automaticallyResolved.insert(id)
#endif
            }
        }
        relevant = relevant || !newFacts.isEmpty
        // Subscribe immediately: a newborn window can close before the next user-triggered
        // catalog scan. Otherwise its 804 could be lost, even though 811 was delivered.
        let updated = snapshot(admitting: newFacts)
        guard relevant else { return }
        NotificationCenter.default.post(name: WindowLifecycleObservation.didChangeNotification, object: self,
            userInfo: [WindowLifecycleObservation.snapshotKey: updated])
    }
    func stop(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        tearDown()
    }
    private func tearDown() {
        guard let sink = ingress else { return }
        sink.deactivate()
        if let backend {
            let context = Unmanaged.passUnretained(sink).toOpaque()
            for event in registered {
                if !backend.remove(event: event, callback: receiveWindowLifecycle, context: context) { failed = true }
            }
            if !backend.request(windowIDs: []) { failed = true }
        }
        registered.removeAll()
        watched.removeAll()
        ingress = nil
#if DEBUG
        automaticallyResolved.removeAll()
        resolutionTrace.removeAll()
#endif
        Self.retiredContexts.append(sink)
    }
    public func snapshot(admitting identities: [WindowLifecycleIdentity] = []) -> WindowLifecycleSnapshot {
        guard let sink = ingress, !owners.isEmpty, !failed, let backend else { return .unavailable }
        // Disappearance from one Space/AX scan is not destruction. Keep prior watches, but
        // prune dead/reused processes using the same launch identity used by catalog actions.
        var processValidity: [String: Bool] = [:]
        func valid(_ identity: WindowLifecycleIdentity) -> Bool {
            let key = CatalogWindowIdentity.application(pid: identity.processID, launchedAt: identity.launchedAt)
            if let cached = processValidity[key] { return cached }
            let result = isProcessCurrent(identity)
            processValidity[key] = result
            return result
        }
        let admitted = identities.filter { $0.windowID > 0 && $0.processID > 0 && valid($0) }
        let value = sink.snapshot(admitting: admitted)
        var next = watched.filter { value.entries[$0.key]?.destroyed != true && valid($0.value) }
        for identity in admitted where value.entries[identity.windowID]?.destroyed != true {
            next[identity.windowID] = identity
        }
        // Do not silently drop old watches and retain their supposedly complete history.
        guard next.count <= 8_192 else { failed = true; tearDown(); return .unavailable }
        if next != watched {
            // This API replaces the subscription list; it does not append a delta.
            guard backend.request(windowIDs: next.keys.sorted()) else { failed = true; tearDown(); return .unavailable }
            watched = next
        }
        return sink.snapshot(admitting: admitted)
    }
#if DEBUG
    var diagnosticResources: [String: Int] {
        ["owners": owners.count, "callbacks": registered.count, "watchedWindows": watched.count,
         "activeIngress": ingress == nil ? 0 : 1, "failed": failed ? 1 : 0]
    }
#endif
}

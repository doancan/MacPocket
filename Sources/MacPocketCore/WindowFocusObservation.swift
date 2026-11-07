import AppKit
@preconcurrency import ApplicationServices
import Darwin
import Foundation

/// A lease on the shared, event-driven focused-window observation. No polling or permission prompt.
@MainActor
public protocol WindowFocusObserving: AnyObject {
    func start()
    func stop()
}

@MainActor
public final class WindowFocusObservation: WindowFocusObserving {
    private let owner = UUID()
    public init() {}
    public func start() { WindowFocusObservationCenter.shared.start(owner) }
    public func stop() { WindowFocusObservationCenter.shared.stop(owner) }
#if DEBUG
    public static var diagnosticResources: [String: Int] { WindowFocusObservationCenter.shared.diagnosticResources }
#endif
    deinit {
        let owner = owner
        Task { @MainActor in WindowFocusObservationCenter.shared.stop(owner) }
    }
}

enum CatalogWindowIdentity {
    /// libproc remains available when AppKit omits launchDate (for example Finder or Chrome).
    /// Prefer the same kernel timestamp on every read; switching between clock sources would
    /// spuriously expire a live target when AppKit's optional value appears or disappears.
    static func processLaunchDate(pid: Int32, applicationDate: Date?) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let kernel: Date?
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_start_tvsec > 0, info.pbi_start_tvusec < 1_000_000 {
            kernel = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
        } else { kernel = nil }
        return resolvedLaunchDate(kernel: kernel, application: applicationDate)
    }
    static func resolvedLaunchDate(kernel: Date?, application: Date?) -> Date? { kernel ?? application }
    static func matchesProcessLaunch(expected: Date?, actual: Date?) -> Bool {
        guard let expected, let actual else { return false }
        return expected == actual
    }
    static func application(pid: Int32, launchedAt: Date?) -> String { "\(pid)-\(launchedAt?.timeIntervalSince1970 ?? 0)" }
    static func window(pid: Int32, launchedAt: Date?, windowID: UInt32?, elementHash: UInt) -> String {
        let app = application(pid: pid, launchedAt: launchedAt)
        return windowID.map { "w-\(app)-\($0)" } ?? "window-\(app)-\(elementHash)"
    }
}

/// Pure event history. The launch date prevents PID reuse from inheriting another process's MRU.
struct WindowFocusTimeline {
    private struct Entry {
        let pid: Int32
        let launchedAt: Date
        let alias: String
        let time: Date
    }
    private var entries: [String: Entry] = [:]
    let capacity: Int
    init(capacity: Int = 4_096) { self.capacity = max(0, capacity) }
    var count: Int { entries.count }

    mutating func record(pid: Int32, launchedAt: Date?, windowID: UInt32?, elementHash: UInt, at time: Date) {
        guard pid > 0, let launchedAt, windowID != nil || elementHash != 0, capacity > 0 else { return }
        let key = CatalogWindowIdentity.window(pid: pid, launchedAt: launchedAt, windowID: windowID, elementHash: elementHash)
        guard entries[key].map({ $0.time <= time }) ?? true else { return }
        let alias = CatalogWindowIdentity.window(pid: pid, launchedAt: launchedAt, windowID: nil, elementHash: elementHash)
        entries[key] = Entry(pid: pid, launchedAt: launchedAt, alias: alias, time: time)
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.time < $1.value.time })?.key { entries.removeValue(forKey: oldest) }
    }

    mutating func remove(pid: Int32, launchedAt: Date?) {
        entries = entries.filter { $0.value.pid != pid || (launchedAt != nil && $0.value.launchedAt != launchedAt) }
    }
    mutating func clear() { entries.removeAll() }
    var timestamps: [String: Date] {
        var result: [String: Date] = [:]
        for (key, entry) in entries {
            result[key] = max(result[key] ?? .distantPast, entry.time)
            result[entry.alias] = max(result[entry.alias] ?? .distantPast, entry.time)
        }
        return result
    }
}

/// All AX messaging happens on this actor, away from the main run loop.
private actor WindowFocusSampleReader {
    struct Sample: Sendable { let windowID: UInt32?; let elementHash: UInt; let time: Date }
    func read(pid: Int32) -> Sample? {
        guard !Task.isCancelled else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let focused = unsafeDowncast(value, to: AXUIElement.self)
        guard let window = WindowFocusOwner.window(for: focused,processID: pid,io: AXWindowTabIO()) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.05)
        guard !Task.isCancelled else { return nil }
        return .init(windowID: WindowCatalog.windowID(of: window), elementHash: CFHash(window), time: Date())
    }
}

/// One AX observer for the foreground application, shared by the global HUD and Tools view.
/// Focus changes within an application arrive through AX; app changes use NSWorkspace.
@MainActor
final class WindowFocusObservationCenter {
    static let shared = WindowFocusObservationCenter()
    private var owners = Set<UUID>()
    private var notifications: [NSObjectProtocol] = []
    private var timeline = WindowFocusTimeline()
    private let reader = WindowFocusSampleReader()
    private var observer: AXObserver?
    private var activePID: Int32?
    private var activeLaunchDate: Date?
    private var generation = UUID()
    private var readTask: Task<Void, Never>?
    private var readWanted = false
    private var wasTrusted = false

#if DEBUG
    var diagnosticResources: [String: Int] {
        ["owners": owners.count, "workspaceObservers": notifications.count, "axObservers": observer == nil ? 0 : 1,
         "focusRecords": timeline.count, "readTasks": readTask == nil ? 0 : 1]
    }
#endif

    func start(_ owner: UUID) {
        guard owners.insert(owner).inserted, owners.count == 1 else { return }
        let center = NSWorkspace.shared.notificationCenter
        notifications.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.observeFrontmost() }
        })
        notifications.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                // A delayed termination notification must not erase a newly reused PID's history.
                guard NSRunningApplication(processIdentifier: pid)?.isTerminated != false else { return }
                self.timeline.remove(pid: pid, launchedAt: nil)
                if self.activePID == pid { self.detach() }
            }
        })
        observeFrontmost()
    }

    func stop(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        for token in notifications { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notifications.removeAll()
        detach(); timeline.clear()
    }

    /// Snapshot scans already run when the HUD opens. Recheck trust here so granting/revoking
    /// permission works without a new background polling loop or restarting MacPocket.
    func timestamps() -> [String: Date] {
        if !owners.isEmpty, AXIsProcessTrusted() != wasTrusted { observeFrontmost() }
        return timeline.timestamps
    }

    private func observeFrontmost() {
        detach()
        wasTrusted = AXIsProcessTrusted()
        guard !owners.isEmpty, wasTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid(), app.activationPolicy == .regular,
              let launch = CatalogWindowIdentity.processLaunchDate(pid: app.processIdentifier, applicationDate: app.launchDate) else { return }
        let pid = app.processIdentifier
        var created: AXObserver?
        guard AXObserverCreate(pid, { observed, _, _, context in
            guard let context else { return }
            // The source is installed only on the main run loop; the shared center outlives it.
            MainActor.assumeIsolated {
                let center = Unmanaged<WindowFocusObservationCenter>.fromOpaque(context).takeUnretainedValue()
                guard let current = center.observer, CFEqual(current, observed) else { return }
                center.requestRead()
            }
        }, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.05)
        guard AXObserverAddNotification(created, element, kAXFocusedWindowChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        observer = created; activePID = pid; activeLaunchDate = launch
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        requestRead()
    }

    private func requestRead() {
        readWanted = true
        guard readTask == nil, let pid = activePID, let launch = activeLaunchDate else { return }
        let session = generation
        readTask = Task { [weak self, reader] in
            while !Task.isCancelled {
                guard let self, session == self.generation else { return }
                self.readWanted = false
                let sample = await reader.read(pid: pid)
                guard !Task.isCancelled, session == self.generation else { return }
                if let sample, let app = NSWorkspace.shared.frontmostApplication,
                   app.processIdentifier == pid,
                   CatalogWindowIdentity.processLaunchDate(pid: pid, applicationDate: app.launchDate) == launch {
                    self.timeline.record(pid: pid, launchedAt: launch, windowID: sample.windowID, elementHash: sample.elementHash, at: sample.time)
                }
                if !self.readWanted { self.readTask = nil; return }
            }
        }
    }

    private func detach() {
        generation = UUID()
        readTask?.cancel(); readTask = nil; readWanted = false
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; activePID = nil; activeLaunchDate = nil
    }
}

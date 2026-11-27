import AppKit
import IOKit.ps
import MacPocketCore

/// Owns only the assertion UUID it acquired. Monitoring uses PocketModel's existing tick.
@MainActor final class AwakeAutomationService: ObservableObject {
    @Published var settings: AwakeAutomationSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            policy.reset()
            revision += 1
            startRetryAt = 0
            stopRetryAt = 0
            error = nil
            scheduleRefresh()
        }
    }
    @Published private(set) var status = AwakeAutomationStatus.disabled
    @Published private(set) var matching: Set<AwakeAutomationCondition> = []
    @Published private(set) var ownedSessionID: UUID?
    @Published private(set) var error: String?
    private let controller: any IdleSleepControlling
    private let defaults: UserDefaults
    private let environment: @MainActor () -> AwakeAutomationInput
    private let sessionChanged: @MainActor (AwakeSession?) -> Void
    private var policy = AwakeAutomationPolicy()
    private var revision = 0
    private var appliedSettings: AwakeAutomationSettings?
    private var reconciling = false
    private var refreshNeeded = false
    private var refreshTask: Task<Void, Never>?
    private var startRetryAt: TimeInterval = 0
    private var stopRetryAt: TimeInterval = 0

    init(controller: any IdleSleepControlling, defaults: UserDefaults = .standard,
         environment: @escaping @MainActor () -> AwakeAutomationInput = { AwakeAutomationService.currentInput() },
         sessionChanged: @escaping @MainActor (AwakeSession?) -> Void = { _ in }) {
        self.controller = controller
        self.defaults = defaults
        self.environment = environment
        self.sessionChanged = sessionChanged
        settings = AwakeAutomationSettings.load(from: defaults)
    }
    /// Also called before awaiting a manual controller operation, invalidating any in-flight automatic claim.
    func pauseForManualControl() { policy.pauseForManualControl(); revision += 1; startRetryAt = 0; stopRetryAt = 0; scheduleRefresh() }
    func resume() { policy.reset(); revision += 1; startRetryAt = 0; stopRetryAt = 0; error = nil; scheduleRefresh() }
    func refreshPreferencesAndReconcile() async {
        let saved = AwakeAutomationSettings.load(from: defaults)
        if saved != settings { settings = saved }
        await reconcile()
    }
    private func scheduleRefresh() {
        guard refreshTask == nil else { refreshNeeded = true; return }
        refreshTask = Task { [weak self] in
            await self?.reconcile()
            self?.refreshTask = nil
            if let self, self.refreshNeeded, !self.reconciling { self.refreshNeeded = false; self.scheduleRefresh() }
        }
    }
    func reconcile() async {
        guard !reconciling else { refreshNeeded = true; return }
        reconciling = true
        refreshNeeded = false
        defer {
            reconciling = false
            if refreshNeeded, refreshTask == nil { refreshNeeded = false; scheduleRefresh() }
        }
        guard settings.enabled || ownedSessionID != nil else {
            statusIfChanged(.disabled)
            if !matching.isEmpty { matching = [] }
            return
        }
        let generation = revision, snapshot = settings, context = environment()
        let current = await controller.status()
        guard generation == revision else { refreshNeeded = true; return }
        if let ownedSessionID, current?.id != ownedSessionID { self.ownedSessionID = nil; appliedSettings = nil }
        let manual = current?.active == true && current?.id != ownedSessionID
        let decision = policy.evaluate(snapshot, input: context, manualSession: manual)
        statusIfChanged(decision.status)
        if matching != decision.matching { matching = decision.matching }
        if let owned = ownedSessionID, (!decision.shouldHold || appliedSettings != snapshot) {
            guard context.uptime >= stopRetryAt else { return }
            do {
                _ = try await controller.stop(sessionID: owned)
                if ownedSessionID == owned { ownedSessionID = nil; appliedSettings = nil }
                error = nil
                stopRetryAt = 0
            } catch {
                self.error = error.localizedDescription
                stopRetryAt = context.uptime + 5
                sessionChanged(await controller.status())
                return
            }
        }
        guard generation == revision else { refreshNeeded = true; return }
        if decision.shouldHold, ownedSessionID == nil, !manual, let remaining = decision.remainingSeconds, context.uptime >= startRetryAt {
            let claimID = UUID()
            do {
                if let session = try await controller.startIfIdle(sessionID: claimID, durationSeconds: remaining, keepDisplayAwake: snapshot.keepDisplayAwake) {
                    guard generation == revision else {
                        // Stop only this late claim; a manual replacement is protected by the controller's
                        // UUID guard.
                        do { _ = try await controller.stop(sessionID: session.id) }
                        catch { ownedSessionID = session.id; self.error = error.localizedDescription }
                        refreshNeeded = true
                        return
                    }
                    ownedSessionID = session.id
                    appliedSettings = snapshot
                    startRetryAt = 0
                    stopRetryAt = 0
                    error = nil
                }
            } catch {
                // A partially acquired assertion can survive a failed native rollback.
                if await controller.status()?.id == claimID { ownedSessionID = claimID }
                self.error = error.localizedDescription
                startRetryAt = context.uptime + 30
            }
        }
        let updated = await controller.status()
        guard generation == revision else { refreshNeeded = true; return }
        sessionChanged(updated)
    }
    private func statusIfChanged(_ value: AwakeAutomationStatus) { if status != value { status = value } }
    static func currentInput() -> AwakeAutomationInput {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let source = info.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
        let power: Bool? = source.flatMap { $0 == kIOPSACPowerValue ? true : ($0 == kIOPSBatteryPowerValue ? false : nil) }
        let displays = NSScreen.screens.compactMap(\.displayID)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return .init(runningApplicationIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                     externalDisplay: displays.isEmpty ? nil : displays.contains { CGDisplayIsBuiltin($0) == 0 },
                     externalPower: power, locked: session?["CGSSessionScreenIsLocked"] as? Bool,
                     uptime: ProcessInfo.processInfo.systemUptime)
    }
    #if DEBUG
    var diagnosticResources: [String: Int] { ["ownedSession": ownedSessionID == nil ? 0 : 1, "refreshTask": refreshTask == nil ? 0 : 1, "reconciling": reconciling ? 1 : 0] }
    #endif
}

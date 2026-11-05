#if DEBUG
import AppKit
import IOKit.pwr_mgt
import MacPocketCore
import SwiftUI

@MainActor private final class AwakeAuditEnvironment {
    var input = AwakeAutomationInput(runningApplicationIDs: [], externalDisplay: true, externalPower: true, locked: false, uptime: 1000)
    var reads = 0
}

private actor ManualAwakeAuditController: SleepControlling {
    private var session: AwakeSession?
    private(set) var starts = 0
    func status() -> AwakeSession? { session }
    func start(durationSeconds: Double?, keepDisplayAwake: Bool) async throws -> AwakeSession {
        starts += 1
        let created = AwakeSession(startedAt: .now, endsAt: durationSeconds.map { Date().addingTimeInterval($0) }, keepDisplayAwake: keepDisplayAwake)
        session = created
        if starts == 1 { try await Task.sleep(for: .milliseconds(150)) }
        return created
    }
    func startIfIdle(sessionID: UUID, durationSeconds: Double, keepDisplayAwake: Bool) -> AwakeSession? { nil }
    func stop() { session = nil }
    func stop(sessionID: UUID) -> Bool {
        guard session?.id == sessionID else { return false }; session = nil; return true
    }
}

private actor AwakeAuditController: IdleSleepControlling {
    private var session: AwakeSession?
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var lastDuration = 0.0
    var failStart = false, failStop = false, partialFailure = false, delayedReturn = false
    func configure(failStart: Bool = false, failStop: Bool = false, partialFailure: Bool = false, delayedReturn: Bool = false) {
        self.failStart = failStart; self.failStop = failStop; self.partialFailure = partialFailure; self.delayedReturn = delayedReturn
    }
    func status() -> AwakeSession? { session }
    func startIfIdle(sessionID: UUID, durationSeconds: Double, keepDisplayAwake: Bool) async throws -> AwakeSession? {
        guard session == nil else { return nil }
        starts += 1; lastDuration = durationSeconds
        let new = AwakeSession(id: sessionID, startedAt: .now, endsAt: Date().addingTimeInterval(durationSeconds), keepDisplayAwake: keepDisplayAwake)
        if partialFailure { session = new; throw SleepControllerError.nativeCall(operation: "FixtureCreate", code: -1) }
        if failStart { throw SleepControllerError.nativeCall(operation: "FixtureCreate", code: -1) }
        session = new
        if delayedReturn { try await Task.sleep(for: .milliseconds(150)) }
        return new
    }
    func stop(sessionID: UUID) throws -> Bool {
        guard session?.id == sessionID else { return false }
        stops += 1
        if failStop { throw SleepControllerError.nativeCall(operation: "FixtureRelease", code: -1) }
        session = nil; return true
    }
    func installManual() -> AwakeSession {
        let manual = AwakeSession(startedAt: .now, endsAt: nil, keepDisplayAwake: false)
        session = manual; return manual
    }
    func clear() { session = nil }
}

/// Controlled policy/driver cases plus one short system-idle assertion in the audit's own process.
@MainActor enum AwakeAutomationRuntimeAudit {
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested else { return [:] }
        let suite = "MacPocket.AwakeAudit." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AwakeAuditController()
        let fixture = AwakeAuditEnvironment()
        let service = AwakeAutomationService(controller: backend, defaults: defaults, environment: { fixture.reads += 1; return fixture.input })
        var checks: [String: Bool] = [:]
        let manualBackend = ManualAwakeAuditController()
        let manualModel = PocketModel(sleepController: manualBackend, startMonitoring: false)
        let focusStart = Task { await manualModel.startAwake(duration: 60, display: false) }
        for _ in 0..<100 { if await manualBackend.starts > 0 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        let manualReplacement = await manualModel.startAwake(duration: 120, display: false)
        let original = await focusStart.value
        checks["awakeStartReturnsItsOwnSessionEvenAfterReplacement"] = original?.id != nil && original?.id != manualReplacement?.id
        checks["awakeLateManualStartDoesNotOverwriteLatestUI"] = manualModel.awakeSession?.id == manualReplacement?.id
        if let original { await manualModel.stopAwake(sessionID: original.id) }
        checks["awakeFocusCleanupUsesReturnedUUID"] = await manualBackend.status()?.id == manualReplacement?.id
        await manualModel.stopAwake()
        checks["awakeExplicitManualStopClearsCurrentUI"] = manualModel.awakeSession == nil
        let stoppedBackend = ManualAwakeAuditController()
        let stoppedModel = PocketModel(sleepController: stoppedBackend, startMonitoring: false)
        let delayed = Task { await stoppedModel.startAwake(duration: 60, display: false) }
        for _ in 0..<100 { if await stoppedBackend.starts > 0 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        await stoppedModel.stopAwake(); _ = await delayed.value
        let stoppedStatus = await stoppedBackend.status()
        checks["awakeLateStartCannotUndoManualStop"] = stoppedModel.awakeSession == nil && stoppedStatus == nil
        await service.reconcile()
        checks["awakeDisabledDoesNotReadEnvironmentOrClaim"] = fixture.reads == 0 && service.ownedSessionID == nil
        var settings = AwakeAutomationSettings(); settings.enabled = true; settings.conditions = [.externalPower]
        service.settings = settings
        _ = await wait { service.ownedSessionID != nil }
        checks["awakeMatchingRuleClaimsSession"] = service.ownedSessionID != nil && service.status == .ready
        let starts = await backend.starts
        await service.reconcile(); await service.reconcile()
        checks["awakeStableRuleDoesNotRenewAssertion"] = await backend.starts == starts
        fixture.input.externalPower = false; await service.reconcile()
        checks["awakeLostConditionReleasesOwnedSession"] = await backend.status() == nil && service.ownedSessionID == nil
        fixture.input.externalPower = true; fixture.input.uptime = 1100; await service.reconcile()
        fixture.input.locked = true; fixture.input.uptime = 1120; await service.reconcile()
        checks["awakeLockPausesAndReleases"] = service.status == .locked && service.ownedSessionID == nil
        fixture.input.locked = false; fixture.input.uptime = 1150; await service.reconcile()
        checks["awakeUnlockUsesRemainingBudget"] = await backend.lastDuration == 7150
        service.pauseForManualControl(); await service.reconcile()
        _ = await wait { service.diagnosticResources["refreshTask"] == 0 }
        checks["awakeManualStopSuppressesAutomaticRestart"] = service.ownedSessionID == nil && service.status == .manualPause
        let manual = await backend.installManual()
        await service.reconcile()
        checks["awakeManualSessionNeverReplaced"] = await backend.status()?.id == manual.id && service.status == .manualSession
        await backend.clear(); await service.reconcile()
        checks["awakeManualExpiryDoesNotRearmRule"] = service.status == .manualPause && service.ownedSessionID == nil
        service.resume(); _ = await wait { service.ownedSessionID != nil }
        checks["awakeExplicitResumeCanStartNewCycle"] = service.ownedSessionID != nil
        fixture.input.uptime += 7201; await service.reconcile()
        checks["awakeBudgetLimitStopsWithoutRenewing"] = service.status == .limitReached && service.ownedSessionID == nil
        service.settings.enabled = false
        _ = await wait { service.diagnosticResources.values.allSatisfy { $0 == 0 } }

        // A controller may deliver a successful claim after a user starts a manual replacement.
        fixture.input.uptime = 10_000
        await backend.configure(delayedReturn: true)
        service.settings.enabled = true
        for _ in 0..<100 { if await backend.status() != nil { break }; try? await Task.sleep(for: .milliseconds(5)) }
        service.pauseForManualControl()
        let replacement = await backend.installManual()
        _ = await wait { service.diagnosticResources["reconciling"] == 0 && service.diagnosticResources["refreshTask"] == 0 }
        checks["awakeLateClaimCannotStopManualReplacement"] = await backend.status()?.id == replacement.id && service.ownedSessionID == nil
        service.settings.enabled = false
        _ = await wait { service.status == .disabled }
        checks["awakeDisablingDoesNotStopManualSession"] = await backend.status()?.id == replacement.id
        await backend.clear(); await backend.configure(failStart: true)
        service.settings.enabled = true
        _ = await wait { service.error != nil }
        let failedStarts = await backend.starts
        fixture.input.uptime += 5; await service.reconcile()
        checks["awakeCreateFailureBacksOff"] = await backend.starts == failedStarts && service.ownedSessionID == nil
        await backend.configure(); fixture.input.uptime += 30; await service.reconcile()
        checks["awakeCreateFailureCanRecover"] = service.error == nil && service.ownedSessionID != nil
        await backend.configure(failStop: true)
        fixture.input.externalPower = false; await service.reconcile()
        checks["awakeFailedReleaseRetainsOwnership"] = service.error != nil && service.ownedSessionID != nil
        await backend.configure(); fixture.input.uptime += 6; await service.reconcile()
        checks["awakeReleaseFailureRetriesCleanup"] = service.ownedSessionID == nil && service.error == nil
        service.settings.enabled = false; await service.reconcile()
        await backend.configure(partialFailure: true)
        fixture.input.externalPower = true; fixture.input.uptime += 100
        service.settings.enabled = true
        _ = await wait { service.error != nil && service.ownedSessionID != nil }
        checks["awakePartialCreateFailureKeepsClaimIdentity"] = service.ownedSessionID != nil
        await backend.configure(); service.settings.enabled = false
        _ = await wait { service.ownedSessionID == nil }
        checks["awakePartialFailureCanBeCleanedWhenDisabled"] = await backend.status() == nil

        service.settings = settings
        _ = await wait { service.ownedSessionID != nil }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 780), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); window.contentView = nil }
        let hosting = NSHostingView(rootView: ScrollView { AwakeAutomationView(service: service).padding(20) }.background(PocketTheme.background))
        hosting.sizingOptions = []; window.contentView = hosting; window.setContentSize(CGSize(width: 480, height: 780))
        window.center(); window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(200))
        let nodes = snapshot(window, to: destination.appendingPathExtension("awake-rules.png"))
        let names = nodes.filter { ["AXCheckBox", "AXSwitch"].contains($0["role"] ?? "") }.compactMap { $0["name"] }
        checks["awakeEnableAndRuleSwitchesNamed"] = names.contains(String(localized: "Koşullu uyanık tutma")) && AwakeAutomationCondition.allCases.allSatisfy { names.contains($0.localizedTitle) }
        checks["awakeMatchAndDurationPickersNamed"] = [String(localized: "Koşullar"), String(localized: "Otomasyonun süre sınırı")].allSatisfy { title in
            nodes.contains { $0["name"] == title && $0["role"] == "AXPopUpButton" }
        }
        service.settings.conditions.insert(.applicationRunning)
        service.settings.applicationIDs = ["fixture.editor"]; service.settings.applicationNames = ["fixture.editor": "Fixture Editor"]
        try? await Task.sleep(for: .milliseconds(100))
        _ = snapshot(window, to: destination.appendingPathExtension("awake-app-rule.png"))
        service.settings.enabled = false
        _ = await wait { service.diagnosticResources.values.allSatisfy { $0 == 0 } }
        checks["awakeDisableDrainsAllOwnedWork"] = service.diagnosticResources.values.allSatisfy { $0 == 0 }
        let live = AwakeAutomationService.currentInput()
        let evidence: [String: Any] = ["externalDisplay": live.externalDisplay as Any? ?? NSNull(), "externalPower": live.externalPower as Any? ?? NSNull(), "locked": live.locked as Any? ?? NSNull(), "note": "Controlled driver cases are simulated; separate UUID-scoped checks use the native system-idle driver."]
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: destination.appendingPathExtension("awake-live-input.json")) }
        if live.externalPower == true {
            let native = SleepController()
            let liveService = AwakeAutomationService(controller: native, defaults: defaults)
            var liveSettings = AwakeAutomationSettings()
            liveSettings.enabled = true; liveSettings.conditions = [.externalPower]; liveSettings.maximumMinutes = 1
            // Audit-only, no display assertion and no wake/unlock API; only a short idle-sleep hold.
            liveSettings.pauseWhenLocked = false; liveSettings.keepDisplayAwake = false
            liveService.settings = liveSettings
            _ = await wait { liveService.ownedSessionID != nil }
            let id = liveService.ownedSessionID
            let assertions = id.flatMap { nativeAssertions($0) } ?? []
            checks["awakeRealPowerInputCreatesOwnedNativeAssertion"] = id != nil && assertions.count == 1
            checks["awakeNativeProbeDoesNotHoldDisplay"] = assertions.first?[kIOPMAssertionTypeKey as String] as? String == kIOPMAssertionTypePreventUserIdleSystemSleep
            liveService.settings.enabled = false
            _ = await wait { liveService.diagnosticResources.values.allSatisfy { $0 == 0 } }
            checks["awakeNativeProbeReleasesItsUUID"] = id.map { nativeAssertions($0)?.isEmpty == true } == true && liveService.ownedSessionID == nil
        } else { checks["awakeRealPowerInputCreatesOwnedNativeAssertion"] = false }
        return checks
    }
    private static func nativeAssertions(_ id: UUID) -> [[String: Any]]? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess, let dictionary = unmanaged?.takeRetainedValue() as NSDictionary? else { return nil }
        let rows = dictionary[NSNumber(value: getpid())] as? [[String: Any]] ?? []
        return rows.filter { ($0[kIOPMAssertionNameKey as String] as? String)?.contains(id.uuidString) == true }
    }
    private static func wait(_ condition: () -> Bool) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + 3
        repeat { if condition() { return true }; try? await Task.sleep(for: .milliseconds(10)) } while ProcessInfo.processInfo.systemUptime < end
        return condition()
    }
    private static func snapshot(_ window: NSWindow, to url: URL) -> [[String: String]] {
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        }
        let nodes = ToolUIAudit.accessibilityNodes(window)
        if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url.appendingPathExtension("ax.json")) }
        return nodes
    }
}
#endif

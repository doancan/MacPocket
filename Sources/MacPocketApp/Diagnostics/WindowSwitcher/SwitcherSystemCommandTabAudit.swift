#if DEBUG
import AppKit
import MacPocketCore

/// Actual Carbon registrations and WindowServer setters. No other application is touched, no key injection or
/// user window action.
@MainActor enum SwitcherSystemCommandTabAudit {
    private static func wait(_ predicate: () -> Bool,seconds: Double = 4) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime+seconds
        while !predicate(),ProcessInfo.processInfo.systemUptime < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return predicate()
    }
    private static func state() -> [String:Bool] {
        guard let value = SwitcherNativeKeyGuard.currentState() else { return [:] }
        return ["forward":value.forward,"reverse":value.reverse]
    }
    static func run(catalog: any WindowCatalogServing,checks: inout [String:Bool],
                    manualExercise: ((WindowSwitcherHotkeyController) async throws -> [String:Any])? = nil) async -> [String:Any] {
        let before = SwitcherNativeKeyGuard.currentState(),secureBefore = SecureKeyboardInputStatus.read()
        let suite = "MacPocket.SystemCommandTabAudit."+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var leases: [SwitcherNativeKeyLease] = [],controller: WindowSwitcherHotkeyController?
        var evidence: [String:Any] = ["secureInputEnabled":secureBefore.enabled,"secureInputOwnerPID":secureBefore.processID ?? 0,
            "nativeInitial":state(),"physicalKeyboardVerified":false,
            "generatedInputUsed":false,"eventTapInstalled":false,"globalSettersExercised":false]
        do {
            guard before != nil,let executable = Bundle.main.executableURL else { throw WindowCatalogError.unsupported }
            let ordinary = SwitcherNativeKeyState(forward: true,reverse: true)
            guard await wait({ SwitcherNativeKeyGuard.currentState() == ordinary }) else { throw WindowCatalogError.unsupported }
            checks["systemCommandTabStartsWithBothNativeKeysEnabled"] = true
            var registration = SwitcherHotkeyRegistration.system
            registration.acquireNative = {
                let lease = try SwitcherNativeKeyLease.acquire(executable: executable)
                leases.append(lease)
                return lease
            }
            defaults.set(true,forKey: "switcher.globalEnabled")
            SwitcherShortcutStore.save([.init(keyCode: SwitcherKeys.tab,modifiers: manualExercise == nil ? .command : .option)],defaults)
            let wantsCapture = manualExercise != nil
            let model = WindowSwitcherModel(catalog: catalog,defaults: defaults,permitsCapture: { wantsCapture && WindowPreviewProvider.permitted })
            let live = WindowSwitcherHotkeyController(model: model,exceptionApplication: { nil },gestureSettings: defaults,
                registration: registration,shortcutSettings: defaults)
            controller = live
            if let manualExercise {
                live.beginPhysicalInputAudit()
                let result = try await manualExercise(live)
                evidence["manualKeyboard"] = result
                checks.merge(result["checks"] as? [String:Bool] ?? [:],uniquingKeysWith: { _,new in new })
                evidence["physicalKeyboardVerified"] = result["physicalKeyboardVerified"] as? Bool ?? false
            } else {
            live.beginRegistrationAudit()
            evidence["registrationMessage"] = live.registrationMessage
            checks["systemCommandTabRegistersBothRealCarbonKeys"] = live.moduleDiagnosticResources["hotKeys"] == 2
            checks["systemCommandTabOwnHelperDisablesBothNativeKeys"] = leases.count == 1 && leases[0].isActive && SwitcherNativeKeyGuard.currentState() == .init(forward: false,reverse: false)
            guard checks["systemCommandTabOwnHelperDisablesBothNativeKeys"] == true else { throw WindowCatalogError.unsupported }
            evidence["nativeWhileOwned"] = state()
            _ = live.setRecording(true)
            checks["systemCommandTabRecorderRestoresActualNativeKeys"] = SwitcherNativeKeyGuard.currentState() == ordinary && live.moduleDiagnosticResources["hotKeys"] == 0
            _ = live.setRecording(false)
            checks["systemCommandTabRecorderExitReacquiresActualNativeKeys"] = leases.count == 2 && SwitcherNativeKeyGuard.currentState() == .init(forward: false,reverse: false)
            guard leases.count == 2 else { throw WindowCatalogError.unsupported }
            checks["systemCommandTabOwnedGuardCanBeTerminated"] = leases[1].terminateOwnedSystemGuardForAudit()
            checks["systemCommandTabParentRestoresAfterRealGuardDeath"] = await wait { SwitcherNativeKeyGuard.currentState() == ordinary }
            checks["systemCommandTabWatchReleasesDeadGuardsCarbonKeys"] = await wait { live.moduleDiagnosticResources["hotKeys"] == 0 && live.canRetryNativeKeys }
            checks["systemCommandTabDoesNotCrashLoop"] = leases.count == 2
            live.retryNativeKeys()
            checks["systemCommandTabExplicitRetryReacquires"] = leases.count == 3 && SwitcherNativeKeyGuard.currentState() == .init(forward: false,reverse: false)
            live.stopForModule()
            checks["systemCommandTabModuleStopRestoresActualNativeKeys"] = SwitcherNativeKeyGuard.currentState() == ordinary
            checks["systemCommandTabModuleStopReleasesResources"] = live.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
            }
        } catch { evidence["error"] = String(describing: error) }
        // Finish every old owner before restoring the native key state, so no late restoration can override
        // it.
        controller?.stopForModule()
        for lease in leases { _ = lease.stop() }
        if !(await wait({ leases.allSatisfy { !$0.isRunning } },seconds: 6)) {
            for lease in leases where lease.isRunning { _ = lease.terminateOwnedSystemGuardForAudit() }
            _ = await wait({ leases.allSatisfy { !$0.isRunning } })
        }
        for lease in leases { _ = lease.stop() }
        checks["systemCommandTabAllOwnedGuardsExit"] = leases.allSatisfy { !$0.isRunning }
        checks["systemCommandTabOriginalNativeStateRestored"] = await wait { before != nil && before == SwitcherNativeKeyGuard.currentState() }
        checks["systemCommandTabSecureInputWasNotChanged"] = secureBefore == SecureKeyboardInputStatus.read()
        evidence["nativeFinal"] = state()
        evidence["ownedGuardsCreated"] = leases.count
        evidence["globalSettersExercised"] = !leases.isEmpty
        return evidence
    }
}
#endif

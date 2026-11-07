import AppKit
@preconcurrency import Carbon
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

@MainActor private final class RegistrationLease: SwitcherNativeKeyOwning {
    var isActive = true,isRunning = true,mayStop = true
    var stopped: () -> Void = {}
    func pulse() -> Bool { isActive && isRunning }
    func stop() -> Bool {
        stopped()
        if mayStop { isActive = false;isRunning = false }
        return mayStop
    }
}

@MainActor private final class RegistrationHarness {
    let name = "SwitcherRegistrationTests."+UUID().uuidString
    let defaults: UserDefaults
    var events: [String] = []
    var failIDs = Set<UInt32>()
    var failAcquire = false
    var acquisitions = 0
    var handles: [EventHotKeyRef:UInt32] = [:]
    var leases: [RegistrationLease] = []
    var application: SwitcherForegroundApplication?
    var controller: WindowSwitcherHotkeyController!
    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.set(true,forKey: "switcher.globalEnabled")
        SwitcherShortcutStore.save([.init(keyCode: 48,modifiers: .command),.defaultOptionTab],defaults)
        let registration = SwitcherHotkeyRegistration(register: { [unowned self] _,_,id in
            events.append("register:\(id.id)")
            if failIDs.contains(id.id) { return (-9878,nil) }
            let ref = EventHotKeyRef(bitPattern: Int(id.id)+0x100)!
            handles[ref] = id.id
            return (noErr,ref)
        },unregister: { [unowned self] ref in
            events.append("unregister:\(handles.removeValue(forKey: ref) ?? 0)")
        },acquireNative: { [unowned self] in
            events.append("acquire");acquisitions += 1
            if failAcquire { throw SwitcherNativeKeyError.unavailable }
            let lease = RegistrationLease()
            lease.stopped = { [weak self] in self?.events.append("restore") }
            leases.append(lease)
            return lease
        })
        controller = WindowSwitcherHotkeyController(model: WindowSwitcherModel(defaults: defaults),
            exceptionApplication: { [weak self] in self?.application },gestureSettings: defaults,
            registration: registration,shortcutSettings: defaults)
    }
    var ids: Set<UInt32> { Set(handles.values) }
    func start() { controller.beginRegistrationAudit() }
    func close() { controller.stopForModule();defaults.removePersistentDomain(forName: name) }
}

@MainActor final class SwitcherRegistrationTests: XCTestCase {
    func testOrdinaryShortcutNeedsNeitherNativeLeaseNorWatch() {
        let h = RegistrationHarness();defer { h.close() }
        SwitcherShortcutStore.save([.defaultOptionTab],h.defaults);h.start()
        XCTAssertEqual(h.ids,[1,2]);XCTAssertEqual(h.acquisitions,0)
        XCTAssertEqual(h.controller.moduleDiagnosticResources["nativeKeyTimer"],0)
        h.controller.stopForModule()
        XCTAssertTrue(h.controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 })
    }

    func testEitherCarbonFailureRollsBackSuccessfulHalfAndNeverAcquiresNativeKeys() {
        for failed: UInt32 in [1,2] {
            let h = RegistrationHarness();defer { h.close() }
            h.failIDs = [failed];h.start()
            XCTAssertEqual(h.ids,[3,4]);XCTAssertEqual(h.acquisitions,0)
            XCTAssertTrue(h.events.contains("unregister:\(failed == 1 ? 2 : 1)"))
        }
    }

    func testBothCarbonRegistrationsPrecedeAcquireAndRestorePrecedesUnregister() throws {
        let h = RegistrationHarness();defer { h.close() };h.start()
        XCTAssertEqual(Array(h.events.prefix(3)),["register:1","register:2","acquire"])
        XCTAssertEqual(h.ids,[1,2,3,4])
        h.events = [];XCTAssertTrue(h.controller.setRecording(true))
        XCTAssertEqual(h.events.first,"restore");XCTAssertTrue(h.ids.isEmpty)
        XCTAssertEqual(h.controller.moduleDiagnosticResources["nativeKeyTimer"],0)
        XCTAssertTrue(h.controller.setRecording(false));XCTAssertEqual(h.acquisitions,2)
        h.events = [];h.controller.stopForModule()
        XCTAssertEqual(h.events.first,"restore");XCTAssertTrue(h.ids.isEmpty)
        XCTAssertTrue(h.controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 })
    }

    func testAcquisitionFailureRollsBackPairAndExplicitRetryCanRecover() {
        let h = RegistrationHarness();defer { h.close() }
        h.failAcquire = true;h.start()
        XCTAssertEqual(h.ids,[3,4]);XCTAssertTrue(h.controller.canRetryNativeKeys)
        h.controller.refreshRegistrationForAudit();h.controller.checkNativeKeysForAudit()
        XCTAssertEqual(h.acquisitions,1)
        h.failAcquire = false;h.controller.retryNativeKeys()
        XCTAssertEqual(h.ids,[1,2,3,4]);XCTAssertEqual(h.acquisitions,2)
        XCTAssertFalse(h.controller.canRetryNativeKeys)
    }

    func testUnexpectedGuardianDeathDoesNotRestartUntilExplicitRetry() {
        let h = RegistrationHarness();defer { h.close() };h.start()
        h.leases[0].isActive = false;h.leases[0].isRunning = false
        h.controller.checkNativeKeysForAudit()
        XCTAssertEqual(h.ids,[3,4]);XCTAssertEqual(h.acquisitions,1)
        h.controller.checkNativeKeysForAudit();h.controller.refreshRegistrationForAudit()
        XCTAssertEqual(h.acquisitions,1)
        h.controller.retryNativeKeys()
        XCTAssertEqual(h.acquisitions,2);XCTAssertEqual(h.ids,[1,2,3,4])
    }

    func testEditingCommandProfileToOrdinaryRestoresAndStopsWatch() {
        let h = RegistrationHarness();defer { h.close() };h.start();h.events = []
        h.controller.saveShortcuts([.defaultOptionTab])
        XCTAssertEqual(h.events.first,"restore");XCTAssertEqual(h.ids,[1,2])
        XCTAssertEqual(h.acquisitions,1);XCTAssertEqual(h.controller.moduleDiagnosticResources["nativeKeyTimer"],0)
    }

    func testUnrestoredOldGuardianPreventsOverlappingOwnerAndCanRecover() {
        let h = RegistrationHarness();defer { h.close() };h.start()
        h.leases[0].mayStop = false
        XCTAssertTrue(h.controller.setRecording(true));XCTAssertTrue(h.ids.isEmpty)
        XCTAssertTrue(h.controller.setRecording(false))
        XCTAssertEqual(h.acquisitions,1);XCTAssertEqual(h.ids,[3,4])
        h.leases[0].mayStop = true;h.controller.retryNativeKeys()
        XCTAssertEqual(h.acquisitions,2);XCTAssertEqual(h.ids,[1,2,3,4])
    }

    func testGlobalDisableStopsWatchAndRestoresBeforeReleasingHotkeys() {
        let h = RegistrationHarness();defer { h.close() };h.start();h.events = []
        h.defaults.set(false,forKey: "switcher.globalEnabled");h.controller.refreshRegistrationForAudit()
        XCTAssertEqual(h.events.first,"restore");XCTAssertTrue(h.ids.isEmpty)
        XCTAssertEqual(h.controller.moduleDiagnosticResources["nativeKeyTimer"],0)
        XCTAssertEqual(h.controller.moduleDiagnosticResources["nativeKeyLease"],0)
    }

    func testApplicationExceptionRestoresAndRemovingItResumesRegistration() {
        let h = RegistrationHarness();defer { h.close() };h.start();h.events = []
        h.application = .init(processID: 100,launchedAt: nil,bundleIdentifier: "com.example.Editor",applicationPath: "/Applications/Editor.app",name: "Editor")
        XCTAssertTrue(SwitcherExceptionStore.save([.init(target: .bundleIdentifier,value: "com.example.Editor",shortcuts: .alwaysDisable)],h.defaults))
        h.controller.refreshRegistrationForAudit()
        XCTAssertEqual(h.events.first,"restore");XCTAssertTrue(h.ids.isEmpty)
        XCTAssertEqual(h.controller.suspendedForApplication,"Editor")
        XCTAssertTrue(SwitcherExceptionStore.save([],h.defaults));h.controller.refreshRegistrationForAudit()
        XCTAssertEqual(h.acquisitions,2);XCTAssertEqual(h.ids,[1,2,3,4])
    }
}

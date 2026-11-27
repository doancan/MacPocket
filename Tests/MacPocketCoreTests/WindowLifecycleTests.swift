import AppKit
import XCTest
@testable import MacPocketCore

final class WindowLifecycleTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 10)
    private func identity(_ id: UInt32 = 1, pid: Int32 = 7, launched: TimeInterval = 10) -> WindowLifecycleIdentity {
        .init(windowID: id, processID: pid, launchedAt: Date(timeIntervalSince1970: launched))
    }
    private func created(_ id: UInt32) -> WindowLifecycleMessage { .init(event: .created, windowID: id) }
    private func destroyed(_ id: UInt32) -> WindowLifecycleMessage { .init(event: .destroyed, windowID: id) }

    func testBaselineAdmissionDoesNotInventCreationDates() {
        var timeline = WindowLifecycleTimeline()
        timeline.admit([identity()])
        XCTAssertNil(timeline.snapshot.creation(for: identity()))
        XCTAssertTrue(timeline.snapshot.available)
        XCTAssertEqual(timeline.snapshot.revision, 0)
    }
    func testObservedBirthMustBindToKnownProcessIdentity() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(1), at: Date(timeIntervalSince1970: 20))
        XCTAssertNil(timeline.snapshot.creation(for: identity()))
        timeline.admit([identity()])
        XCTAssertEqual(timeline.snapshot.creation(for: identity())?.observedAt, Date(timeIntervalSince1970: 20))
        XCTAssertNil(timeline.snapshot.creation(for: identity(pid: 8)))
        XCTAssertNil(timeline.snapshot.creation(for: identity(launched: 11)))
    }
    func testProcessBornAfterEventAndAmbiguousOwnersDoNotInheritHistory() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(1), at: Date(timeIntervalSince1970: 20))
        timeline.admit([identity(launched: 30)])
        XCTAssertNil(timeline.snapshot.creation(for: identity(launched: 30)))
        timeline.admit([identity(), identity(pid: 8)])
        XCTAssertNil(timeline.snapshot.creation(for: identity()))
    }
    func testChangedOwnerWithoutNewBirthExpiresHistoryAndOldHandles() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(1), at: Date(timeIntervalSince1970: 20))
        timeline.admit([identity()])
        let old = timeline.snapshot
        timeline.admit([identity(pid: 8)])
        XCTAssertNil(timeline.snapshot.creation(for: identity(pid: 8)))
        XCTAssertTrue(timeline.snapshot.invalidates(1, since: old))
    }
    func testCreateDestroyReuseCannotResurrectPriorIdentityOrCreationDate() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(1), at: Date(timeIntervalSince1970: 20))
        timeline.admit([identity()])
        let old = timeline.snapshot
        timeline.record(destroyed(1), at: Date(timeIntervalSince1970: 30))
        timeline.admit([identity()])
        XCTAssertNil(timeline.snapshot.creation(for: identity()))
        XCTAssertTrue(timeline.snapshot.invalidates(1, since: timeline.snapshot))
        timeline.record(created(1), at: Date(timeIntervalSince1970: 40))
        timeline.admit([identity(pid: 8)])
        XCTAssertNil(timeline.snapshot.creation(for: identity()))
        XCTAssertEqual(timeline.snapshot.creation(for: identity(pid: 8))?.observedAt, Date(timeIntervalSince1970: 40))
        XCTAssertTrue(timeline.snapshot.invalidates(1, since: old))
        XCTAssertFalse(timeline.snapshot.invalidates(1, since: timeline.snapshot))
    }
    func testDuplicateCreateKeepsFirstObservedOrderAndClockChangesDoNotReverseSequence() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(1), at: Date(timeIntervalSince1970: 50))
        timeline.admit([identity()])
        timeline.record(created(1), at: Date(timeIntervalSince1970: 55))
        timeline.record(created(2), at: Date(timeIntervalSince1970: 30))
        timeline.admit([identity(), identity(2)])
        XCTAssertEqual(timeline.snapshot.creation(for: identity())?.observedAt, Date(timeIntervalSince1970: 50))
        XCTAssertLessThan(timeline.snapshot.creation(for: identity())!.sequence, timeline.snapshot.creation(for: identity(2))!.sequence)
    }
    func testOnlyIDsChangedDuringScanAreRejected() {
        var timeline = WindowLifecycleTimeline()
        let before = timeline.snapshot
        timeline.record(created(1), at: .now)
        XCTAssertTrue(timeline.snapshot.invalidates(1, since: before))
        XCTAssertFalse(timeline.snapshot.invalidates(2, since: before))
        let after = timeline.snapshot
        XCTAssertFalse(after.invalidates(1, since: after))
        timeline.record(destroyed(1), at: .now)
        XCTAssertTrue(timeline.snapshot.invalidates(1, since: after))
    }
    func testUnresolvedFastBirthDoesNotTransferItsDateToALaterUseOfThatID() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(1), at: Date(timeIntervalSince1970: 20))
        // The first surface vanished before its owner could be resolved or watched for 804.
        timeline.record(created(1), at: Date(timeIntervalSince1970: 40))
        timeline.admit([identity(pid: 8, launched: 30)])
        XCTAssertEqual(timeline.snapshot.creation(for: identity(pid: 8, launched: 30))?.observedAt, Date(timeIntervalSince1970: 40))
    }
    func testEvictionExpiresOldScansInsteadOfCallingForgottenDestroyedIDLive() {
        var timeline = WindowLifecycleTimeline(capacity: 1)
        let old = timeline.snapshot
        timeline.record(destroyed(1), at: .now)
        timeline.record(created(2), at: .now)
        XCTAssertEqual(timeline.snapshot.entries.count, 1)
        XCTAssertTrue(timeline.snapshot.invalidates(1, since: old))
        XCTAssertFalse(timeline.snapshot.invalidates(3, since: timeline.snapshot))
    }
    func testSessionRestartAndMonitorFailureExpirePriorHandles() {
        let first = WindowLifecycleTimeline().snapshot, next = WindowLifecycleTimeline().snapshot
        XCTAssertTrue(next.invalidates(1, since: first))
        XCTAssertTrue(WindowLifecycleSnapshot.unavailable.invalidates(1, since: first))
        XCTAssertTrue(next.invalidates(1, since: .unavailable))
        XCTAssertFalse(WindowLifecycleSnapshot.unavailable.invalidates(1, since: .unavailable))
    }
    func testMalformedWrongLengthZeroAndUnrelatedEventsAreIgnoredIncludingUnalignedPayload() {
        var bytes: [UInt8] = [0, 42, 0, 0, 0, 99]
        bytes.withUnsafeMutableBytes { buffer in
            let address = buffer.baseAddress!.advanced(by: 1)
            XCTAssertEqual(WindowLifecycleMessage.decode(event: 811, data: address, length: 4)?.windowID, 42)
            XCTAssertEqual(WindowLifecycleMessage.decode(event: 804, data: address, length: 4)?.event, .destroyed)
            for length in [-1, 0, 3, 5, 12] { XCTAssertNil(WindowLifecycleMessage.decode(event: 811, data: address, length: length)) }
            for event: UInt32 in [806, 815, 816, 1325, 1326] { XCTAssertNil(WindowLifecycleMessage.decode(event: event, data: address, length: 4)) }
        }
        var zero: UInt32 = 0
        withUnsafePointer(to: &zero) { XCTAssertNil(WindowLifecycleMessage.decode(event: 811, data: $0, length: 4)) }
        XCTAssertNil(WindowLifecycleMessage.decode(event: 811, data: nil, length: 4))
    }
    func testCreationSortUsesObservedSequenceAndUnknownWindowsFollowMRU() {
        var timeline = WindowLifecycleTimeline()
        timeline.record(created(11), at: Date(timeIntervalSince1970: 40))
        timeline.record(created(2), at: Date(timeIntervalSince1970: 30))
        timeline.admit([identity(11), identity(2)])
        let windows = [UInt32(1), 2, 11, 3].map { id in
            SwitchableWindow(id: "w\(id)", processID: 7, application: "Fixture", title: "same", applicationURL: nil,
                minimized: false, hidden: false, fullScreen: false, frontmost: id == 1, windowAccessible: true,
                canClose: true, canMinimize: true, canFullScreen: true, launchedAt: launch,
                lastFocusedAt: Date(timeIntervalSince1970: Double(id)), windowID: id,
                creationObservation: timeline.snapshot.creation(for: identity(id)))
        }
        XCTAssertEqual(WindowFiltering.apply(windows, order: .creation).compactMap(\.windowID), [11, 2, 3, 1])
        XCTAssertEqual(WindowFiltering.apply(windows, order: .recent).compactMap(\.windowID), [11, 3, 2, 1])
    }
    func testCreationSortPreferenceRoundTripsAndOldUnknownValuesStillFallback() throws {
        var presentation = SwitcherPresentationOverrides()
        presentation.order = .creation
        XCTAssertEqual(try JSONDecoder().decode(SwitcherPresentationOverrides.self, from: JSONEncoder().encode(presentation)).order, .creation)
        XCTAssertNil(try JSONDecoder().decode(SwitcherPresentationOverrides.self, from: Data(#"{"order":"future"}"#.utf8)).order)
    }
}

@MainActor private final class LifecycleBackendFixture: WindowLifecycleBackend {
    struct Registration { let event: UInt32; let callback: WindowLifecycleCallback; let context: UnsafeMutableRawPointer }
    let connection: UInt32 = 99
    var registrations: [Registration] = []
    var removed: [UInt32] = []
    var requests: [[UInt32]] = []
    var rejectEvent: UInt32?
    var rejectRequest = false
    var rejectRemove = false
    func register(event: UInt32, callback: WindowLifecycleCallback, context: UnsafeMutableRawPointer) -> Bool {
        guard event != rejectEvent else { return false }
        registrations.append(.init(event: event, callback: callback, context: context))
        return true
    }
    func remove(event: UInt32, callback: WindowLifecycleCallback, context: UnsafeMutableRawPointer) -> Bool {
        removed.append(event)
        return !rejectRemove
    }
    func request(windowIDs: [UInt32]) -> Bool { requests.append(windowIDs); return !rejectRequest }
    func emit(_ event: UInt32, id: UInt32, registration: Int? = nil, connection: UInt32 = 99) {
        guard let record = registration.map({ registrations[$0] }) ?? registrations.last(where: { $0.event == event }) else { return }
        var number = id
        withUnsafeMutablePointer(to: &number) { record.callback(event, $0, 4, record.context, connection) }
    }
}

@MainActor final class WindowLifecycleServiceTests: XCTestCase {
    @MainActor private final class NotificationCounter { var value = 0; var valid = true }
    private func identity(_ id: UInt32) -> WindowLifecycleIdentity {
        .init(windowID: id, processID: getpid(), launchedAt: CatalogWindowIdentity.processLaunchDate(pid: getpid(), applicationDate: nil)!)
    }
    func testLeasesShareRegistrationAndLastOwnerUnregistersAndClearsWholeWatchList() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: nil)
        let unavailable = UUID()
        service.start(unavailable)
        XCTAssertFalse(service.snapshot().available)
        service.stop(unavailable)
        let live = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), first = UUID(), second = UUID()
        live.start(first)
        live.start(first)
        live.start(second)
        XCTAssertEqual(backend.registrations.count, 2)
        _ = live.snapshot(admitting: [identity(1), identity(2)])
        XCTAssertEqual(backend.requests.last, [1, 2])
        live.stop(first)
        XCTAssertTrue(backend.removed.isEmpty)
        live.stop(second)
        XCTAssertEqual(Set(backend.removed), [811, 804])
        XCTAssertEqual(backend.requests.last, [])
        XCTAssertTrue(live.diagnosticResources.values.allSatisfy { $0 == 0 })
    }
    func testWatchRequestsSendUnionAndDestroyPrunesOnlyOnTheNextFullRequest() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        defer { service.stop(owner) }
        _ = service.snapshot(admitting: [identity(1)])
        _ = service.snapshot(admitting: [identity(2)])
        XCTAssertEqual(backend.requests, [[1], [1, 2]])
        _ = service.snapshot(admitting: [identity(2)])
        XCTAssertEqual(backend.requests.count, 2)
        backend.emit(804, id: 1)
        _ = service.snapshot(admitting: [identity(2)])
        XCTAssertEqual(backend.requests.last, [2])
    }
    func testFailedPartialRegistrationRollsBackAndDisablesRetry() {
        let backend = LifecycleBackendFixture()
        backend.rejectEvent = 804
        let service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        XCTAssertEqual(backend.removed, [811])
        XCTAssertFalse(service.snapshot().available)
        service.stop(owner)
        service.start(owner)
        XCTAssertEqual(backend.registrations.count, 1)
        service.stop(owner)
    }
    func testFailedWatchRequestTearsDownAndDoesNotPublishFalseHistory() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        backend.rejectRequest = true
        XCTAssertFalse(service.snapshot(admitting: [identity(1)]).available)
        XCTAssertEqual(Set(backend.removed), [811, 804])
        service.stop(owner)
    }
    func testWrongConnectionAndRetiredContextCannotAffectRestartedSession() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        let old = service.snapshot()
        backend.emit(811, id: 1, connection: 100)
        XCTAssertEqual(service.snapshot().revision, old.revision)
        service.stop(owner)
        service.start(owner)
        let fresh = service.snapshot()
        backend.emit(811, id: 1, registration: 0)
        XCTAssertEqual(service.snapshot().revision, fresh.revision)
        backend.emit(811, id: 1)
        XCTAssertNotNil(service.snapshot(admitting: [identity(1)]).creation(for: identity(1)))
        XCTAssertNotEqual(fresh.sessionID, old.sessionID)
        service.stop(owner)
    }
    func testRemoveFailureDisablesFutureRegistrationsButLateCallbackRemainsSafe() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        backend.rejectRemove = true
        service.stop(owner)
        backend.emit(811, id: 1, registration: 0)
        service.start(owner)
        XCTAssertFalse(service.snapshot().available)
        XCTAssertEqual(backend.registrations.count, 2)
        service.stop(owner)
    }

    func testInvalidProcessFactsCannotBindBirthOrSeedAWatch() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in false }), owner = UUID()
        service.start(owner)
        backend.emit(811, id: 1)
        XCTAssertNil(service.snapshot(admitting: [identity(1)]).creation(for: identity(1)))
        XCTAssertTrue(backend.requests.isEmpty)
        service.stop(owner)
    }

    func testDeadProcessPruningReplacesFullWatchList() {
        let backend = LifecycleBackendFixture()
        let state = NotificationCounter()
        let service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in state.valid }), owner = UUID()
        service.start(owner)
        _ = service.snapshot(admitting: [identity(1)])
        state.valid = false
        _ = service.snapshot()
        XCTAssertEqual(backend.requests, [[1], []])
        service.stop(owner)
    }

    func testCapacityFailureFallsBackRatherThanSilentlyDroppingLiveWindowWatches() {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        let facts = (1...8_193).map { WindowLifecycleIdentity(windowID: UInt32($0), processID: 1, launchedAt: .distantPast) }
        XCTAssertFalse(service.snapshot(admitting: facts).available)
        XCTAssertEqual(backend.requests, [[]])
        XCTAssertEqual(Set(backend.removed), [811, 804])
        service.stop(owner)
    }

    func testConcurrentIngressSerializesEventsAndQueuesOneDeliveryForABurst() async {
        let ingress = WindowLifecycleIngress(connection: 99)
        let deliveries = NotificationCounter()
        ingress.activate { _ in deliveries.value += 1 }
        // Main is occupied for this bounded burst; callbacks may arrive from arbitrary threads.
        DispatchQueue.concurrentPerform(iterations: 256) { index in
            ingress.receive(.init(event: .created, windowID: UInt32(index + 1)), connection: 99)
        }
        let snapshot = ingress.snapshot(admitting: [])
        XCTAssertEqual(snapshot.entries.count, 256)
        XCTAssertEqual(Set(snapshot.entries.values.compactMap { $0.creation?.sequence }).count, 256)
        XCTAssertEqual(deliveries.value, 0)
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(deliveries.value, 1)
        ingress.deactivate()
        ingress.receive(.init(event: .created, windowID: 999), connection: 99)
        XCTAssertFalse(ingress.snapshot(admitting: []).available)
    }

    func testDestroyNotificationSurvivesACatalogPruningTheWatchBeforeDelivery() async {
        let backend = LifecycleBackendFixture(), service = WindowLifecycleService(backend: backend, isProcessCurrent: { _ in true }), owner = UUID()
        service.start(owner)
        defer { service.stop(owner) }
        let fact = WindowLifecycleIdentity(windowID: 101, processID: getpid() + 10_000, launchedAt: .distantPast)
        let baseline = service.snapshot(admitting: [fact])
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: WindowLifecycleObservation.didChangeNotification, object: nil, queue: .main) { notification in
            guard notification.object as? WindowLifecycleService === service else { return }
            MainActor.assumeIsolated { counter.value += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        backend.emit(804, id: 101)
        let after = service.snapshot()
        XCTAssertTrue(after.invalidates(101, since: baseline))
        XCTAssertEqual(backend.requests.last, [])
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(counter.value, 1)
    }
}

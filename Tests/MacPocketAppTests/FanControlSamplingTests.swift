import Synchronization
import XCTest
import MacPocketCore
@testable import MacPocketApp
import MacPocketTestSupport

private actor FanTemperatureFixture: FanTemperatureReading {
    var value: Double? = 60
    private(set) var reads = 0
    private var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?
    func block() { blocked = true }
    func unblock() { blocked = false; continuation?.resume(); continuation = nil }
    func setValue(_ value: Double?) { self.value = value }
    func celsius() async -> Double? {
        reads += 1
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return value
    }
}

private final class FanHelperFixture: NSObject, MacPocketHelperXPC, @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (status: 0, targets: [Double](), heartbeats: 0, releases: 0)
    var snapshot: (status: Int, targets: [Double], heartbeats: Int, releases: Int) { lock.withLock { counts } }
    var holdTarget = false
    private var targetReply: (@Sendable (String?) -> Void)?
    func finishTarget() { let reply = lock.withLock { let reply = targetReply; targetReply = nil; return reply }; reply?(nil) }
    func status(reply: @escaping @Sendable ([[NSNumber]], String?) -> Void) {
        lock.withLock { counts.status += 1 }
        reply([[2000, 1000, 5000]], nil)
    }
    func setTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) {
        let held = lock.withLock { counts.targets.append(rpm); if holdTarget { targetReply = reply }; return holdTarget }
        if !held { reply(nil) }
    }
    func heartbeat(reply: @escaping @Sendable () -> Void) { lock.withLock { counts.heartbeats += 1 }; reply() }
    func releaseAll(reply: @escaping @Sendable () -> Void) { lock.withLock { counts.releases += 1 }; reply() }
    func scanMACAddresses(cidr: String, interface: String, reply: @escaping @Sendable ([String: String], String?) -> Void) { reply([:], nil) }
}

/// Behaves like an unreachable helper: NSXPC reports the failure on its own queue and never calls the reply.
private final class UnreachableHelperFixture: NSObject, MacPocketHelperXPC, Sendable {
    private let onError: @Sendable (any Error) -> Void
    private let statusCalls = Mutex(0)
    var statusCount: Int { statusCalls.withLock { $0 } }
    init(onError: @escaping @Sendable (any Error) -> Void) { self.onError = onError }
    private func fail() {
        let onError = onError
        DispatchQueue.global().async {
            onError(NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid))
        }
    }
    func status(reply: @escaping @Sendable ([[NSNumber]], String?) -> Void) { statusCalls.withLock { $0 += 1 }; fail() }
    func setTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) { fail() }
    func heartbeat(reply: @escaping @Sendable () -> Void) { fail() }
    func releaseAll(reply: @escaping @Sendable () -> Void) { fail() }
    func scanMACAddresses(cidr: String, interface: String, reply: @escaping @Sendable ([String: String], String?) -> Void) { fail() }
}

/// A helper launchd can't start: messages are queued forever, with neither a reply nor an error.
private final class SilentHelperFixture: NSObject, MacPocketHelperXPC, Sendable {
    func status(reply: @escaping @Sendable ([[NSNumber]], String?) -> Void) {}
    func setTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) {}
    func heartbeat(reply: @escaping @Sendable () -> Void) {}
    func releaseAll(reply: @escaping @Sendable () -> Void) {}
    func scanMACAddresses(cidr: String, interface: String, reply: @escaping @Sendable ([String: String], String?) -> Void) {}
}

@MainActor final class FanControlSamplingTests: XCTestCase {
    private func fixture() -> (FanControlService, FanTemperatureFixture, FanHelperFixture) {
        let defaults = temporaryDefaults()
        let temperatures = FanTemperatureFixture(), helper = FanHelperFixture()
        return (FanControlService(defaults: defaults, temperatures: temperatures, helper: helper), temperatures, helper)
    }
    private func wait(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<600 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
    private func stop(_ service: FanControlService, helper: FanHelperFixture) async {
        service.profile = .system
        service.viewDisappeared()
        let stopped = await wait { !service.isPolling }
        XCTAssertTrue(stopped)
    }

    func testSystemProfileReadsFanStatusWithoutReadingTemperature() async {
        let (service, temperatures, helper) = fixture()
        XCTAssertFalse(service.isPolling)
        XCTAssertEqual(service.reading, .loading)
        service.viewAppeared()
        let appeared = await wait { helper.snapshot.status == 1 }
        XCTAssertTrue(appeared)
        let loaded = await wait { service.reading == .loaded }
        XCTAssertTrue(loaded)
        service.viewDisappeared()
        XCTAssertFalse(service.isPolling)
        let reads = await temperatures.reads
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(helper.snapshot.targets.isEmpty)
    }

    func testFixedProfileKeepsHiddenHeartbeatWithoutTemperatureAndStopsAfterRelease() async {
        let (service, temperatures, helper) = fixture()
        service.profile = .fixed(percent: 50)
        let alive = await wait { helper.snapshot.heartbeats == 1 }
        XCTAssertTrue(alive)
        XCTAssertEqual(helper.snapshot.targets, [3000])
        let reads = await temperatures.reads
        XCTAssertEqual(reads, 0)
        await stop(service, helper: helper)
        XCTAssertEqual(helper.snapshot.releases, 1)
        let status = helper.snapshot.status
        try? await Task.sleep(for: .milliseconds(2100))
        XCTAssertEqual(helper.snapshot.status, status)
    }

    func testLostConnectionResendsTheManualTargetToTheNewHelper() async {
        // A restarted helper (e.g. after an app update) starts with the fans under system control.
        let (service, _, helper) = fixture()
        service.profile = .fixed(percent: 50)
        let sent = await wait { helper.snapshot.targets.count == 1 }
        XCTAssertTrue(sent)
        service.connectionLost()
        let resent = await wait { helper.snapshot.targets.count == 2 }
        XCTAssertTrue(resent)
        XCTAssertEqual(helper.snapshot.targets, [3000, 3000])
        await stop(service, helper: helper)
    }

    func testCurveReadsFreshTemperatureAndPreservesTargetCalculation() async {
        let (service, temperatures, helper) = fixture()
        service.profile = .curve([CurvePoint(celsius: 40, percent: 0), CurvePoint(celsius: 80, percent: 100)])
        let initial = await wait { helper.snapshot.targets.count == 1 }
        XCTAssertTrue(initial)
        XCTAssertEqual(helper.snapshot.targets, [3000])
        await temperatures.setValue(80)
        let updated = await wait { helper.snapshot.targets.count == 2 }
        XCTAssertTrue(updated)
        XCTAssertEqual(helper.snapshot.targets, [3000, 5000])
        let reads = await temperatures.reads
        XCTAssertEqual(reads, 2)
        await stop(service, helper: helper)
    }

    func testMissingCurveTemperatureReleasesFansWithoutSendingTarget() async {
        let (service, temperatures, helper) = fixture()
        await temperatures.setValue(nil)
        service.profile = FanControlService.temperatureCurve
        let released = await wait { helper.snapshot.releases == 1 }
        XCTAssertTrue(released)
        XCTAssertTrue(helper.snapshot.targets.isEmpty)
        XCTAssertNotNil(service.message)
        await stop(service, helper: helper)
    }

    func testProfileChangeDuringTemperatureReadDoesNotApplyStaleCurve() async {
        let (service, temperatures, helper) = fixture()
        await temperatures.block()
        service.profile = FanControlService.temperatureCurve
        let reading = await wait { await temperatures.reads == 1 }
        XCTAssertTrue(reading)
        service.profile = .system
        service.viewDisappeared()
        await temperatures.unblock()
        let stopped = await wait { !service.isPolling }
        XCTAssertTrue(stopped)
        XCTAssertTrue(helper.snapshot.targets.isEmpty)
        XCTAssertEqual(helper.snapshot.releases, 1)
    }

    func testProfileChangeDuringTargetReplyStillReleasesBeforeStopping() async {
        let (service, _, helper) = fixture()
        helper.holdTarget = true
        service.profile = .fixed(percent: 50)
        let sent = await wait { helper.snapshot.targets.count == 1 }
        XCTAssertTrue(sent)
        service.profile = .system
        service.viewDisappeared()
        helper.finishTarget()
        let stopped = await wait { !service.isPolling }
        XCTAssertTrue(stopped)
        XCTAssertEqual(helper.snapshot.releases, 1)
    }

    func testUnreachableHelperErrorOffMainThreadDoesNotStallPolling() async {
        let defaults = temporaryDefaults()
        var helpers: [UnreachableHelperFixture] = []
        let service = FanControlService(defaults: defaults, temperatures: FanTemperatureFixture(), connector: { onError in
            if helpers.isEmpty { helpers.append(UnreachableHelperFixture(onError: onError)) }
            return helpers.first
        })
        XCTAssertEqual(service.reading, .loading)
        service.viewAppeared()
        let reported = await wait { service.message != nil }
        XCTAssertTrue(reported)
        XCTAssertEqual(service.reading, .failed, "an unreachable helper is not the same as a Mac without fans")
        // The next tick must run again instead of waiting forever for a reply that never comes.
        let retried = await wait { (helpers.first?.statusCount ?? 0) >= 2 }
        XCTAssertTrue(retried)
        XCTAssertTrue(service.fans.isEmpty)
        service.viewDisappeared()
    }

    func testHelperThatNeverAnswersTimesOutInsteadOfLoadingForever() async {
        let service = FanControlService(defaults: temporaryDefaults(), temperatures: FanTemperatureFixture(),
                                        helper: SilentHelperFixture(), requestTimeout: .milliseconds(200))
        service.viewAppeared()
        let failed = await wait { service.reading == .failed }
        XCTAssertTrue(failed)
        XCTAssertNotNil(service.message)
        service.viewDisappeared()
    }

    func testTemperatureWorkerDoesNotRunBlockingReadOnMainThread() async {
        let worker = FanTemperatureReader(read: { Thread.isMainThread ? nil : 61 })
        let value = await worker.celsius()
        XCTAssertEqual(value, 61)
    }
}

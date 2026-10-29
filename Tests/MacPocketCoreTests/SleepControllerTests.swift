import XCTest
import Darwin
import IOKit.pwr_mgt
@testable import MacPocketCore

final class SleepControllerTests: XCTestCase {
    private func nativeAssertions(for session: AwakeSession) throws -> [[String: Any]] {
        var unmanaged: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&unmanaged)
        XCTAssertEqual(result, kIOReturnSuccess)
        let raw: CFDictionary = try XCTUnwrap(unmanaged?.takeRetainedValue())
        let dictionary = raw as NSDictionary
        let current = dictionary[NSNumber(value: getpid())] as? [[String: Any]] ?? []
        return current.filter { ($0[kIOPMAssertionNameKey as String] as? String)?.contains(session.id.uuidString) == true }
    }

    func testNativeSystemAndDisplayAssertionsAreCreatedAndReleased() async throws {
        let controller = SleepController()
        let session = try await controller.start(durationSeconds: nil, keepDisplayAwake: true)
        do {
            XCTAssertTrue(session.active)
            XCTAssertTrue(session.keepDisplayAwake)
            XCTAssertNil(session.endsAt)
            let native = try nativeAssertions(for: session)
            let types = Set(native.compactMap { $0[kIOPMAssertionTypeKey as String] as? String })
            XCTAssertEqual(native.count, 2)
            XCTAssertTrue(native.allSatisfy {
                ($0[kIOPMAssertionLevelKey as String] as? NSNumber)?.intValue == Int(kIOPMAssertionLevelOn)
            })
            XCTAssertTrue(types.contains(kIOPMAssertionTypePreventUserIdleSystemSleep as String))
            XCTAssertTrue(types.contains(kIOPMAssertionTypePreventUserIdleDisplaySleep as String))
        } catch {
            try? await controller.stop()
            throw error
        }
        try await controller.stop()
        let status = await controller.status()
        XCTAssertNil(status)
        XCTAssertTrue(try nativeAssertions(for: session).isEmpty)
        try await controller.stop()
    }

    func testSystemOnlySessionDoesNotCreateDisplayAssertion() async throws {
        let controller = SleepController()
        let session = try await controller.start(durationSeconds: nil, keepDisplayAwake: false)
        do {
            let native = try nativeAssertions(for: session)
            XCTAssertEqual(native.count, 1)
            XCTAssertEqual(native.first?[kIOPMAssertionTypeKey as String] as? String,
                           kIOPMAssertionTypePreventUserIdleSystemSleep as String)
        } catch {
            try? await controller.stop()
            throw error
        }
        try await controller.stop()
    }

    func testFiniteSessionAutomaticallyReleasesNativeAssertion() async throws {
        let controller = SleepController()
        let session = try await controller.start(durationSeconds: 0.15, keepDisplayAwake: false)
        do {
            XCTAssertNotNil(session.endsAt)
            XCTAssertEqual(try nativeAssertions(for: session).count, 1)
            try await Task.sleep(for: .milliseconds(250))
            let status = await controller.status()
            XCTAssertNil(status)
            XCTAssertTrue(try nativeAssertions(for: session).isEmpty)
        } catch {
            try? await controller.stop()
            throw error
        }
        try await controller.stop()
    }

    func testInvalidDurationLeavesExistingSessionIntact() async throws {
        let controller = SleepController()
        let original = try await controller.start(durationSeconds: nil, keepDisplayAwake: false)
        do {
            for duration in [0, -1, Double.nan, Double.infinity, -Double.infinity,
                             SleepController.maximumDurationSeconds + 1] {
                do {
                    _ = try await controller.start(durationSeconds: duration, keepDisplayAwake: true)
                    XCTFail("Expected invalid duration")
                } catch SleepControllerError.invalidDuration { }
                let status = await controller.status()
                XCTAssertEqual(status?.id, original.id)
            }
            XCTAssertEqual(try nativeAssertions(for: original).count, 1)
        } catch {
            try? await controller.stop()
            throw error
        }
        try await controller.stop()
    }

    func testMaximumFiniteDurationIsAcceptedAndManuallyStoppable() async throws {
        let controller = SleepController()
        let session = try await controller.start(durationSeconds: SleepController.maximumDurationSeconds,
                                                 keepDisplayAwake: false)
        do {
            let endsAt = try XCTUnwrap(session.endsAt)
            XCTAssertEqual(endsAt.timeIntervalSince(session.startedAt), 604_800, accuracy: 0.001)
        } catch {
            try? await controller.stop()
            throw error
        }
        try await controller.stop()
        XCTAssertTrue(try nativeAssertions(for: session).isEmpty)
    }

    func testReplacingSessionCancelsOldTimerWithoutLeakingAssertions() async throws {
        let controller = SleepController()
        let original = try await controller.start(durationSeconds: 0.15, keepDisplayAwake: true)
        let replacement: AwakeSession
        do {
            replacement = try await controller.start(durationSeconds: nil, keepDisplayAwake: false)
            XCTAssertNotEqual(original.id, replacement.id)
            XCTAssertTrue(try nativeAssertions(for: original).isEmpty)
            try await Task.sleep(for: .milliseconds(250))
            let status = await controller.status()
            XCTAssertEqual(status?.id, replacement.id)
            XCTAssertEqual(try nativeAssertions(for: replacement).count, 1)
        } catch {
            try? await controller.stop()
            throw error
        }
        try await controller.stop()
        XCTAssertTrue(try nativeAssertions(for: replacement).isEmpty)
    }

    func testControllerDeinitializationReleasesItsAssertions() async throws {
        var controller: SleepController? = SleepController()
        let session = try await controller!.start(durationSeconds: nil, keepDisplayAwake: true)
        XCTAssertEqual(try nativeAssertions(for: session).count, 2)
        controller = nil
        XCTAssertTrue(try nativeAssertions(for: session).isEmpty)
    }
}

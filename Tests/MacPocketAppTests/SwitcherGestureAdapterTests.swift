import AppKit
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

@MainActor final class SwitcherGestureAdapterTests: XCTestCase {
    private func contacts(_ x: Double) -> [SwitcherGestureContact] { (1...3).map { .init(id: Int32($0),x: x,y: 0.4) } }
    private func trigger(_ relay: TrackpadGestureRelay,device: UInt64 = 1) {
        relay.process(device: device,contacts: [])
        relay.process(device: device,contacts: contacts(0.3))
        relay.process(device: device,contacts: contacts(0.38))
    }
    func testQueuedDeliveryIsDiscardedAfterStop() async {
        let relay = TrackpadGestureRelay()
        var received: [SwitcherGestureEvent] = []
        relay.configure(options: .init(fingers: 3),devices: [1]) { received.append($0) }
        trigger(relay)
        relay.stop()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(received.isEmpty)
    }
    func testReconfigurationDropsPreviousGenerationAndRequiresNewNeutralBoundary() async {
        let relay = TrackpadGestureRelay()
        var received: [SwitcherGestureEvent] = []
        relay.configure(options: .init(fingers: 3),devices: [1]) { received.append($0) }
        trigger(relay)
        relay.configure(options: .init(fingers: 3),devices: [2]) { received.append($0) }
        trigger(relay)
        relay.process(device: 2,contacts: contacts(0.4))
        relay.process(device: 2,contacts: contacts(0.8))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(received.isEmpty)
        trigger(relay,device: 2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received.count,1)
        relay.stop()
    }
    func testRecognizedStepAndReleaseAreDeliveredInOrderWithSameIdentity() async {
        let relay = TrackpadGestureRelay()
        var received: [SwitcherGestureEvent] = []
        relay.configure(options: .init(fingers: 3),devices: [1]) { received.append($0) }
        trigger(relay)
        relay.process(device: 1,contacts: [])
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received.count,2)
        if received.count == 2 { XCTAssertEqual(received[1],.ended(id: received[0].id)) }
        relay.stop()
    }
    func testHardwareLossCancelsDeliveredGestureAndDiscardsQueuedFingerRelease() async {
        let relay = TrackpadGestureRelay()
        var received: [SwitcherGestureEvent] = []
        relay.configure(options: .init(fingers: 3),devices: [1]) { received.append($0) }
        trigger(relay)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received.count,1)
        guard let gesture = received.first else { relay.stop();return }
        relay.process(device: 1,contacts: [])
        relay.cancelForHardwareChange()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received,[gesture,.cancelled(id: gesture.id)])
        relay.stop()
    }
    func testHardwareChangeDiscardsUndeliveredGestureAndRequiresNeutralFrame() async {
        let relay = TrackpadGestureRelay()
        var received: [SwitcherGestureEvent] = []
        relay.configure(options: .init(fingers: 3),devices: [1]) { received.append($0) }
        trigger(relay)
        relay.cancelForHardwareChange()
        relay.process(device: 1,contacts: contacts(0.4))
        relay.process(device: 1,contacts: contacts(0.8))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(received.isEmpty)
        trigger(relay)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(received.count,1)
        relay.stop()
    }
    func testNativeHardwareObservationRearmsAndStopCancelsPendingWakeDelivery() async {
        let observation = TrackpadHardwareObservation()
        var changes: [Bool] = []
        defer { observation.stop() }
        XCTAssertTrue(observation.start { changes.append($0) })
        XCTAssertEqual(observation.diagnosticResources,["port":1,"source":1,"iterators":2,"wakeObserver":1,"sleepObserver":1,"pending":0])
        XCTAssertTrue(observation.start { changes.append($0) })
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification,object: nil)
        for _ in 0..<60 where changes.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }   // a loaded CI machine is slower than 220 ms
        XCTAssertEqual(changes,[true])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification,object: nil)
        observation.stop()
        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(changes,[true])
        XCTAssertTrue(observation.diagnosticResources.values.allSatisfy { $0 == 0 })
    }
    func testSleepCancelsScheduledReconnectAndWakeSchedulesFreshEnumeration() async {
        let observation = TrackpadHardwareObservation()
        var changes: [Bool] = [],sleeps = 0
        defer { observation.stop() }
        XCTAssertTrue(observation.start(willSleep: { sleeps += 1 }) { changes.append($0) })
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.didWakeNotification,object: nil)
        center.post(name: NSWorkspace.willSleepNotification,object: nil)
        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(sleeps,1)
        XCTAssertTrue(changes.isEmpty)
        center.post(name: NSWorkspace.didWakeNotification,object: nil)
        for _ in 0..<60 where changes.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(changes,[true])
    }
    func testConnectedTrackpadNativeAdapterStartsAndStops() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACPOCKET_TEST_TRACKPAD"] == "1",
                          "Set MACPOCKET_TEST_TRACKPAD=1 on a Mac with a connected trackpad.")
        let monitor = TrackpadSwipeMonitor()
        defer { monitor.stop() }
        XCTAssertTrue(monitor.isAvailable)
        monitor.configure(options: .init(fingers: 3)) { _ in }
        XCTAssertTrue(monitor.isRunning,"The native device list must contain the connected trackpad.")
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        monitor.configure(options: .init(fingers: 4)) { _ in }
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }
    func testDecoderDistinguishesAllUpFromInvalidBufferAndBoundsCount() {
        XCTAssertEqual(TrackpadContactDecoder.decode(touches: nil,count: 0),[])
        XCTAssertNil(TrackpadContactDecoder.decode(touches: nil,count: 1))
        XCTAssertNil(TrackpadContactDecoder.decode(touches: nil,count: -1))
        XCTAssertNil(TrackpadContactDecoder.decode(touches: nil,count: .max))
    }
    func testDecoderIncludesMakeTouchAndTouchingButExcludesBreakingAndHovering() {
        var data = Data(repeating: 0,count: 8 * 96 + 1)
        data.withUnsafeMutableBytes { bytes in
            for state in 0..<8 {
                let base = bytes.baseAddress! + 1 + state * 96
                base.storeBytes(of: Int32(state + 10),toByteOffset: 16,as: Int32.self)
                base.storeBytes(of: Int32(state),toByteOffset: 20,as: Int32.self)
                base.storeBytes(of: Float(0.25),toByteOffset: 32,as: Float.self)
                base.storeBytes(of: Float(0.5),toByteOffset: 36,as: Float.self)
            }
        }
        let contacts = data.withUnsafeBytes { TrackpadContactDecoder.decode(touches: $0.baseAddress! + 1,count: 8) }
        XCTAssertEqual(contacts,[.init(id: 13,x: 0.25,y: 0.5),.init(id: 14,x: 0.25,y: 0.5)])
    }
    func testDecoderRejectsUnknownABIStateInsteadOfTreatingItAsRelease() {
        var data = Data(repeating: 0,count: 96)
        data.withUnsafeMutableBytes { $0.storeBytes(of: Int32(99),toByteOffset: 20,as: Int32.self) }
        XCTAssertNil(data.withUnsafeBytes { TrackpadContactDecoder.decode(touches: $0.baseAddress,count: 1) })
    }
}

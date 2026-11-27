import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class SwitcherGestureTests: XCTestCase {
    private func contacts(_ x: Double = 0.3,_ y: Double = 0.3,fingers: Int = 3) -> [SwitcherGestureContact] {
        (0..<fingers).map { .init(id: Int32($0 + 1),x: x + Double($0) * 0.04,y: y) }
    }
    private func armed(_ options: SwitcherGestureOptions = .init(fingers: 3)) -> SwitcherGestureTracker {
        var tracker = SwitcherGestureTracker(options: options)
        _ = tracker.process(device: 1,contacts: [])
        _ = tracker.process(device: 1,contacts: contacts(fingers: options.fingers))
        return tracker
    }
    func testPreferencesPreserveOldFingerCountWithoutWritingNewKeys() {
        let d = temporaryDefaults()
        XCTAssertEqual(SwitcherGestureOptions.load(d),.init())
        XCTAssertNil(d.object(forKey: SwitcherGestureOptions.axisKey))
        d.set(4,forKey: SwitcherGestureOptions.fingersKey)
        XCTAssertEqual(SwitcherGestureOptions.load(d),.init(fingers: 4))
        XCTAssertNil(d.object(forKey: SwitcherGestureOptions.hapticsKey))
        d.set("bad",forKey: SwitcherGestureOptions.axisKey)
        d.set(9,forKey: SwitcherGestureOptions.fingersKey)
        XCTAssertEqual(SwitcherGestureOptions.load(d),.init())
        d.set(3,forKey: SwitcherGestureOptions.fingersKey)
        d.set("vertical",forKey: SwitcherGestureOptions.axisKey)
        d.set(true,forKey: SwitcherGestureOptions.hapticsKey)
        XCTAssertEqual(SwitcherGestureOptions.load(d),.init(fingers: 3,axis: .vertical,haptics: true))
    }
    func testEnablingMidContactRequiresAnAllUpBoundary() {
        var t = SwitcherGestureTracker(options: .init(fingers: 3))
        XCTAssertEqual(t.process(device: 1,contacts: contacts()),[])
        XCTAssertEqual(t.process(device: 1,contacts: contacts(0.6)),[])
        XCTAssertEqual(t.process(device: 1,contacts: []),[])
        XCTAssertEqual(t.process(device: 1,contacts: contacts()),[])
        XCTAssertEqual(t.process(device: 1,contacts: contacts(0.38)).count,1)
    }
    func testHorizontalTravelKeepsRemainderAndReversesWithoutExtraNoise() {
        var t = armed()
        XCTAssertTrue(t.process(device: 1,contacts: contacts(0.36)).isEmpty)
        guard case .step(let id,.horizontal,false,2)? = t.process(device: 1,contacts: contacts(0.45)).first else { return XCTFail("two forward steps") }
        XCTAssertTrue(t.process(device: 1,contacts: contacts(0.46)).isEmpty)
        XCTAssertEqual(t.process(device: 1,contacts: contacts(0.36)),[.step(id: id,axis: .horizontal,backwards: true,count: 1)])
        XCTAssertEqual(t.process(device: 1,contacts: []),[.ended(id: id)])
        XCTAssertTrue(t.process(device: 1,contacts: []).isEmpty)
    }
    func testVerticalFourFingerUsesUpForBackwardsAndDownForForward() {
        var t = armed(.init(fingers: 4,axis: .vertical))
        guard case .step(let id,.vertical,true,1)? = t.process(device: 1,contacts: contacts(0.3,0.38,fingers: 4)).first else { return XCTFail("up") }
        XCTAssertEqual(t.process(device: 1,contacts: contacts(0.3,0.28,fingers: 4)),[.step(id: id,axis: .vertical,backwards: false,count: 1)])
    }
    func testPartialLiftFreezesUntilLastFingerAndDoesNotCommitEarly() {
        var t = armed()
        let events = t.process(device: 1,contacts: contacts(0.38))
        let id = events[0].id
        XCTAssertTrue(t.process(device: 1,contacts: Array(contacts(0.38).prefix(2))).isEmpty)
        XCTAssertTrue(t.process(device: 1,contacts: Array(contacts(0.7).prefix(1))).isEmpty)
        XCTAssertEqual(t.process(device: 1,contacts: []),[.ended(id: id)])
    }
    func testReplacingContactCancelsAndCannotRestartUntilLift() {
        var t = armed()
        let id = t.process(device: 1,contacts: contacts(0.38))[0].id
        var changed = contacts(0.4)
        changed[0] = .init(id: 99,x: 0.8,y: 0.3)
        XCTAssertEqual(t.process(device: 1,contacts: changed),[.cancelled(id: id)])
        XCTAssertTrue(t.process(device: 1,contacts: contacts(0.7)).isEmpty)
        XCTAssertTrue(t.process(device: 1,contacts: []).isEmpty)
        _ = t.process(device: 1,contacts: contacts())
        XCTAssertEqual(t.process(device: 1,contacts: contacts(0.38)).count,1)
    }
    func testRejoiningAndExtraFingerCancelRatherThanCommit() {
        for extra in [false,true] {
            var t = armed()
            let id = t.process(device: 1,contacts: contacts(0.38))[0].id
            if !extra { _ = t.process(device: 1,contacts: Array(contacts(0.38).prefix(2))) }
            XCTAssertEqual(t.process(device: 1,contacts: contacts(0.4,fingers: extra ? 4 : 3)),[.cancelled(id: id)])
            XCTAssertTrue(t.process(device: 1,contacts: []).isEmpty)
        }
    }
    func testTwoDevicesCannotMixOrCommitEachOthersGesture() {
        var t = armed()
        _ = t.process(device: 2,contacts: [])
        let id = t.process(device: 1,contacts: contacts(0.38))[0].id
        XCTAssertTrue(t.process(device: 2,contacts: contacts(0.8)).isEmpty)
        XCTAssertTrue(t.process(device: 2,contacts: []).isEmpty)
        XCTAssertEqual(t.process(device: 1,contacts: []),[.ended(id: id)])
        _ = t.process(device: 2,contacts: contacts())
        XCTAssertEqual(t.process(device: 2,contacts: contacts(0.38)).count,1)
    }
    func testCrossAxisCancelsUntilLiftAndSmallDiagonalStillNavigates() {
        var t = armed()
        XCTAssertTrue(t.process(device: 1,contacts: contacts(0.32,0.5)).isEmpty)
        XCTAssertTrue(t.process(device: 1,contacts: contacts(0.6,0.5)).isEmpty)
        _ = t.process(device: 1,contacts: [])
        _ = t.process(device: 1,contacts: contacts())
        XCTAssertEqual(t.process(device: 1,contacts: contacts(0.38,0.32)).count,1)
    }
    func testBadFramesCancelWithoutInfiniteWorkOrAccidentalCommit() {
        for bad: [SwitcherGestureContact]? in [nil,[.init(id: 1,x: .nan,y: 0)], [.init(id: 1,x: .infinity,y: 0)], [.init(id: 1,x: 2,y: 0)],Array(repeating: .init(id: 1,x: 0.2,y: 0.2),count: 3)] {
            var t = armed()
            let id = t.process(device: 1,contacts: contacts(0.38))[0].id
            XCTAssertEqual(t.process(device: 1,contacts: bad),[.cancelled(id: id)])
            XCTAssertTrue(t.process(device: 1,contacts: []).isEmpty)
        }
    }
    func testWrongFingerCountAndDisabledNeverTrigger() {
        var t = armed(.init(fingers: 4))
        XCTAssertTrue(t.process(device: 1,contacts: contacts(0.9)).isEmpty)
        var off = SwitcherGestureTracker(options: .init())
        _ = off.process(device: 1,contacts: [])
        _ = off.process(device: 1,contacts: contacts())
        XCTAssertTrue(off.process(device: 1,contacts: contacts(0.9)).isEmpty)
    }
    func testMaximumValidTravelIsBoundedInOneEvent() {
        var t = SwitcherGestureTracker(options: .init(fingers: 3))
        _ = t.process(device: 1,contacts: [])
        _ = t.process(device: 1,contacts: (1...3).map { .init(id: Int32($0),x: 0,y: 0) })
        let events = t.process(device: 1,contacts: (1...3).map { .init(id: Int32($0),x: 1,y: 0) })
        guard case .step(_,_,false,14)? = events.first else { return XCTFail("bounded step batch") }
        XCTAssertEqual(events.count,1)
    }
}

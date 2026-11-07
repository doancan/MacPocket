import XCTest
@testable import MacPocketCore

final class WindowCursorFollowTests: XCTestCase {
    private let screens: [(id: UInt32,frame: CGRect)] = [(1,CGRect(x: 0,y: 0,width: 1000,height: 800)),(2,CGRect(x: 1000,y: 0,width: 1000,height: 800))]
    private let origin = CGPoint(x: 100,y: 100)
    private func destination(_ policy: SwitcherCursorPolicy = .always,frame: CGRect = CGRect(x: 1200,y: 200,width: 400,height: 300),
                             current: CGPoint? = nil,displays: [(id: UInt32,frame: CGRect)]? = nil) -> CGPoint? {
        WindowCursorGeometry.destination(policy: policy,origin: origin,current: current ?? origin,window: frame,displays: displays ?? screens)
    }
    func testDefaultAndUnknownPreferenceNeverMoveAndReadingDoesNotWrite() {
        let suite = "WindowCursorFollowTests." + UUID().uuidString, defaults: UserDefaults
        defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SwitcherCursorPolicy.load(defaults),.never);XCTAssertNil(defaults.object(forKey: SwitcherCursorPolicy.key))
        defaults.set("future-mode",forKey: SwitcherCursorPolicy.key);XCTAssertEqual(SwitcherCursorPolicy.load(defaults),.never)
        for policy in SwitcherCursorPolicy.allCases { defaults.set(policy.rawValue,forKey: SwitcherCursorPolicy.key);XCTAssertEqual(SwitcherCursorPolicy.load(defaults),policy) }
        XCTAssertNil(destination(.never))
    }
    func testAlwaysTargetsTheVisibleCenterOnSameOrAnotherDisplay() {
        XCTAssertEqual(destination(),CGPoint(x: 1400,y: 350))
        XCTAssertEqual(destination(frame: CGRect(x: 200,y: 200,width: 400,height: 300)),CGPoint(x: 400,y: 350))
    }
    func testDifferentDisplayComparesPointerDisplayAndRejectsUnknownOrAmbiguousOwner() {
        XCTAssertEqual(destination(.differentDisplay),CGPoint(x: 1400,y: 350))
        XCTAssertNil(destination(.differentDisplay,frame: CGRect(x: 200,y: 200,width: 400,height: 300)))
        let gap: [(id: UInt32,frame: CGRect)] = [(2,CGRect(x: 1000,y: 0,width: 1000,height: 800))]
        XCTAssertNil(destination(.differentDisplay,displays: gap))
        XCTAssertNil(destination(.differentDisplay,displays: screens + [(3,screens[0].frame)]))
    }
    func testPartlyOffscreenWindowUsesOnlyItsVisibleIntersection() {
        XCTAssertEqual(destination(frame: CGRect(x: -500,y: -200,width: 800,height: 400)),CGPoint(x: 150,y: 100))
        XCTAssertNil(destination(frame: CGRect(x: -1000,y: -1000,width: 20,height: 20)))
    }
    func testSpanningWindowUsesCenterDisplayAndClipsBeforeCentering() {
        XCTAssertEqual(destination(frame: CGRect(x: 900,y: 200,width: 400,height: 300)),CGPoint(x: 1150,y: 350))
        XCTAssertEqual(destination(frame: CGRect(x: 600,y: 200,width: 400,height: 300)),CGPoint(x: 800,y: 350))
    }
    func testNegativeAndVerticallyArrangedDisplaysUseCoreGraphicsCoordinates() {
        let above: [(id: UInt32,frame: CGRect)] = screens + [(3,CGRect(x: -800,y: -600,width: 1000,height: 600))]
        XCTAssertEqual(destination(frame: CGRect(x: -700,y: -500,width: 200,height: 200),displays: above),CGPoint(x: -600,y: -400))
    }
    func testPointerMotionOrNewInteractionCancelsFollowEvenIfPointerReturnsToOrigin() {
        XCTAssertNil(destination(current: CGPoint(x: 104,y: 100)))
        let initial = WindowCursorOrigin(point: origin,interactionSerial: 100)
        XCTAssertNil(WindowCursorGeometry.destination(policy: .always,origin: initial,current: .init(point: origin,interactionSerial: 101),buttonsDown: false,
                                                      window: CGRect(x: 1200,y: 200,width: 400,height: 300),displays: screens))
        XCTAssertNil(WindowCursorGeometry.destination(policy: .always,origin: initial,current: initial,buttonsDown: true,
                                                      window: CGRect(x: 1200,y: 200,width: 400,height: 300),displays: screens))
    }
    func testInvalidGeometryAndOverflowingEdgesNeverReachCursorAPI() {
        XCTAssertNil(destination(frame: .zero));XCTAssertNil(destination(frame: CGRect(x: CGFloat.infinity,y: 0,width: 100,height: 100)))
        XCTAssertNil(destination(frame: CGRect(x: CGFloat.greatestFiniteMagnitude,y: 0,width: CGFloat.greatestFiniteMagnitude,height: 100)))
        XCTAssertNil(destination(displays: []));XCTAssertNil(destination(current: CGPoint(x: CGFloat.nan,y: 100)))
    }
}

import XCTest
@testable import MacPocketCore

final class MonitorVolumeTests: XCTestCase {
    func testVolumeKeysDecodeFromKeyCodesAndMediaEvents() {
        XCTAssertEqual(VolumeKey(keyCode: 72), .up)
        XCTAssertEqual(VolumeKey(keyCode: 73), .down)
        XCTAssertEqual(VolumeKey(keyCode: 74), .mute)
        XCTAssertNil(VolumeKey(keyCode: 144))
        XCTAssertEqual(VolumeKey(systemDefinedSubtype: 8, data1: 0x0000_0A00), .up)
        XCTAssertEqual(VolumeKey(systemDefinedSubtype: 8, data1: 0x0001_0A00), .down)
        XCTAssertEqual(VolumeKey(systemDefinedSubtype: 8, data1: 0x0007_0A00), .mute)
        XCTAssertNil(VolumeKey(systemDefinedSubtype: 8, data1: 0x0002_0A00), "Brightness up is not a volume key")
        XCTAssertNil(VolumeKey(systemDefinedSubtype: 7, data1: 0x0000_0A00))
    }

    func testStepsSnapToSixteenthsAndFineStepsToSixtyFourths() {
        var state = MonitorVolumeState(level: 0.2)
        state.apply(.up, fine: false)
        XCTAssertEqual(state.level, 0.25, accuracy: 0.0001)
        state.apply(.down, fine: true)
        XCTAssertEqual(state.level, 0.25 - 1.0 / 64, accuracy: 0.0001)
        state = MonitorVolumeState(level: 1)
        state.apply(.up, fine: false)
        XCTAssertEqual(state.level, 1)
        state = MonitorVolumeState(level: 0)
        state.apply(.down, fine: false)
        XCTAssertEqual(state.level, 0)
    }

    func testMuteKeepsLevelAndUpOrDownUnmutes() {
        var state = MonitorVolumeState(level: 0.5)
        state.apply(.mute, fine: false)
        XCTAssertTrue(state.muted)
        XCTAssertEqual(state.effectiveLevel, 0)
        XCTAssertEqual(state.level, 0.5)
        state.apply(.mute, fine: false)
        XCTAssertFalse(state.muted)
        XCTAssertEqual(state.effectiveLevel, 0.5)

        state.apply(.mute, fine: false)
        state.apply(.down, fine: false)
        XCTAssertFalse(state.muted)
        XCTAssertEqual(state.level, 0.4375, accuracy: 0.0001)
    }

    func testOnlyMonitorSpeakersMacOSCannotControlAreRouted() {
        XCTAssertTrue(MonitorVolumeRouting.controlsOutput(kind: .display, systemVolumeSettable: false))
        XCTAssertFalse(MonitorVolumeRouting.controlsOutput(kind: .display, systemVolumeSettable: true))
        XCTAssertFalse(MonitorVolumeRouting.controlsOutput(kind: .builtIn, systemVolumeSettable: false))
        XCTAssertFalse(MonitorVolumeRouting.controlsOutput(kind: .usb, systemVolumeSettable: false))
        XCTAssertFalse(MonitorVolumeRouting.controlsOutput(kind: .headphones, systemVolumeSettable: true))
    }

    func testAudioDeviceMatchesScreenByName() {
        let screens: [(id: UInt32, name: String)] = [(1, "LG HDR 4K"), (2, "MateView"), (3, "Built-in Retina Display")]
        XCTAssertEqual(MonitorVolumeRouting.display(forAudioDevice: "MateView", screens: screens), 2)
        XCTAssertEqual(MonitorVolumeRouting.display(forAudioDevice: "lg hdr 4k", screens: screens), 1)
        XCTAssertEqual(MonitorVolumeRouting.display(forAudioDevice: "LG HDR 4K (2)", screens: screens), 1)
        XCTAssertNil(MonitorVolumeRouting.display(forAudioDevice: "DELL U2720Q", screens: screens))
        XCTAssertNil(MonitorVolumeRouting.display(forAudioDevice: "", screens: screens))
        let twins: [(id: UInt32, name: String)] = [(1, "LG HDR 4K (1)"), (2, "LG HDR 4K (2)")]
        XCTAssertNil(MonitorVolumeRouting.display(forAudioDevice: "LG HDR 4K", screens: twins), "Two identical monitors are ambiguous")
    }

    func testMuteReplyMeaning() {
        XCTAssertEqual(MonitorVolumeRouting.muteState(fromReply: 1), true)
        XCTAssertEqual(MonitorVolumeRouting.muteState(fromReply: 2), false)
        XCTAssertNil(MonitorVolumeRouting.muteState(fromReply: 0))
        XCTAssertNil(MonitorVolumeRouting.muteState(fromReply: nil))
    }
}

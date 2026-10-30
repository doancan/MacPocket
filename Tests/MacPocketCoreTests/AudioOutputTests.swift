import XCTest
@testable import MacPocketCore

final class AudioOutputRulesTests: XCTestCase {
    private let speakers = AudioOutputDevice(objectID: 1, uid: "speakers", name: "Hoparlör", kind: .builtIn)
    private let airPods = AudioOutputDevice(objectID: 2, uid: "airpods", name: "AirPods", kind: .bluetooth)
    private let monitor = AudioOutputDevice(objectID: 3, uid: "lg", name: "LG", kind: .display)

    func testCyclesThroughConnectedDevicesInTheChosenOrder() {
        let devices = [speakers, airPods, monitor]
        XCTAssertEqual(AudioOutputRules.next(after: "speakers", devices: devices, cycle: []), airPods)
        XCTAssertEqual(AudioOutputRules.next(after: "lg", devices: devices, cycle: []), speakers, "wraps around")
        XCTAssertEqual(AudioOutputRules.next(after: "speakers", devices: devices, cycle: ["lg", "speakers"]), monitor)
        XCTAssertEqual(AudioOutputRules.next(after: "airpods", devices: devices, cycle: ["lg", "speakers"]), monitor,
                       "the current device isn't in the cycle: start at its first device")
    }

    func testDisconnectedCycleDevicesAreSkipped() {
        XCTAssertEqual(AudioOutputRules.next(after: "speakers", devices: [speakers], cycle: ["airpods", "speakers"]), speakers)
        XCTAssertNil(AudioOutputRules.next(after: nil, devices: [], cycle: []))
    }

    func testVolumeDropsOnlyWhenPersonalAudioFallsBackToSpeakers() {
        let settings = AudioOutputSettings()
        XCTAssertEqual(AudioOutputRules.volumeAfterSwitch(from: airPods, to: speakers, settings: settings), 0.25)
        XCTAssertNil(AudioOutputRules.volumeAfterSwitch(from: speakers, to: airPods, settings: settings))
        XCTAssertNil(AudioOutputRules.volumeAfterSwitch(from: monitor, to: speakers, settings: settings))
        var off = settings
        off.speakerVolumeAfterHeadphones = nil
        XCTAssertNil(AudioOutputRules.volumeAfterSwitch(from: airPods, to: speakers, settings: off))
    }
}

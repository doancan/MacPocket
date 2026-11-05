import XCTest
@testable import MacPocketCore

final class MixerRoutingTests: XCTestCase {
    private let speakers = AudioOutputDevice(objectID: 1, uid: "speakers", name: "Speakers", kind: .builtIn)
    private let headset = AudioOutputDevice(objectID: 2, uid: "headset", name: "Headset", kind: .usb)

    func testNativeBypassAndExplicitRoutesIncludingCurrentDefault() {
        let devices = [speakers, headset]
        XCTAssertFalse(MixerOutputResolution.resolve(entry: .init(), devices: devices, defaultUID: "speakers").needsTap)
        let route = MixerOutputResolution.resolve(entry: .init(outputUID: "headset"), devices: devices, defaultUID: "speakers")
        XCTAssertTrue(route.needsTap); XCTAssertEqual(route.effectiveUID, "headset"); XCTAssertFalse(route.preferredUnavailable)
        XCTAssertTrue(MixerOutputResolution.resolve(entry: .init(outputUID: "speakers"), devices: devices, defaultUID: "speakers").needsTap,
                      "An explicitly chosen output must override an app's own output selection too")
    }

    func testDisconnectFallsBackWithoutErasingPreferenceAndReconnectRestores() {
        let entry = VolumeMixerSettings.Entry(volume: 0.4, outputUID: "headset", outputName: "Headset")
        let missing = MixerOutputResolution.resolve(entry: entry, devices: [speakers], defaultUID: "speakers")
        XCTAssertEqual(missing.effectiveUID, "speakers"); XCTAssertTrue(missing.preferredUnavailable); XCTAssertTrue(missing.needsTap)
        let back = MixerOutputResolution.resolve(entry: entry, devices: [headset, speakers], defaultUID: "speakers")
        XCTAssertEqual(back.effectiveUID, "headset"); XCTAssertFalse(back.preferredUnavailable)
        XCTAssertEqual(entry.outputUID, "headset"); XCTAssertEqual(entry.volume, 0.4)
    }

    func testMissingDefaultIsNeverAnArbitraryDevice() {
        let absent = MixerOutputResolution.resolve(entry: .init(volume: 0.5), devices: [headset], defaultUID: "gone")
        XCTAssertNil(absent.effectiveUID); XCTAssertFalse(absent.needsTap)
        let explicit = MixerOutputResolution.resolve(entry: .init(outputUID: "headset"), devices: [headset], defaultUID: nil)
        XCTAssertEqual(explicit.effectiveUID, "headset"); XCTAssertTrue(explicit.needsTap)
    }

    func testOldPreferencesDecodeAndNewRouteRoundTrips() throws {
        let data = Data(#"{"entries":{"app":{"volume":0.3,"muted":true}}}"#.utf8)
        let old = try JSONDecoder().decode(VolumeMixerSettings.self, from: data)
        XCTAssertEqual(old.entry(for: "app").gain, 0); XCTAssertNil(old.entry(for: "app").outputUID)
        var settings = old
        settings.entries["app"] = .init(volume: 0.7, outputUID: "headset", outputName: "Headset")
        XCTAssertEqual(try JSONDecoder().decode(VolumeMixerSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertTrue(settings.hasActiveEntries)
    }

    func testCorruptEntryNumbersAndRouteBoundsAreSanitized() {
        XCTAssertEqual(VolumeMixerSettings.Entry(volume: .nan).gain, 1)
        XCTAssertEqual(VolumeMixerSettings.Entry(volume: -.infinity).volume, 1)
        XCTAssertNil(VolumeMixerSettings.Entry(outputUID: "").outputUID)
        XCTAssertNil(VolumeMixerSettings.Entry(outputUID: String(repeating: "x", count: 1025)).outputUID)
        XCTAssertNil(VolumeMixerSettings.Entry(outputName: "orphan").outputName)
        XCTAssertEqual(VolumeMixerSettings.Entry(outputUID: "x", outputName: String(repeating: "a", count: 300)).outputName?.count, 256)
    }

    func testLateBuildCannotCompleteOrRemoveItsReplacement() throws {
        var builds = MixerBuildRegistry()
        let old = try XCTUnwrap(builds.begin("app"))
        XCTAssertNil(builds.begin("app")); builds.invalidate("app")
        let new = try XCTUnwrap(builds.begin("app"))
        XCTAssertNotEqual(old, new); XCTAssertFalse(builds.finish("app", token: old)); XCTAssertTrue(builds.owns("app", token: new))
        XCTAssertEqual(builds.count, 1); XCTAssertTrue(builds.finish("app", token: new)); XCTAssertEqual(builds.count, 0)
        _ = builds.begin("app"); builds.invalidateAll(); XCTAssertEqual(builds.count, 0)
    }
}

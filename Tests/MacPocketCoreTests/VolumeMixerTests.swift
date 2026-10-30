import XCTest
@testable import MacPocketCore

final class AudioGainTests: XCTestCase {
    private func run(_ gain: Float, _ input: [Float], outputCount: Int? = nil) -> [Float] {
        var output = [Float](repeating: 9, count: outputCount ?? input.count)
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { AudioGain.apply(gain: gain, input: source, output: $0) }
        }
        return output
    }

    func testUnityAndAttenuation() {
        XCTAssertEqual(run(1, [0.5, -0.25]), [0.5, -0.25])
        XCTAssertEqual(run(0.5, [0.5, -0.25]), [0.25, -0.125])
        XCTAssertEqual(run(0, [0.5, -0.25]), [0, 0], "mute")
    }

    func testBoostIsSoftLimitedAndNeverClips() {
        let boosted = run(1.5, [0.4, 0.9, -1, 1])
        XCTAssertEqual(boosted[0], 0.6, accuracy: 0.0001, "below the knee: plain gain")
        for sample in boosted { XCTAssertLessThanOrEqual(abs(sample), 1) }
        XCTAssertGreaterThan(boosted[1], 0.8)
        XCTAssertEqual(boosted[2], -boosted[3], "symmetric")
    }

    func testExtraOutputIsSilencedAndShortOutputIsSafe() {
        XCTAssertEqual(run(1, [0.5], outputCount: 3), [0.5, 0, 0])
        XCTAssertEqual(run(1, [0.5, 0.5, 0.5], outputCount: 1), [0.5])
    }

    func testLimiterIsMonotonic() {
        var previous: Float = 0
        for step in 0...300 {
            let value = AudioGain.limit(Float(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
        XCTAssertLessThan(previous, 1)
    }
}

final class VolumeMixerSettingsTests: XCTestCase {
    func testEntriesClampAndNeutrality() {
        XCTAssertEqual(VolumeMixerSettings.Entry(volume: 4).volume, 1.5)
        XCTAssertTrue(VolumeMixerSettings.Entry().isNeutral)
        XCTAssertFalse(VolumeMixerSettings.Entry(volume: 1, muted: true).isNeutral)
        XCTAssertEqual(VolumeMixerSettings.Entry(volume: 0.7, muted: true).gain, 0)
        XCTAssertEqual(VolumeMixerSettings().entry(for: "unknown"), VolumeMixerSettings.Entry())
    }
}

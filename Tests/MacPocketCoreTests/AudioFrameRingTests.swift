import CoreAudio
import Synchronization
import XCTest
@testable import MacPocketCore

final class AudioFrameRingTests: XCTestCase {
    private func read(_ ring: AudioFrameRing, frames: Int, gain: Float = 1) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 9, count: frames), right = left
        left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in ring.read(left: l, right: r, gain: gain) } }
        return (left, right)
    }
    @discardableResult private func write(_ ring: AudioFrameRing, _ stereo: [Float]) -> Int {
        stereo.withUnsafeBufferPointer { ring.write($0) }
    }
    private func constant(frames: Int, value: Float = 0.5) -> [Float] {
        (0..<frames).flatMap { _ in [value, -value] }
    }

    func testPrimingSilenceAndInitiallyMutedAudioNeverLeaks() {
        let ring = AudioFrameRing(sampleRate: 48_000, capacity: 512, primeFrames: 64)
        XCTAssertEqual(read(ring, frames: 100).left, Array(repeating: 0, count: 100))
        write(ring, constant(frames: 32))
        XCTAssertEqual(read(ring, frames: 100).left, Array(repeating: 0, count: 100))
        write(ring, constant(frames: 128))
        let muted = read(ring, frames: 128, gain: 0)
        XCTAssertTrue(muted.left.allSatisfy { $0 == 0 })
        XCTAssertTrue(muted.right.allSatisfy { $0 == 0 })
    }

    func testStereoGainRampAndUnderrunTail() {
        let ring = AudioFrameRing(sampleRate: 48_000, capacity: 512, primeFrames: 64)
        write(ring, constant(frames: 256))
        let output = read(ring, frames: 400)
        XCTAssertGreaterThan(output.left[0], 0)
        XCTAssertLessThan(output.left[0], 0.01, "Start with a short fade")
        XCTAssertGreaterThan(output.left[100], output.left[0])
        for (l, r) in zip(output.left, output.right) { XCTAssertEqual(l, -r, accuracy: 0.00001) }
        XCTAssertTrue(output.left.suffix(100).allSatisfy { $0 == 0 })
        XCTAssertEqual(ring.counters.underruns, 1)
    }

    func testFullRingDropsNewFramesAndWrapsWithoutOverwritingUnreadAudio() {
        let ring = AudioFrameRing(sampleRate: 48_000, capacity: 64, primeFrames: 2)
        XCTAssertEqual(write(ring, constant(frames: 80, value: 0.25)), 64)
        XCTAssertEqual(ring.counters.dropped, 16)
        XCTAssertEqual(write(ring, constant(frames: 10, value: -0.75)), 0)
        XCTAssertEqual(ring.counters.dropped, 26)
        let old = read(ring, frames: 32)
        XCTAssertTrue(old.left.allSatisfy { $0 > 0 })
        XCTAssertGreaterThan(write(ring, constant(frames: 32, value: 0.5)), 0)
        let wrapped = read(ring, frames: 64)
        XCTAssertTrue(wrapped.left.allSatisfy { $0 >= 0 && $0 <= 0.5 })
        XCTAssertTrue(wrapped.right.allSatisfy { $0 <= 0 && $0 >= -0.5 })
    }

    func testNonfiniteAndExtremeInputsNeverReachOutput() {
        let ring = AudioFrameRing(sampleRate: .nan, capacity: .max, primeFrames: 2)
        XCTAssertEqual(ring.sampleRate, 48_000)
        XCTAssertEqual(ring.capacity, 262_144)
        write(ring, [.nan, .infinity, -.infinity, .nan] + constant(frames: 300, value: .greatestFiniteMagnitude))
        let result = read(ring, frames: 300, gain: 1.5)
        XCTAssertTrue((result.left + result.right).allSatisfy { $0.isFinite && abs($0) <= 1 })
        let gain = AudioRenderGain(.nan)
        XCTAssertEqual(gain.value, 1)
        gain.value = -.infinity
        XCTAssertEqual(gain.value, 1)
        gain.value = -2
        XCTAssertEqual(gain.value, 0)
        gain.value = 4
        XCTAssertEqual(gain.value, 1.5)
    }

    func testSustainedIndependentClockDriftStaysBounded() {
        for extra in [-1, 1] {
            let ring = AudioFrameRing(sampleRate: 48_000, capacity: 8_192, primeFrames: 1_024)
            write(ring, constant(frames: 1_024))
            for block in 0..<1_000 {
                write(ring, constant(frames: 256 + (block.isMultiple(of: 4) ? extra : 0)))
                let output = read(ring, frames: 256)
                XCTAssertGreaterThan(output.left[200], 0)
            }
            XCTAssertEqual(ring.counters.dropped, 0)
            XCTAssertEqual(ring.counters.underruns, 0)
        }
    }

    func testConcurrentProducerConsumerPreservesChannelsAndBounds() {
        let ring = AudioFrameRing(sampleRate: 48_000, capacity: 2_048, primeFrames: 64)
        let done = Atomic<Bool>(false), invalid = Atomic<Bool>(false)
        DispatchQueue.concurrentPerform(iterations: 2) { role in
            if role == 0 {
                let block: [Float] = (0..<128).flatMap { _ in [Float(0.5), Float(-0.5)] }
                for _ in 0..<2_000 { block.withUnsafeBufferPointer { _ = ring.write($0) } }
                done.store(true, ordering: .releasing)
            } else {
                var left = [Float](repeating: 0, count: 128), right = left
                var iterations = 0
                repeat {
                    left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in ring.read(left: l, right: r, gain: 1) } }
                    if zip(left, right).contains(where: { !$0.isFinite || abs($0) > 1 || abs($0 + $1) > 0.00001 }) {
                        invalid.store(true, ordering: .relaxed)
                    }
                    iterations += 1
                } while !done.load(ordering: .acquiring) || iterations < 2_100
            }
        }
        XCTAssertFalse(invalid.load(ordering: .relaxed))
        XCTAssertEqual(ring.counters.capture, 2_000)
        XCTAssertGreaterThanOrEqual(ring.counters.output, 2_100)
    }

    private func pcmFormat(bits: UInt32, bytes: UInt32, channels: UInt32 = 2, flags: AudioFormatFlags) -> AudioStreamBasicDescription {
        let perFrame = flags & kAudioFormatFlagIsNonInterleaved == 0 ? bytes * channels : bytes
        return .init(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
                     mBytesPerPacket: perFrame, mFramesPerPacket: 1, mBytesPerFrame: perFrame, mChannelsPerFrame: channels,
                     mBitsPerChannel: bits, mReserved: 0)
    }

    func testIntegerPCMEndiannessAnd24BitPadding() {
        for bits: UInt32 in [16, 24, 32] {
            for bytes in Set([bits / 8, UInt32(4)]) {
                for big in [false, true] {
                    for high in [false, true] {
                        let flags = kAudioFormatFlagIsSignedInteger | (big ? kAudioFormatFlagIsBigEndian : 0) | (high ? kAudioFormatFlagIsAlignedHigh : 0)
                        let format = pcmFormat(bits: bits, bytes: bytes, flags: flags)
                        var data: [UInt8] = []
                        let amplitude = UInt32(1) << (bits - 2)
                        for _ in 0..<300 {
                            for signed in [Int32(bitPattern: amplitude), -Int32(bitPattern: amplitude)] {
                                var value = UInt32(bitPattern: signed)
                                if high { value <<= bytes * 8 - bits }
                                let encoded = (0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
                                data += big ? encoded.reversed() : encoded
                            }
                        }
                        let ring = AudioFrameRing(sampleRate: 48_000, capacity: 512, primeFrames: 2)
                        data.withUnsafeMutableBytes { raw in
                            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                            ring.writePCM(&list, format: format)
                        }
                        let output = read(ring, frames: 280)
                        XCTAssertGreaterThan(output.left[250], 0.3, "bits=\(bits), bytes=\(bytes), big=\(big), high=\(high)")
                        XCTAssertEqual(output.left[250], -output.right[250], accuracy: 0.0001)
                    }
                }
            }
        }
    }

    func testPlanarFloatPCMAndMonoDuplication() {
        let ring = AudioFrameRing(sampleRate: 48_000, capacity: 512, primeFrames: 2)
        var left = [Float](repeating: 0.5, count: 300), right = [Float](repeating: -0.25, count: 300)
        left.withUnsafeMutableBytes { l in right.withUnsafeMutableBytes { r in
            let list = AudioBufferList.allocate(maximumBuffers: 2)
            defer { list.unsafeMutablePointer.deallocate() }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(l.count), mData: l.baseAddress)
            list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(r.count), mData: r.baseAddress)
            ring.writePCM(list.unsafePointer, format: pcmFormat(bits: 32, bytes: 4, flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved))
        } }
        let stereo = read(ring, frames: 280)
        XCTAssertEqual(stereo.left[250], -stereo.right[250] * 2, accuracy: 0.0001)
        let mono = AudioFrameRing(sampleRate: 48_000, capacity: 512, primeFrames: 2)
        var samples = [Double](repeating: 0.5, count: 300)
        samples.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            mono.writePCM(&list, format: pcmFormat(bits: 64, bytes: 8, channels: 1, flags: kAudioFormatFlagIsFloat))
        }
        let duplicated = read(mono, frames: 280)
        XCTAssertEqual(duplicated.left, duplicated.right)
        XCTAssertGreaterThan(duplicated.left[250], 0.3)
    }

    func testUnsupportedPCMIsRejectedBeforeBuffering() {
        var format = pcmFormat(bits: 32, bytes: 4, flags: kAudioFormatFlagIsFloat)
        XCTAssertTrue(AudioFrameRing.supportsPCM(format))
        format.mSampleRate = .infinity
        XCTAssertFalse(AudioFrameRing.supportsPCM(format))
        format.mSampleRate = 48_000
        format.mChannelsPerFrame = 8
        XCTAssertFalse(AudioFrameRing.supportsPCM(format))
        format.mChannelsPerFrame = 2
        format.mFormatFlags = 0
        XCTAssertFalse(AudioFrameRing.supportsPCM(format))
    }
}

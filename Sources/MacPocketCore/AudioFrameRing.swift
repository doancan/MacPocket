import CoreAudio
import Foundation
import Synchronization

/// Lock-free parameters for the render callback. A Float is transferred as an atomic bit pattern.
public final class AudioRenderGain: Sendable {
    private let bits: Atomic<UInt32>
    public init(_ value: Float) { bits = Atomic(value.isFinite ? min(1.5, max(0, value)).bitPattern : Float(1).bitPattern) }
    public var value: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store((newValue.isFinite ? min(1.5, max(0, newValue)) : 1).bitPattern, ordering: .relaxed) }
    }
}

/// Exactly one capture producer and one output consumer. Slots are published/released with acquire/release.
/// Storage is allocated before audio starts. No allocation, locks, logging, or system calls in the callbacks.
public final class AudioFrameRing: @unchecked Sendable {
    public let capacity: Int
    public let primeFrames: Int
    public let sampleRate: Double
    private let samples: UnsafeMutablePointer<Float>
    private let writePosition = Atomic<UInt64>(0)
    private let readPosition = Atomic<UInt64>(0)
    private let dropped = Atomic<UInt64>(0)
    private let captureCalls = Atomic<UInt64>(0)
    private let outputCalls = Atomic<UInt64>(0)
    private let underrunCount = Atomic<UInt64>(0)
    // Consumer-only state.
    private var primed = false
    private var fraction = 0.0
    private var ratio = 1.0
    private var currentGain: Float = 1

    public init(sampleRate: Double, capacity: Int = 16_384, primeFrames: Int? = nil) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? min(768_000, max(8_000, sampleRate)) : 48_000
        self.capacity = max(64, min(capacity, 262_144))
        self.primeFrames = max(2, min(primeFrames ?? Int(self.sampleRate * 0.025), self.capacity / 2))
        samples = .allocate(capacity: self.capacity * 2)
        samples.initialize(repeating: 0, count: self.capacity * 2)
    }
    deinit { samples.deinitialize(count: capacity * 2); samples.deallocate() }

    public var counters: (capture: UInt64, output: UInt64, dropped: UInt64, underruns: UInt64) {
        (captureCalls.load(ordering: .relaxed), outputCalls.load(ordering: .relaxed),
         dropped.load(ordering: .relaxed), underrunCount.load(ordering: .relaxed))
    }

    /// Canonical interleaved stereo, useful for producers already in Float32.
    @discardableResult public func write(_ stereo: UnsafeBufferPointer<Float>) -> Int {
        captureCalls.wrappingAdd(1, ordering: .relaxed)
        let write = writePosition.load(ordering: .relaxed)
        let read = readPosition.load(ordering: .acquiring)
        let requested = stereo.count / 2
        let count = min(requested, capacity - Int(write &- read))
        for frame in 0..<count {
            let offset = Int((write &+ UInt64(frame)) % UInt64(capacity)) * 2
            samples[offset] = stereo[frame * 2].isFinite ? stereo[frame * 2] : 0
            samples[offset + 1] = stereo[frame * 2 + 1].isFinite ? stereo[frame * 2 + 1] : 0
        }
        if count < requested { dropped.wrappingAdd(UInt64(requested - count), ordering: .relaxed) }
        writePosition.store(write &+ UInt64(count), ordering: .releasing)
        return count
    }

    /// Decode the tap's linear PCM format straight into the ring without temporary buffers.
    public func writePCM(_ buffers: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) {
        captureCalls.wrappingAdd(1, ordering: .relaxed)
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        guard Self.supportsPCM(format), !list.isEmpty,
              list.reduce(UInt32(0), { $0 + $1.mNumberChannels }) == format.mChannelsPerFrame,
              list.allSatisfy({ $0.mNumberChannels > 0 && $0.mData != nil }) else { return }
        let bytes = Int(format.mBytesPerFrame) / ((format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 ? 1 : max(1, Int(format.mChannelsPerFrame)))
        let requested = list.reduce(Int.max) { min($0, Int($1.mDataByteSize) / (bytes * Int($1.mNumberChannels))) }
        let write = writePosition.load(ordering: .relaxed), read = readPosition.load(ordering: .acquiring)
        let count = min(requested, capacity - Int(write &- read))
        for frame in 0..<count {
            let offset = Int((write &+ UInt64(frame)) % UInt64(capacity)) * 2
            samples[offset] = Self.pcmSample(list, channel: 0, frame: frame, bytes: bytes, format: format)
            samples[offset + 1] = Self.pcmSample(list, channel: min(1, Int(format.mChannelsPerFrame) - 1), frame: frame, bytes: bytes, format: format)
        }
        if count < requested { dropped.wrappingAdd(UInt64(requested - count), ordering: .relaxed) }
        writePosition.store(write &+ UInt64(count), ordering: .releasing)
    }

    public static func supportsPCM(_ format: AudioStreamBasicDescription) -> Bool {
        let channels = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 ? format.mChannelsPerFrame : 1
        let bytes = format.mBytesPerFrame / max(1, channels)
        return format.mFormatID == kAudioFormatLinearPCM && (1...2).contains(format.mChannelsPerFrame)
            && format.mSampleRate.isFinite && (8_000...768_000).contains(format.mSampleRate)
            && format.mBytesPerFrame == bytes * channels
            && ((format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && ((bytes == 4 && format.mBitsPerChannel == 32) || (bytes == 8 && format.mBitsPerChannel == 64)))
                || (format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && (2...4).contains(bytes)
                    && [16, 24, 32].contains(format.mBitsPerChannel) && format.mBitsPerChannel <= bytes * 8))
    }

    private static func pcmSample(_ buffers: UnsafeMutableAudioBufferListPointer, channel: Int, frame: Int, bytes: Int,
                                  format: AudioStreamBasicDescription) -> Float {
        var base = 0
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            defer { base += channels }
            guard channel < base + channels else { continue }
            let offset = (frame * channels + channel - base) * bytes
            guard let data = buffer.mData, offset >= 0, offset + bytes <= Int(buffer.mDataByteSize) else { return 0 }
            let big = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
            let value: Float
            if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                if bytes == 4 {
                    let bits = data.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                    value = Float(bitPattern: big ? bits.byteSwapped : bits)
                } else if bytes == 8 {
                    let bits = data.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                    value = Float(Double(bitPattern: big ? bits.byteSwapped : bits))
                } else { return 0 }
            } else {
                var bits: UInt32 = 0
                for index in 0..<min(bytes, 4) {
                    let byte = UInt32(data.load(fromByteOffset: offset + index, as: UInt8.self))
                    bits |= byte << UInt32((big ? bytes - index - 1 : index) * 8)
                }
                let width = Int(format.mBitsPerChannel)
                guard (1...32).contains(width), width <= bytes * 8 else { return 0 }
                if format.mFormatFlags & kAudioFormatFlagIsAlignedHigh != 0 { bits >>= UInt32(bytes * 8 - width) }
                let shifted = Int32(bitPattern: bits << UInt32(32 - width)) >> Int32(32 - width)
                value = Float(shifted) / Float(UInt64(1) << UInt64(width - 1))
            }
            return value.isFinite ? value : 0
        }
        return 0
    }

    /// Stereo noninterleaved output for AVAudioSourceNode. Tiny adaptive interpolation corrects independent
    /// device-clock drift; AVAudioEngine separately converts the nominal sample rate/channel layout.
    public func read(left: UnsafeMutableBufferPointer<Float>, right: UnsafeMutableBufferPointer<Float>, gain: Float, compensation: Float = 1) {
        outputCalls.wrappingAdd(1, ordering: .relaxed)
        let frames = min(left.count, right.count)
        left.update(repeating: 0)
        right.update(repeating: 0)
        var read = readPosition.load(ordering: .relaxed)
        var write = writePosition.load(ordering: .acquiring)
        if !primed {
            currentGain = 0
            guard write &- read >= UInt64(primeFrames) else { return }
            primed = true
            fraction = 0
        }
        let desired = 1 + min(0.002, max(-0.002, (Double(write &- read) - Double(primeFrames)) / (sampleRate * 4)))
        ratio += (desired - ratio) * 0.02
        let targetGain = gain.isFinite ? min(1.5, max(0, gain)) : 1
        let slew = Float(min(1, 1 / (sampleRate * 0.005)))
        for frame in 0..<frames {
            write = writePosition.load(ordering: .acquiring)
            guard write &- read >= 2 else { primed = false; fraction = 0; underrunCount.wrappingAdd(1, ordering: .relaxed); break }
            currentGain += (targetGain - currentGain) * slew
            let a = Int(read % UInt64(capacity)) * 2
            let b = Int((read &+ 1) % UInt64(capacity)) * 2
            let fraction = Float(fraction)
            let l = (samples[a] + (samples[b] - samples[a]) * fraction) * currentGain * compensation
            let r = (samples[a + 1] + (samples[b + 1] - samples[a + 1]) * fraction) * currentGain * compensation
            left[frame] = !l.isFinite ? 0 : ((currentGain > 1 || abs(l) > 1) ? AudioGain.limit(l) : l)
            right[frame] = !r.isFinite ? 0 : ((currentGain > 1 || abs(r) > 1) ? AudioGain.limit(r) : r)
            self.fraction += ratio
            let advance = UInt64(self.fraction)
            self.fraction -= Double(advance)
            read &+= advance
        }
        readPosition.store(read, ordering: .releasing)
    }
}

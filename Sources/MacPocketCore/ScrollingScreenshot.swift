import CoreGraphics
import Foundation

/// A bounded vertical panorama. Cropped strips own their pixels instead of retaining entire input frames.
/// Ambiguous/no-overlap frames never change the accepted image or the reference position.
public struct ScrollScreenshotStitcher: Sendable {
    public struct Limits: Sendable {
        public var pixels: Int
        public var height: Int
        public var sections: Int
        public init(pixels: Int = 40_000_000, height: Int = 60_000, sections: Int = 120) {
            self.pixels = max(1, min(80_000_000, pixels))
            self.height = max(1, min(100_000, height))
            self.sections = max(1, min(200, sections))
        }
    }
    public enum Update: Equatable, Sendable {
        case started, appended(pixels: Int), unchanged, revisited, unmatched, ambiguous, limitReached
    }
    public enum Failure: Error, LocalizedError, Sendable {
        case invalidFrame, sizeChanged, empty, allocation
        public var errorDescription: String? {
            switch self {
            case .invalidFrame: String(localized: "Kaydırmalı çekim alanı çok küçük veya çok büyük.")
            case .sizeChanged: String(localized: "Çekim alanının piksel boyutu değişti. Yeni bir çekim başlat.")
            case .empty: String(localized: "Birleştirilecek görüntü yok.")
            case .allocation: String(localized: "Ekran görüntüsü için yeterli bellek ayrılamadı.")
            }
        }
    }
    private let limits: Limits
    private var reference: Sample?
    private var first: CGImage?
    private var strips: [CGImage] = []
    private var footer: CGImage?
    private var referenceTop = 0
    private var coveredEnd = 0
    private var fixedTop = 0
    private var fixedBottom = 0
    private var establishedMargins = false
    public private(set) var width = 0
    public private(set) var height = 0
    public private(set) var sections = 0
    public init(limits: Limits = .init()) { self.limits = limits }

    /// Useful for waiting until a wheel/keyboard scroll has settled. No screen/event access is performed
    /// here.
    public static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height, let a = Sample(a), let b = Sample(b) else { return .infinity }
        var sum = 0, count = 0
        for y in stride(from: 0, to: a.height, by: max(1, a.height / 160)) {
            for x in 0..<a.width { sum += a.distance(to: b, ax: x, ay: y, bx: x, by: y); count += 3 }
        }
        return count == 0 ? .infinity : Double(sum) / Double(count)
    }

    public mutating func append(_ image: CGImage) throws -> Update {
        try Task.checkCancellation()
        guard image.width >= 32, image.height >= 64, image.height <= 16_384,
              image.width <= 16_384, image.width <= limits.pixels / image.height else { throw Failure.invalidFrame }
        guard let sample = Sample(image) else { throw Failure.allocation }
        guard let previous = reference else {
            width = image.width
            height = image.height
            sections = 1
            guard height <= limits.height else { throw Failure.invalidFrame }
            first = try Self.copy(image, rect: CGRect(x: 0, y: 0, width: width, height: height))
            reference = sample
            coveredEnd = height
            return .started
        }
        guard image.width == width, image.height == previous.height else { throw Failure.sizeChanged }
        let margins = establishedMargins ? (fixedTop, fixedBottom) : previous.stationaryMargins(sample)
        let match = try previous.match(sample, top: margins.0, bottom: margins.1)
        switch match {
        case .unchanged: return .unchanged
        case .unmatched: return .unmatched
        case .ambiguous: return .ambiguous
        case .offset(let offset):
            let top = referenceTop + offset
            let contentHeight = image.height - margins.0 - margins.1
            let end = top + contentHeight
            let currentEnd = establishedMargins ? coveredEnd : contentHeight
            let extra = max(0, end - currentEnd)
            let candidateHeight = height + extra
            if extra > 0, (sections >= limits.sections || candidateHeight > limits.height || width > limits.pixels / candidateHeight) { return .limitReached }
            if !establishedMargins {
                fixedTop = margins.0
                fixedBottom = margins.1
                coveredEnd = contentHeight
                establishedMargins = true
                guard let first else { throw Failure.empty }
                strips = [try Self.copy(first, rect: CGRect(x: 0, y: 0, width: width, height: first.height - fixedBottom))]
                if fixedBottom > 0 { footer = try Self.copy(first, rect: CGRect(x: 0, y: first.height - fixedBottom, width: width, height: fixedBottom)) }
                self.first = nil
            }
            if extra > 0 {
                guard extra <= contentHeight else { return .unmatched }
                let strip = try Self.copy(image, rect: CGRect(x: 0, y: image.height - fixedBottom - extra, width: width, height: extra))
                let newFooter = fixedBottom > 0 ? try Self.copy(image, rect: CGRect(x: 0, y: image.height - fixedBottom, width: width, height: fixedBottom)) : nil
                strips.append(strip)
                footer = newFooter
                coveredEnd = end
                height = candidateHeight
                sections += 1
            }
            reference = sample
            referenceTop = top
            return extra > 0 ? .appended(pixels: extra) : .revisited
        }
    }

    public func render() throws -> CGImage {
        try Task.checkCancellation()
        if let first { return first }
        guard !strips.isEmpty, width > 0, height > 0 else { throw Failure.empty }
        guard let context = Self.context(width: width, height: height) else { throw Failure.allocation }
        var remaining = height
        for strip in strips + (footer.map { [$0] } ?? []) {
            try Task.checkCancellation()
            remaining -= strip.height
            context.draw(strip, in: CGRect(x: 0, y: remaining, width: width, height: strip.height))
        }
        guard remaining == 0, let result = context.makeImage() else { throw Failure.allocation }
        return result
    }

    private static func copy(_ image: CGImage, rect: CGRect) throws -> CGImage {
        guard let crop = image.cropping(to: rect), let context = context(width: Int(rect.width), height: Int(rect.height)) else { throw Failure.allocation }
        context.draw(crop, in: CGRect(origin: .zero, size: rect.size))
        guard let copy = context.makeImage() else { throw Failure.allocation }
        return copy
    }
    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private enum Match { case offset(Int), unchanged, unmatched, ambiguous }
    private struct Sample: Sendable {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        init?(_ image: CGImage) {
            let w = min(96, image.width), h = image.height
            width = w
            height = h
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            bytes = pixels
        }
        @inline(__always) func distance(to b: Self, ax: Int, ay: Int, bx: Int, by: Int) -> Int {
            let a = (ay * width + ax) * 4, bIndex = (by * b.width + bx) * 4
            return abs(Int(bytes[a]) - Int(b.bytes[bIndex])) + abs(Int(bytes[a + 1]) - Int(b.bytes[bIndex + 1])) + abs(Int(bytes[a + 2]) - Int(b.bytes[bIndex + 2]))
        }
        func stationaryMargins(_ b: Self) -> (Int, Int) {
            func sameRow(_ y: Int) -> Bool {
                let sum = (2..<(width - 2)).reduce(0) { $0 + distance(to: b, ax: $1, ay: y, bx: $1, by: y) }
                return Double(sum) / Double((width - 4) * 3) < 1.5
            }
            var top = 0, bottom = 0
            while top < height / 4, sameRow(top) { top += 1 }
            while bottom < height / 5, sameRow(height - 1 - bottom) { bottom += 1 }
            return (top, bottom)
        }
        func match(_ b: Self, top: Int, bottom: Int) throws -> Match {
            let end = height - bottom, length = end - top
            let yStep = max(1, length / 120)
            let columns = (2..<(width - 2)).filter { x in
                var diff = 0, n = 0
                for y in stride(from: top, to: end, by: yStep) { diff += distance(to: b, ax: x, ay: y, bx: x, by: y); n += 3 }
                return diff > n
            }
            if columns.isEmpty { return .unchanged }
            if columns.count < 2 { return .unmatched }
            func hash(_ sample: Self, row: Int) -> (UInt64, Bool) {
                var hash: UInt64 = 14_695_981_039_346_656_037, low = 255, high = 0
                for x in columns {
                    let i = (row * width + x) * 4
                    for c in 0..<3 {
                        let value = sample.bytes[i + c]
                        low = min(low, Int(value))
                        high = max(high, Int(value))
                        hash = (hash ^ UInt64(value >> 3)) &* 1_099_511_628_211
                    }
                }
                return (hash, high - low > 16)
            }
            let aRows = (top..<end).map { hash(self, row: $0) }
            let bRows = (top..<end).map { hash(b, row: $0) }
            var rowsByHash: [UInt64: [Int]] = [:]
            for y in top..<end {
                let (value, detailed) = aRows[y - top]
                if detailed, rowsByHash[value, default: []].count < 16 { rowsByHash[value, default: []].append(y) }
            }
            var votes: [Int: Int] = [:]
            for y in top..<end {
                let (value, detailed) = bRows[y - top]
                if detailed, let matches = rowsByHash[value] {
                    for old in matches { let offset = old - y; if abs(offset) < length * 4 / 5 { votes[offset, default: 0] += 1 } }
                }
            }
            let minOverlap = max(32, length / 5)
            func score(_ offset: Int) -> Double {
                let start = max(top, top - offset), finish = min(end, end - offset)
                guard finish - start >= minOverlap else { return .infinity }
                var sum = 0, samples = 0, detailedRows = 0
                for y in stride(from: start, to: finish, by: max(1, (finish - start) / 120)) {
                    let aDetail = aRows[y + offset - top].1, bDetail = bRows[y - top].1
                    guard aDetail || bDetail else { continue }
                    detailedRows += 1
                    for x in columns { sum += distance(to: b, ax: x, ay: y + offset, bx: x, by: y); samples += 3 }
                }
                guard detailedRows >= 5, samples >= 128 else { return .infinity }
                return Double(sum) / Double(samples)
            }
            var candidates = Set(votes.sorted { $0.value > $1.value }.prefix(18).map(\.key))
            candidates.insert(0)
            if candidates.count < 3 {
                let step = max(1, length / 128)
                var coarse: [(Int, Double)] = []
                for d in stride(from: -length * 4 / 5, through: length * 4 / 5, by: step) {
                    try Task.checkCancellation()
                    coarse.append((d, score(d)))
                }
                for (d, _) in coarse.sorted(by: { $0.1 < $1.1 }).prefix(6) {
                    for refined in (d - step)...(d + step) where abs(refined) < length * 4 / 5 { candidates.insert(refined) }
                }
            }
            var ranked: [(Int, Double)] = []
            for offset in candidates { try Task.checkCancellation(); ranked.append((offset, score(offset))) }
            ranked.sort { $0.1 == $1.1 ? abs($0.0) < abs($1.0) : $0.1 < $1.1 }
            guard let best = ranked.first, best.1 < 10 else { return .unmatched }
            if let alternate = ranked.first(where: { abs($0.0 - best.0) > 3 }), alternate.1 - best.1 < max(0.8, best.1 * 0.2) { return .ambiguous }
            if best.0 != 0 {
                // A textured fixed sidebar cannot be silently repeated in the long image. Flat margins are
                // safe.
                let stable = Set(2..<(width - 2)).subtracting(columns)
                let from = max(top, top - best.0), to = min(end, end - best.0)
                for x in stable {
                    var sum = 0, n = 0
                    for y in stride(from: from, to: to, by: max(1, (to - from) / 80)) {
                        sum += distance(to: b, ax: x, ay: y + best.0, bx: x, by: y)
                        n += 3
                    }
                    if n > 0 && Double(sum) / Double(n) > 5 { return .unmatched }
                }
            }
            return best.0 == 0 ? .unchanged : .offset(best.0)
        }
    }
}

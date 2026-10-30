import CoreGraphics
import Foundation
import Vision

/// Text and codes read from an image, on the device (Vision), never sent anywhere.
public enum ScreenTextReader {
    public struct Line: Equatable, Sendable {
        public let text: String
        /// Normalized, origin bottom-left (Vision's convention).
        public let box: CGRect

        public init(text: String, box: CGRect) { self.text = text; self.box = box }
    }

    /// Reading order: top to bottom; fragments on the same visual row are joined left to right with a space.
    public static func arrange(_ lines: [Line]) -> String {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Line]] = []
        for line in sorted {
            // Same row when the vertical centers are within half a line height.
            if let last = rows.last?.first, abs(last.box.midY - line.box.midY) < max(last.box.height, line.box.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }

    /// Recognizes text in Turkish and English (plus the system's other supported languages as fallback).
    public static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["tr-TR", "en-US"].filter(supported.contains)
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> Line? in
            observation.topCandidates(1).first.map { Line(text: $0.string, box: observation.boundingBox) }
        }
        return arrange(lines)
    }

    /// QR codes and other barcodes' contents.
    public static func codes(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        var seen = Set<String>()
        return (request.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
    }
}

/// A picked color in the formats people paste into code and design tools.
public struct PickedColor: Equatable, Sendable {
    /// sRGB components, 0…1.
    public let red: Double, green: Double, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1); self.green = min(max(green, 0), 1); self.blue = min(max(blue, 0), 1)
    }

    public enum Format: String, CaseIterable, Codable, Sendable { case hex, rgb, hsl, swiftUI }

    private func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }

    public func formatted(_ format: Format) -> String {
        switch format {
        case .hex: String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        case .rgb: "rgb(\(byte(red)), \(byte(green)), \(byte(blue)))"
        case .hsl: hslText
        case .swiftUI:
            "Color(red: \(Self.short(red)), green: \(Self.short(green)), blue: \(Self.short(blue)))"
        }
    }

    private var hslText: String {
        let (hue, saturation, lightness) = hsl
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    private static func short(_ value: Double) -> String {
        String(format: "%.3f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    /// Hue in degrees, saturation and lightness 0…1.
    public var hsl: (Double, Double, Double) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maximum {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }
}

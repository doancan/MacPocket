import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Settings

/// What a screenshot shortcut captures.
public enum ScreenshotMode: String, Codable, CaseIterable, Sendable {
    /// Area selection with the mode bar (Area / Window / Fullscreen / Previous area).
    case allInOne
    case area, window, fullscreen, previousArea, scrolling
}

public enum ScreenshotFormat: String, Codable, CaseIterable, Sendable {
    case png, jpg, heic

    public var fileExtension: String { rawValue }
    public var typeIdentifier: CFString {
        switch self {
        case .png: UTType.png.identifier as CFString
        case .jpg: UTType.jpeg.identifier as CFString
        case .heic: UTType.heic.identifier as CFString
        }
    }
    /// JPEG has no alpha: transparent window shadows are flattened onto white.
    public var supportsTransparency: Bool { self != .jpg }
}

public struct ScreenshotSettings: Codable, Equatable, Sendable {
    public var format = ScreenshotFormat.png
    /// 0…1, used for JPEG and HEIC.
    public var quality = 0.9
    /// Folder path; nil saves to the Desktop.
    public var folder: String?
    public var saveToFolder = true
    public var copyToClipboard = true
    public var showOverlay = true
    /// The preview card closes once dragged into another app.
    public var closeOverlayAfterDrag = true
    /// Seconds before the preview card closes by itself; nil keeps it until closed.
    public var overlayAutoClose: Int?
    public var playSound = true
    public var shortcuts: [ScreenshotMode: KeyCombo] = [
        .fullscreen: KeyCombo(keyCode: 20, modifiers: [.command, .shift]), // ⇧⌘3
        .area: KeyCombo(keyCode: 21, modifiers: [.command, .shift]), // ⇧⌘4
        .allInOne: KeyCombo(keyCode: 23, modifiers: [.command, .shift]), // ⇧⌘5
    ]

    public static let autoCloseChoices: [Int?] = [nil, 5, 10, 30]
    public static let storageKey = "MacPocket.screenshot.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> ScreenshotSettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ScreenshotSettings.self, from: $0) } ?? ScreenshotSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

// MARK: - Files

public enum ScreenshotFiles {
    /// "Ekran Resmi 2026-11-03 08.43.12.png"-style name, never overwriting an existing file.
    public static func url(in folder: URL, at date: Date, prefix: String, format: ScreenshotFormat, exists: (URL) -> Bool) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "\(prefix) \(formatter.string(from: date))"
        var candidate = folder.appendingPathComponent("\(base).\(format.fileExtension)")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) (\(counter)).\(format.fileExtension)")
            counter += 1
        }
        return candidate
    }
}

// MARK: - Geometry

public enum ScreenshotGeometry {
    /// The rectangle spanned by a drag, whichever corner it started from.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// A selection in screen points (origin top-left of the screen) as whole pixels of that screen's image,
    /// clamped to the image. Nil when nothing of at least one pixel remains.
    public static func pixelRect(_ selection: CGRect, scale: CGFloat, imageSize: CGSize) -> CGRect? {
        let scaled = CGRect(x: selection.minX * scale, y: selection.minY * scale, width: selection.width * scale, height: selection.height * scale)
        let integral = CGRect(x: scaled.minX.rounded(), y: scaled.minY.rounded(),
                              width: scaled.width.rounded(), height: scaled.height.rounded())
        let clamped = integral.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return clamped
    }

    /// "1280 × 720" in pixels.
    public static func sizeLabel(_ selection: CGRect, scale: CGFloat) -> String {
        "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
    }
}

// MARK: - Encoding

public enum ScreenshotEncoder {
    public enum Failure: Error { case encode }

    /// The image in the chosen format; JPEG is flattened onto white first.
    public static func encode(_ image: CGImage, as format: ScreenshotFormat, quality: Double = 0.9, scale: Double = 1) throws -> Data {
        let source = format.supportsTransparency ? image : flattened(image) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier, 1, nil) else { throw Failure.encode }
        let scale = scale.isFinite && scale > 0 ? min(8, scale) : 1
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        if format != .png { properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, quality)) }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encode }
        return data as Data
    }

    static func flattened(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }
}

// MARK: - History

public struct ScreenshotHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    public var date: Date
    public var mode: ScreenshotMode
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: UUID = UUID(), path: String, date: Date, mode: ScreenshotMode, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.path = path
        self.date = date
        self.mode = mode
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Recent captures, newest first: at most `limit` entries from the last `maximumAge`, only while the file
/// exists.
public struct ScreenshotHistory: Codable, Equatable, Sendable {
    public static let limit = 200
    public static let maximumAge: TimeInterval = 30 * 24 * 3600

    public private(set) var entries: [ScreenshotHistoryEntry] = []

    public init(entries: [ScreenshotHistoryEntry] = []) { self.entries = entries }

    public mutating func add(_ entry: ScreenshotHistoryEntry) {
        entries.removeAll { $0.path == entry.path }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    /// Drops entries older than the maximum age or whose file is gone.
    public mutating func prune(now: Date, exists: (String) -> Bool) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.maximumAge || !exists($0.path) }
    }
}

// MARK: - Annotations

/// sRGB color with alpha, 0…1.
public struct AnnotationColor: Codable, Equatable, Hashable, Sendable {
    public var red, green, blue, alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public static let red = AnnotationColor(red: 1, green: 0.23, blue: 0.19)
    public static let yellow = AnnotationColor(red: 1, green: 0.84, blue: 0.04)
    public static let green = AnnotationColor(red: 0.2, green: 0.78, blue: 0.35)
    public static let blue = AnnotationColor(red: 0.04, green: 0.52, blue: 1)
    public static let purple = AnnotationColor(red: 0.69, green: 0.32, blue: 0.87)
    public static let white = AnnotationColor(red: 1, green: 1, blue: 1)
    public static let black = AnnotationColor(red: 0, green: 0, blue: 0)
    public static let palette: [AnnotationColor] = [.red, .yellow, .green, .blue, .purple, .white, .black]
}

/// One editor layer, in image pixels with the origin at the top left.
public enum Annotation: Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint, color: AnnotationColor, width: Double)
    case highlight(CGRect, color: AnnotationColor)
    case pixelate(CGRect, block: Double)
    case text(String, at: CGPoint, color: AnnotationColor, size: Double)

    /// The arrowhead's length and half width for a stroke width.
    public static func arrowHead(width: Double) -> (length: Double, halfWidth: Double) { (max(14, width * 4.2), max(8, width * 2.6)) }
}

public enum AnnotationRenderer {
    /// The image with every layer drawn in order, at the image's own resolution.
    public static func render(_ image: CGImage, annotations: [Annotation]) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        // Work in top-left coordinates like the editor.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for annotation in annotations {
            switch annotation {
            case let .pixelate(rect, block):
                // Read from what is drawn so far, so pixelating a highlighted area keeps the highlight.
                if let current = context.makeImage() { pixelate(rect.standardized, block: block, source: current, in: context, height: height) }
            case let .highlight(rect, color):
                context.saveGState()
                context.setBlendMode(.multiply)
                context.setFillColor(AnnotationColor(red: color.red, green: color.green, blue: color.blue, alpha: 0.45).cgColor)
                context.fill(rect.standardized)
                context.restoreGState()
            case let .arrow(from, to, color, width):
                drawArrow(from: from, to: to, color: color, width: width, in: context)
            case let .text(string, origin, color, size):
                drawText(string, at: origin, color: color, size: size, in: context)
            }
        }
        return context.makeImage()
    }

    private static func pixelate(_ rect: CGRect, block: Double, source: CGImage, in context: CGContext, height: Int) {
        let area = rect.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height)).integral
        guard area.width >= 1, area.height >= 1, let crop = source.cropping(to: area) else { return }
        let block = max(2, block)
        let smallWidth = max(1, Int((area.width / block).rounded())), smallHeight = max(1, Int((area.height / block).rounded()))
        guard let small = CGContext(data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let reduced = small.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        // The context is flipped; draw the (unflipped) bitmap upright.
        context.translateBy(x: area.minX, y: area.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(reduced, in: CGRect(x: 0, y: 0, width: area.width, height: area.height))
        context.restoreGState()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, color: AnnotationColor, width: Double, in context: CGContext) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let head = Annotation.arrowHead(width: width)
        let headLength = min(head.length, length * 0.6)
        let ux = dx / length, uy = dy / length
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: CGColor(gray: 0, alpha: 0.35))
        context.move(to: from)
        context.addLine(to: base)
        context.strokePath()
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x - uy * head.halfWidth, y: base.y + ux * head.halfWidth))
        context.addLine(to: CGPoint(x: base.x + uy * head.halfWidth, y: base.y - ux * head.halfWidth))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private static func drawText(_ string: String, at origin: CGPoint, color: AnnotationColor, size: Double, in context: CGContext) {
        guard !string.isEmpty else { return }
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: CGColor(gray: 0, alpha: 0.4))
        for (index, line) in string.components(separatedBy: "\n").enumerated() {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            let baseline = origin.y + CTFontGetAscent(font) + CGFloat(index) * lineHeight
            context.saveGState()
            // CoreText draws upright in an unflipped space: flip around the baseline.
            context.translateBy(x: origin.x, y: baseline)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
        context.restoreGState()
    }
}

// MARK: - Shortcut conflicts

/// macOS's own screenshot shortcuts (System Settings → Keyboard Shortcuts → Screenshots). Another app holding
/// the same keys isn't reported by `RegisterEventHotKey`, so conflicts are looked up instead.
public enum ScreenshotShortcutConflicts {
    /// Symbolic hot key IDs and their default keys: 28 ⇧⌘3, 29 ⌃⇧⌘3, 30 ⇧⌘4, 31 ⌃⇧⌘4, 184 ⇧⌘5.
    public static let systemShortcuts: [Int: KeyCombo] = [
        28: KeyCombo(keyCode: 20, modifiers: [.command, .shift]),
        29: KeyCombo(keyCode: 20, modifiers: [.command, .shift, .control]),
        30: KeyCombo(keyCode: 21, modifiers: [.command, .shift]),
        31: KeyCombo(keyCode: 21, modifiers: [.command, .shift, .control]),
        184: KeyCombo(keyCode: 23, modifiers: [.command, .shift]),
    ]

    /// Modes whose shortcut equals an enabled macOS screenshot shortcut. `symbolicHotKeys` is the
    /// `AppleSymbolicHotKeys` dictionary of `com.apple.symbolichotkeys`; a missing entry counts as enabled
    /// (the default).
    public static func system(_ shortcuts: [ScreenshotMode: KeyCombo], symbolicHotKeys: [String: Any]?) -> Set<ScreenshotMode> {
        let enabled = systemShortcuts.filter { id, _ in
            guard let entry = symbolicHotKeys?[String(id)] as? [String: Any] else { return true }
            return (entry["enabled"] as? NSNumber)?.boolValue ?? (entry["enabled"] as? Bool) ?? true
        }.map(\.value)
        return Set(shortcuts.compactMap { mode, combo in enabled.contains(combo) ? mode : nil })
    }

    /// Default keys of screenshot apps that take over ⇧⌘3/4/5 while running (bundle ID prefix → app name).
    public static let knownApps: [String: String] = ["com.getcleanshot.app": "CleanShot X", "pl.maketheweb.cleanshotx": "CleanShot X"]

    public static func runningApp(bundleIDs: [String]) -> String? {
        for id in bundleIDs { if let match = knownApps.first(where: { id.hasPrefix($0.key) }) { return match.value } }
        return nil
    }
}

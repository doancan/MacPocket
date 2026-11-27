// Native, deterministic artwork for the Finder installer; the two draggable icons belong to Finder.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else { fatalError("Usage: render-installer <repository> <output-directory> <app>") }
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let app = URL(fileURLWithPath: arguments[3]).path
let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")!
let version = info["CFBundleShortVersionString"] as! String
let minimum = info["LSMinimumSystemVersion"] as! String
let englishURL = root.appendingPathComponent("Resources/en.lproj/Localizable.strings")
let english = try PropertyListSerialization.propertyList(from: Data(contentsOf: englishURL), format: nil) as! [String: String]

// English leads and Turkish follows in smaller type: both are drawn because a Finder background cannot change language.
// Everything essential sits in the top 424 pt; a Finder with its path bar and status bar on hides the rest.
let heading = "MacPocket’ı yükle"
let instruction = "MacPocket’ı Uygulamalar klasörüne sürükle."
let completion = "Ardından Uygulamalar’dan açıp bu diski çıkarabilirsin."
for key in [heading, instruction, completion] {
    guard english[key] != nil else { fatalError("Missing installer translation: \(key)") }
}

let width: CGFloat = 720
let height: CGFloat = 480
let ink = NSColor(srgbRed: 0.10, green: 0.14, blue: 0.22, alpha: 1)
let secondary = NSColor(srgbRed: 0.34, green: 0.39, blue: 0.47, alpha: 1)
let accent = NSColor(srgbRed: 0.02, green: 0.31, blue: 0.98, alpha: 1)

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: height - y - h, width: w, height: h)
}

func text(_ value: String, x: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor = ink, centered: Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = centered ? .center : .left
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: value, attributes: attributes)
    let needed = attributed.boundingRect(with: CGSize(width: w, height: 100), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    guard needed <= size * 1.6 else { fatalError("Installer copy overflows: \(value)") }
    attributed.draw(in: rect(x, y, w, ceil(size * 1.6)))
}

func render(scale: Int, preview: Bool) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
        pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = CGSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    NSColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()

    accent.setFill()
    NSBezierPath(roundedRect: rect(44, 38, 4, 60), xRadius: 2, yRadius: 2).fill()
    text(english[heading]!, x: 64, y: 36, w: 500, size: 31, weight: .semibold)
    text(heading, x: 65, y: 78, w: 500, size: 17, color: secondary)
    text(version, x: 595, y: 48, w: 80, size: 13, weight: .medium, color: secondary, centered: true)

    // These cards align with the real Finder icons at (200, 212) and (520, 212) and enclose the icon and its label,
    // so Finder's label never meets the card's edge.
    for x: CGFloat in [126, 446] {
        NSColor.white.setFill()
        let pad = NSBezierPath(roundedRect: rect(x, 138, 148, 168), xRadius: 30, yRadius: 30)
        pad.fill()
        NSColor(srgbRed: 0.86, green: 0.89, blue: 0.94, alpha: 1).setStroke()
        pad.lineWidth = 1
        pad.stroke()
    }
    accent.withAlphaComponent(0.09).setFill()
    NSBezierPath(ovalIn: rect(336, 188, 48, 48)).fill()
    accent.setStroke()
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 349, y: height - 212))
    arrow.line(to: CGPoint(x: 371, y: height - 212))
    arrow.move(to: CGPoint(x: 363, y: height - 204))
    arrow.line(to: CGPoint(x: 371, y: height - 212))
    arrow.line(to: CGPoint(x: 363, y: height - 220))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()

    text(english[instruction]!, x: 40, y: 322, w: 640, size: 17, weight: .medium, centered: true)
    text(instruction, x: 40, y: 351, w: 640, size: 14, color: secondary, centered: true)
    NSColor(srgbRed: 0.86, green: 0.89, blue: 0.94, alpha: 1).setFill()
    NSBezierPath(rect: rect(44, 374, 632, 1)).fill()
    text(english[completion]!, x: 44, y: 382, w: 632, size: 12, color: secondary)
    text(completion, x: 44, y: 400, w: 632, size: 11, color: secondary)

    text("macOS \(minimum) · Apple Silicon", x: 44, y: 106, w: 632, size: 12, color: secondary)
    if preview {
        NSWorkspace.shared.icon(forFile: app).draw(in: rect(144, 156, 112, 112))
        NSWorkspace.shared.icon(forFile: "/Applications").draw(in: rect(464, 156, 112, 112))
        text("MacPocket", x: 120, y: 280, w: 160, size: 13, centered: true)
        text("Applications", x: 440, y: 280, w: 160, size: 13, centered: true)
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let background = NSImage(size: CGSize(width: width, height: height))
background.addRepresentation(render(scale: 1, preview: false))
background.addRepresentation(render(scale: 2, preview: false))
guard let tiff = background.tiffRepresentation else { fatalError("Cannot encode installer background") }
try tiff.write(to: output.appendingPathComponent("background.tiff"))
let preview = render(scale: 2, preview: true)
try preview.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("preview.png"))

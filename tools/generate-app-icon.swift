import AppKit
import Foundation

// Render the same vector at every icon size; no screenshots or external assets.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let outline = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
                               xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.31, blue: 0.72, alpha: 1),
               ending: NSColor(srgbRed: 0.25, green: 0.62, blue: 0.96, alpha: 1))!
        .draw(in: outline, angle: 80)
    let rim = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876),
                          xRadius: 194, yRadius: 194)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    rim.lineWidth = 3
    rim.stroke()
    let pocket = NSBezierPath()
    pocket.move(to: NSPoint(x: 270, y: 700))
    pocket.line(to: NSPoint(x: 754, y: 700))
    pocket.line(to: NSPoint(x: 754, y: 430))
    pocket.curve(to: NSPoint(x: 512, y: 266), controlPoint1: NSPoint(x: 754, y: 342), controlPoint2: NSPoint(x: 614, y: 282))
    pocket.curve(to: NSPoint(x: 270, y: 430), controlPoint1: NSPoint(x: 410, y: 282), controlPoint2: NSPoint(x: 270, y: 342))
    pocket.close()
    NSColor.white.withAlphaComponent(0.08).setFill()
    pocket.fill()
    NSColor.white.setStroke()
    pocket.lineWidth = 36
    pocket.lineJoinStyle = .round
    pocket.stroke()
    let waveform = NSBezierPath()
    waveform.move(to: NSPoint(x: 338, y: 494))
    waveform.line(to: NSPoint(x: 398, y: 494))
    waveform.line(to: NSPoint(x: 447, y: 588))
    waveform.line(to: NSPoint(x: 511, y: 392))
    waveform.line(to: NSPoint(x: 566, y: 544))
    waveform.line(to: NSPoint(x: 611, y: 494))
    waveform.line(to: NSPoint(x: 686, y: 494))
    waveform.lineWidth = 30
    waveform.lineJoinStyle = .round
    waveform.lineCapStyle = .round
    waveform.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}

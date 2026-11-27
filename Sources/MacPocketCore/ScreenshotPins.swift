import CoreGraphics
import Foundation

public enum ScreenshotPinPolicy {
    public static let maximumCount = 8
    public static let maximumPixels = 48_000_000
    public static func allows(width: Int, height: Int, count: Int, usedPixels: Int) -> Bool {
        width > 0 && height > 0 && count >= 0 && count < maximumCount && usedPixels >= 0
            && usedPixels < maximumPixels && width <= (maximumPixels - usedPixels) / height
    }
    /// AppKit coordinates, including displays above/left of the main display. Never assumes a 2× source.
    public static func frame(pixels: CGSize, scale: CGFloat, visible: CGRect, anchor: CGPoint) -> CGRect {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let area = visible.insetBy(dx: 12, dy: 12)
        let w = pixels.width.isFinite && pixels.width > 0 ? pixels.width / scale : 320
        let h = pixels.height.isFinite && pixels.height > 0 ? pixels.height / scale : 240
        let limitW = max(1, min(640, area.width)), limitH = max(1, min(560, area.height))
        let fit = min(1, limitW / w, max(1, limitH - 92) / h)
        let size = CGSize(width: min(limitW, max(280, w * fit)), height: min(limitH, max(220, h * fit + 92)))
        let x = anchor.x.isFinite ? anchor.x : area.midX, y = anchor.y.isFinite ? anchor.y : area.midY
        return CGRect(x: max(area.minX, min(x - size.width / 2, area.maxX - size.width)),
                      y: max(area.minY, min(y - size.height / 2, area.maxY - size.height)), width: size.width, height: size.height)
    }
}

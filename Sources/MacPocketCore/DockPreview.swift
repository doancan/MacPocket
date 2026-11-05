import CoreGraphics
import Foundation

public enum DockEdge: String, Codable, CaseIterable, Sendable { case bottom, left, right }

public struct DockPreviewSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var thumbnails = true
    public var live = true
    public var currentSpaceOnly = false
    public var hoverDelayMilliseconds = 350
    public var hideDelayMilliseconds = 300
    public var excludedPaths: [String] = []
    public static let storageKey = "MacPocket.dockPreview.settings"
    public init() {}
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey), var settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        settings.hoverDelayMilliseconds = min(1200, max(100, settings.hoverDelayMilliseconds))
        settings.hideDelayMilliseconds = min(1200, max(100, settings.hideDelayMilliseconds))
        settings.excludedPaths = Array(Set(settings.excludedPaths.filter { $0.hasPrefix("/") && $0.utf8.count <= 16_384 })).sorted().prefix(500).map { $0 }
        return settings
    }
    public func save(to defaults: UserDefaults = .standard) { defaults.set(try? JSONEncoder().encode(self), forKey: Self.storageKey) }
}

public struct DockPreviewLayout: Equatable, Sendable {
    public let frame: CGRect
    public let columns: Int
    public let cardSize: CGSize
    public static let padding: CGFloat = 12
    public static let spacing: CGFloat = 10
    public static let chromeHeight: CGFloat = 116

    /// AppKit global coordinates. The screen may have a negative origin or sit above the primary display.
    public static func compute(count: Int, icon: CGRect, visibleFrame: CGRect, edge: DockEdge) -> Self {
        let area = visibleFrame.insetBy(dx: 10, dy: 10)
        let width = max(100, min(720, area.width))
        let columns = max(1, min(3, min(max(1, count), Int((width - 2 * padding + spacing) / (210 + spacing)))))
        let cardWidth = min(columns == 1 ? 320 : 210, max(80, (width - 2 * padding - 4 - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
        let cardSize = CGSize(width: cardWidth, height: 176)
        let rows = ceil(CGFloat(max(1, min(count, 80))) / CGFloat(columns))
        let panelWidth = min(area.width, 2 * padding + 4 + CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing)
        let panelHeight = min(max(100, area.height), min(600, chromeHeight + rows * cardSize.height + max(0, rows - 1) * spacing))
        let origin: CGPoint
        switch edge {
        case .bottom: origin = CGPoint(x: icon.midX - panelWidth / 2, y: icon.maxY + 10)
        case .left: origin = CGPoint(x: icon.maxX + 10, y: icon.midY - panelHeight / 2)
        case .right: origin = CGPoint(x: icon.minX - panelWidth - 10, y: icon.midY - panelHeight / 2)
        }
        let frame = CGRect(x: max(area.minX, min(origin.x, area.maxX - panelWidth)),
                           y: max(area.minY, min(origin.y, area.maxY - panelHeight)), width: panelWidth, height: panelHeight)
        return Self(frame: frame, columns: columns, cardSize: cardSize)
    }
}

public enum DockPreviewGeometry {
    /// The bridge remains valid when an auto-hidden Dock retracts while the pointer enters the preview.
    public static func keepsOpen(point: CGPoint, icon: CGRect, panel: CGRect, edge: DockEdge) -> Bool {
        guard point.x.isFinite, point.y.isFinite, icon.width > 0, panel.width > 0 else { return false }
        let icon = icon.insetBy(dx: -6, dy: -6)
        let panel = panel.insetBy(dx: -6, dy: -6)
        if icon.contains(point) || panel.contains(point) { return true }
        let corners: [CGPoint]
        switch edge {
        case .bottom:
            corners = [CGPoint(x: icon.minX, y: icon.maxY), CGPoint(x: icon.maxX, y: icon.maxY),
                       CGPoint(x: panel.maxX, y: panel.minY), CGPoint(x: panel.minX, y: panel.minY)]
        case .left:
            corners = [CGPoint(x: icon.maxX, y: icon.minY), CGPoint(x: panel.minX, y: panel.minY),
                       CGPoint(x: panel.minX, y: panel.maxY), CGPoint(x: icon.maxX, y: icon.maxY)]
        case .right:
            corners = [CGPoint(x: panel.maxX, y: panel.minY), CGPoint(x: icon.minX, y: icon.minY),
                       CGPoint(x: icon.minX, y: icon.maxY), CGPoint(x: panel.maxX, y: panel.maxY)]
        }
        var sign: CGFloat = 0
        guard let minX = corners.map(\.x).min(), let maxX = corners.map(\.x).max(),
              let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max(),
              (minX...maxX).contains(point.x), (minY...maxY).contains(point.y) else { return false }
        for index in corners.indices {
            let a = corners[index], b = corners[(index + 1) % corners.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) < 0.001 { continue }
            if sign != 0, (cross > 0) != (sign > 0) { return false }
            sign = cross
        }
        return true
    }

    public static func nearDock(_ point: CGPoint, screen: CGRect, edge: DockEdge) -> Bool {
        guard screen.contains(point) else { return false }
        switch edge {
        case .bottom: return point.y <= screen.minY + 220
        case .left: return point.x <= screen.minX + 220
        case .right: return point.x >= screen.maxX - 220
        }
    }
}

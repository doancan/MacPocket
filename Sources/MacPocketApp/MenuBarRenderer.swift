import AppKit
import MacPocketCore
import SwiftUI

// MARK: - History

/// One menu bar sample. Values the snapshot could not provide yet stay nil.
struct MenuBarSample: Identifiable, Sendable {
    let date: Date
    let cpuUser: Double?
    let cpuSystem: Double?
    let memoryFraction: Double?
    let memoryPressure: Double?
    let networkDown: Double?
    let networkUp: Double?
    let diskRead: Double?
    let diskWrite: Double?
    let battery: Double?
    var id: Date { date }
    var cpuTotal: Double? { cpuUser.flatMap { user in cpuSystem.map { min(100, user + $0) } } }
}

/// Short ring buffer feeding the popover charts and the status item mini graphs.
/// Lives as long as the status item controller, so history survives popover open/close.
@MainActor
final class MenuBarHistory: ObservableObject {
    static let shared = MenuBarHistory()
    static let capacity = 90
    @Published private(set) var samples: [MenuBarSample] = []

    func record(_ snapshot: SystemSnapshot) {
        guard samples.last?.date != snapshot.capturedAt else { return }
        let memory = snapshot.usedMemoryBytes.map { Double($0) / Double(max(1, snapshot.physicalMemoryBytes)) }
        samples.append(MenuBarSample(
            date: snapshot.capturedAt, cpuUser: snapshot.cpuUserPercent, cpuSystem: snapshot.cpuSystemPercent,
            memoryFraction: memory, memoryPressure: snapshot.memoryPressurePercent,
            networkDown: snapshot.network?.receivedBytesPerSecond, networkUp: snapshot.network?.sentBytesPerSecond,
            diskRead: snapshot.diskIO?.readBytesPerSecond, diskWrite: snapshot.diskIO?.writeBytesPerSecond,
            battery: snapshot.power.chargePercent))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    /// Recent values for a module's mini graph, normalised to 0…1.
    /// Bounded values use their natural scale; rates scale to the window maximum with a floor,
    /// so an idle link draws a flat line instead of amplified noise.
    func graph(for module: MenuBarModule, settings: MenuBarModuleSettings, count: Int) -> [Double] {
        let recent = samples.suffix(count)
        func scaled(_ values: [Double], floor: Double) -> [Double] {
            let ceiling = max(floor, values.max() ?? 0)
            return values.map { min(1, $0 / ceiling) }
        }
        switch module {
        case .cpu:
            return recent.map { sample in
                switch settings.value {
                case .cpuUser: (sample.cpuUser ?? 0) / 100
                case .cpuSystem: (sample.cpuSystem ?? 0) / 100
                default: (sample.cpuTotal ?? 0) / 100
                }
            }
        case .memory:
            return recent.map { settings.value == .memoryPressure ? ($0.memoryPressure ?? 0) / 100 : $0.memoryFraction ?? 0 }
        case .disk:
            return scaled(recent.map { ($0.diskRead ?? 0) + ($0.diskWrite ?? 0) }, floor: 1_048_576)
        case .network:
            let values = recent.map { sample -> Double in
                switch settings.value {
                case .networkDownload: sample.networkDown ?? 0
                case .networkUpload: sample.networkUp ?? 0
                default: (sample.networkDown ?? 0) + (sample.networkUp ?? 0)
                }
            }
            return scaled(values, floor: 65_536)
        case .power:
            return recent.map { ($0.battery ?? 0) / 100 }
        }
    }

    /// Upload (positive) and download (negative side) series for the mirrored network graph.
    func networkMirror(count: Int) -> (up: [Double], down: [Double]) {
        let recent = samples.suffix(count)
        let up = recent.map { $0.networkUp ?? 0 }, down = recent.map { $0.networkDown ?? 0 }
        let ceiling = max(65_536, up.max() ?? 0, down.max() ?? 0)
        return (up.map { min(1, $0 / ceiling) }, down.map { min(1, $0 / ceiling) })
    }
}

// MARK: - Rendering

/// Draws status item images. Images are templates (black + alpha), so macOS tints them for the
/// menu bar appearance and the highlighted state; hierarchy comes from alpha, not color.
@MainActor
enum MenuBarRenderer {
    static let height: CGFloat = 22
    static let graphSamples = 20

    /// Cache key: an image is re-rendered only when one of these inputs changes.
    struct Key: Hashable {
        var parts: [String]
        var levels: [Int]
    }

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private static func attributes(_ font: NSFont, alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(alpha)]
    }

    private static func width(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((text as NSString).size(withAttributes: attributes).width)
    }

    /// Symbol for a module; the power symbol reflects battery level and charging.
    static func symbol(for module: MenuBarModule, snapshot: SystemSnapshot?) -> String {
        guard module == .power, let power = snapshot?.power, power.batteryPresent, let charge = power.chargePercent else {
            return module.symbol
        }
        if power.isCharging == true { return "battery.100percent.bolt" }
        switch charge {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private static func drawSymbol(_ name: String, in rect: NSRect, pointSize: CGFloat = 13) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let scale = min(rect.width / max(1, size.width), rect.height / max(1, size.height), 1)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
    }

    /// Bottom of the line box that vertically centers one line of `font` in the item.
    private static func centeredY(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard let font = attributes[.font] as? NSFont else { return 4 }
        return ((height - (font.ascender - font.descender)) / 2).rounded(.toNearestOrAwayFromZero)
    }

    private static func drawText(_ text: String, x: CGFloat, baseline: CGFloat, _ attributes: [NSAttributedString.Key: Any]) {
        (text as NSString).draw(at: NSPoint(x: x, y: baseline), withAttributes: attributes)
    }

    /// Vertical capsule gauge filled from the bottom.
    private static func drawGauge(_ fraction: Double, in rect: NSRect) {
        let radius = rect.width / 2
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let level = CGFloat(min(1, max(0, fraction)))
        guard level > 0 else { return }
        let filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(rect.width, rect.height * level))
        NSColor.black.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    /// Bar-graph history inside a faint rounded frame.
    private static func drawGraph(_ values: [Double], in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let slots = CGFloat(graphSamples)
        let barWidth = inner.width / slots
        NSColor.black.setFill()
        // Right-aligned: the newest sample is always at the right edge.
        for (index, value) in values.suffix(graphSamples).reversed().enumerated() {
            let height = inner.height * CGFloat(min(1, max(0, value)))
            guard height > 0.2 else { continue }
            let x = inner.maxX - CGFloat(index + 1) * barWidth
            NSRect(x: x, y: inner.minY, width: max(0.5, barWidth - 0.4), height: height).fill()
        }
    }

    /// Network graph: upload grows up from the midline, download grows down.
    private static func drawMirrorGraph(up: [Double], down: [Double], in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let mid = inner.midY
        let barWidth = inner.width / CGFloat(graphSamples)
        for (index, value) in up.suffix(graphSamples).reversed().enumerated() {
            let height = inner.height / 2 * CGFloat(value)
            guard height > 0.2 else { continue }
            NSColor.black.setFill()
            NSRect(x: inner.maxX - CGFloat(index + 1) * barWidth, y: mid, width: max(0.5, barWidth - 0.4), height: height).fill()
        }
        for (index, value) in down.suffix(graphSamples).reversed().enumerated() {
            let height = inner.height / 2 * CGFloat(value)
            guard height > 0.2 else { continue }
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSRect(x: inner.maxX - CGFloat(index + 1) * barWidth, y: mid - height, width: max(0.5, barWidth - 0.4), height: height).fill()
        }
    }

    private static func template(width: CGFloat, draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: max(1, ceil(width)), height: height), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func glyph() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MacPocket")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }

    // MARK: Separate item

    static func moduleKey(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                          snapshot: SystemSnapshot?, history: MenuBarHistory) -> Key {
        var levels: [Int] = []
        if settings.style == .gauge {
            levels.append(Int((reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0) * 40))
        } else if settings.style == .graph {
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: graphSamples)
                levels += mirror.up.map { Int($0 * 40) } + mirror.down.map { Int($0 * 40) }
            } else {
                levels += history.graph(for: module, settings: settings, count: graphSamples).map { Int($0 * 40) }
            }
        }
        return Key(parts: [module.rawValue, String(describing: settings), symbol(for: module, snapshot: snapshot)]
                   + reading.lines + reading.reserve, levels: levels)
    }

    static func module(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                       snapshot: SystemSnapshot?, history: MenuBarHistory) -> NSImage {
        let symbolName = symbol(for: module, snapshot: snapshot)
        if settings.style == .icon {
            return template(width: 18) { drawSymbol(symbolName, in: NSRect(x: 0, y: 2, width: 18, height: 18), pointSize: 14) }
        }
        let showText = settings.style == .value || settings.showValue
        let twoLines = reading.lines.count > 1
        let stackedLabel = settings.showLabel && showText && !twoLines
        let sideLabel = settings.showLabel && !stackedLabel

        let labelAttributes = attributes(font(7.5, .semibold), alpha: 0.72)
        let sideLabelAttributes = attributes(font(8.5, .semibold), alpha: 0.72)
        let valueAttributes = attributes(font(twoLines ? 9 : stackedLabel ? 10 : 12.5))

        var x: CGFloat = 0
        var operations: [(CGFloat) -> Void] = []
        func add(width: CGFloat, gap: CGFloat = 3, _ operation: @escaping (CGFloat) -> Void) {
            let start = x
            operations.append { _ in operation(start) }
            x += width + gap
        }

        if settings.showIcon {
            add(width: 15) { start in drawSymbol(symbolName, in: NSRect(x: start, y: 3, width: 15, height: 16)) }
        }
        if sideLabel {
            let label = module.shortLabel
            add(width: width(label, sideLabelAttributes)) { start in
                drawText(label, x: start, baseline: centeredY(sideLabelAttributes), sideLabelAttributes)
            }
        }
        switch settings.style {
        case .gauge:
            let fraction = reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0
            add(width: 5, gap: 4) { start in drawGauge(fraction, in: NSRect(x: start, y: 3, width: 5, height: 16)) }
        case .graph:
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: graphSamples)
                add(width: 28, gap: 4) { start in drawMirrorGraph(up: mirror.up, down: mirror.down, in: NSRect(x: start, y: 3, width: 28, height: 16)) }
            } else {
                let values = history.graph(for: module, settings: settings, count: graphSamples)
                add(width: 28, gap: 4) { start in drawGraph(values, in: NSRect(x: start, y: 3, width: 28, height: 16)) }
            }
        case .value, .icon:
            break
        }
        if showText {
            if twoLines {
                let lineWidth = zip(reading.lines + [""], reading.reserve + [""]).map { max(width($0, valueAttributes), width($1, valueAttributes)) }.max() ?? 0
                let lines = reading.lines
                add(width: lineWidth, gap: 0) { start in
                    drawText(lines[0], x: start, baseline: 11.5, valueAttributes)
                    drawText(lines[1], x: start, baseline: 1.5, valueAttributes)
                }
            } else {
                let value = reading.lines.first ?? "—"
                let reserve = reading.reserve.first ?? value
                let valueWidth = max(width(value, valueAttributes), width(reserve, valueAttributes))
                if stackedLabel {
                    let label = module.shortLabel
                    let blockWidth = max(valueWidth, width(label, labelAttributes))
                    add(width: blockWidth, gap: 0) { start in
                        drawText(label, x: start, baseline: 12.5, labelAttributes)
                        // Right-aligned so digits don't shift as the value changes.
                        drawText(value, x: start + blockWidth - width(value, valueAttributes), baseline: 1.5, valueAttributes)
                    }
                } else {
                    add(width: valueWidth, gap: 0) { start in
                        drawText(value, x: start + valueWidth - width(value, valueAttributes),
                                 baseline: centeredY(valueAttributes), valueAttributes)
                    }
                }
            }
        } else {
            x -= 4
        }
        let total = max(x, 12)
        return template(width: total) { for operation in operations { operation(0) } }
    }

    // MARK: Grouped item

    static func groupedKey(style: MenuBarGroupedStyle, readings: [(MenuBarModule, MenuBarReading)], history: MenuBarHistory,
                           preferences: MenuBarPreferences) -> Key {
        var key = Key(parts: [style.rawValue], levels: [])
        guard style != .glyph else { return key }
        for (module, reading) in readings {
            key.parts.append(module.rawValue)
            key.parts += style == .stacked ? reading.lines + reading.reserve : []
            if style == .gauges { key.levels.append(Int(level(module, reading, history, preferences) * 40)) }
        }
        return key
    }

    private static func level(_ module: MenuBarModule, _ reading: MenuBarReading, _ history: MenuBarHistory,
                              _ preferences: MenuBarPreferences) -> Double {
        reading.fraction ?? history.graph(for: module, settings: preferences.settings(for: module), count: graphSamples).last ?? 0
    }

    static func grouped(style: MenuBarGroupedStyle, readings: [(MenuBarModule, MenuBarReading)], history: MenuBarHistory,
                        preferences: MenuBarPreferences) -> NSImage {
        guard style != .glyph, !readings.isEmpty else { return glyph() }
        if style == .gauges {
            let barWidth: CGFloat = 4.5, gap: CGFloat = 2.5
            let levels = readings.map { level($0.0, $0.1, history, preferences) }
            let width = 17 + CGFloat(levels.count) * (barWidth + gap) - gap
            return template(width: width) {
                drawSymbol("gauge.with.dots.needle.50percent", in: NSRect(x: 0, y: 3, width: 14, height: 16), pointSize: 12)
                for (index, value) in levels.enumerated() {
                    drawGauge(value, in: NSRect(x: 17 + CGFloat(index) * (barWidth + gap), y: 3, width: barWidth, height: 16))
                }
            }
        }

        // Stacked: two rows per column. Single-line modules pair up as "CPU %12"; a two-line
        // reading (network up/down) takes a column of its own.
        let labelAttributes = attributes(font(8, .semibold), alpha: 0.62)
        let valueAttributes = attributes(font(9.5))
        struct Row { let label: String?; let value: String; let reserve: String }
        var columns: [[Row]] = []
        var pending: [Row] = []
        for (module, reading) in readings {
            if reading.lines.count > 1 {
                columns.append(zip(reading.lines, reading.reserve).map { Row(label: nil, value: $0, reserve: $1) })
            } else {
                pending.append(Row(label: module.shortLabel, value: reading.lines.first ?? "—",
                                   reserve: reading.reserve.first ?? "—"))
                if pending.count == 2 { columns.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { columns.append(pending) }

        let columnGap: CGFloat = 7
        let layouts = columns.map { rows -> (rows: [Row], labelWidth: CGFloat, valueWidth: CGFloat) in
            let labelWidth = rows.compactMap(\.label).map { width($0, labelAttributes) }.max() ?? 0
            let valueWidth = rows.map { max(width($0.value, valueAttributes), width($0.reserve, valueAttributes)) }.max() ?? 0
            return (rows, labelWidth, valueWidth)
        }
        let total = layouts.reduce(CGFloat(0)) { $0 + $1.labelWidth + ($1.labelWidth > 0 ? 3 : 0) + $1.valueWidth }
            + columnGap * CGFloat(max(0, layouts.count - 1))
        return template(width: total) {
            var x: CGFloat = 0
            for layout in layouts {
                let valueX = x + layout.labelWidth + (layout.labelWidth > 0 ? 3 : 0)
                let baselines: [CGFloat] = layout.rows.count == 1 ? [centeredY(valueAttributes)] : [11.5, 1.5]
                for (row, baseline) in zip(layout.rows, baselines) {
                    if let label = row.label { drawText(label, x: x, baseline: baseline + 0.5, labelAttributes) }
                    drawText(row.value, x: valueX + layout.valueWidth - width(row.value, valueAttributes), baseline: baseline, valueAttributes)
                }
                x = valueX + layout.valueWidth + columnGap
            }
        }
    }
}

/// SwiftUI preview of a rendered status item on a menu-bar-like strip (Settings).
struct MenuBarItemPreview: View {
    let image: NSImage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .foregroundStyle(.primary)
            .padding(.horizontal, PocketSpacing.s)
            .frame(height: 24)
            .background(.bar, in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous).strokeBorder(PocketTheme.line)
            }
            .accessibilityHidden(true)
    }
}

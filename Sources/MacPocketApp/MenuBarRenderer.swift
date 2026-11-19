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
    /// Fastest fan as a share of its maximum speed.
    let fan: Double?
    let thermal: Double?
    /// Hottest sensor in °C.
    var temperature: Double? = nil
    var gpu: Double? = nil
    var gpuRenderer: Double? = nil
    var gpuMemory: Double? = nil
    var ping: Double? = nil
    /// 1-minute load average per logical CPU, 0…1.
    var load: Double? = nil
    var swap: Double? = nil
    var watts: Double? = nil
    var wifiRSSI: Double? = nil
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
        let swapFraction: Double? = snapshot.swapTotalBytes.flatMap { total in
            total > 0 ? snapshot.swapUsedBytes.map { min(1, Double($0) / Double(total)) } : nil
        }
        var updated = samples
        updated.append(MenuBarSample(
            date: snapshot.capturedAt, cpuUser: snapshot.cpuUserPercent, cpuSystem: snapshot.cpuSystemPercent,
            memoryFraction: memory, memoryPressure: snapshot.memoryPressurePercent,
            networkDown: snapshot.network?.receivedBytesPerSecond, networkUp: snapshot.network?.sentBytesPerSecond,
            diskRead: snapshot.diskIO?.readBytesPerSecond, diskWrite: snapshot.diskIO?.writeBytesPerSecond,
            battery: snapshot.power.chargePercent,
            fan: snapshot.fans?.compactMap(\.fraction).max(),
            thermal: MenuBarFormatter.thermalLevel(snapshot.thermalState),
            temperature: snapshot.temperatures.flatMap(TemperatureSummary.hottest)?.celsius,
            gpu: snapshot.gpu?.utilizationPercent, gpuRenderer: snapshot.gpu?.rendererPercent,
            gpuMemory: snapshot.gpu?.memoryInUseBytes.map { Double($0) / Double(max(1, snapshot.physicalMemoryBytes)) },
            ping: snapshot.connectivity?.pingMilliseconds,
            load: snapshot.loadAverages?.first.map { min(1, $0 / Double(max(1, snapshot.logicalCPUCount))) },
            swap: swapFraction, watts: snapshot.systemPowerWatts,
            wifiRSSI: snapshot.connectivity?.wifiRSSI.map(Double.init)))
        if updated.count > Self.capacity { updated.removeFirst(updated.count - Self.capacity) }
        samples = updated
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
        case .weather, .aiUsage, .awake, .focus, .bluetooth, .display, .clock, .clipboard,
             .overview, .health, .timeline, .launcher: return []
        case .cpu:
            return recent.map { sample in
                switch settings.value {
                case .cpuUser: (sample.cpuUser ?? 0) / 100
                case .cpuSystem: (sample.cpuSystem ?? 0) / 100
                case .cpuLoad: sample.load ?? 0
                default: (sample.cpuTotal ?? 0) / 100
                }
            }
        case .gpu:
            return recent.map { sample in
                switch settings.value {
                case .gpuRenderer: (sample.gpuRenderer ?? sample.gpu ?? 0) / 100
                case .gpuMemory: sample.gpuMemory ?? 0
                default: (sample.gpu ?? 0) / 100
                }
            }
        case .memory:
            return recent.map { sample in
                switch settings.value {
                case .memoryPressure: (sample.memoryPressure ?? 0) / 100
                case .memorySwap: sample.swap ?? 0
                default: sample.memoryFraction ?? 0
                }
            }
        case .disk:
            return scaled(recent.map { ($0.diskRead ?? 0) + ($0.diskWrite ?? 0) }, floor: 1_048_576)
        case .network where settings.value == .networkPing:
            return scaled(recent.map { $0.ping ?? 0 }, floor: 100)
        case .network where settings.value == .networkWifiSignal:
            return recent.map { sample in sample.wifiRSSI.map { min(1, max(0, ($0 + 90) / 60)) } ?? 0 }
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
            return recent.map { sample in
                switch settings.value {
                case .powerFanSpeed, .powerFanPercent: sample.fan ?? 0
                case .powerThermal: sample.thermal ?? 0
                case .powerTemperature: min(1, (sample.temperature ?? 0) / 100)
                case .powerWatts: min(1, (sample.watts ?? 0) / 100)
                default: (sample.battery ?? 0) / 100
                }
            }
        }
    }

    /// Write (up) and read (down) series for the mirrored disk graph.
    func diskMirror(count: Int) -> (up: [Double], down: [Double]) {
        let recent = samples.suffix(count)
        let up = recent.map { $0.diskWrite ?? 0 }, down = recent.map { $0.diskRead ?? 0 }
        let ceiling = max(1_048_576, up.max() ?? 0, down.max() ?? 0)
        return (up.map { min(1, $0 / ceiling) }, down.map { min(1, $0 / ceiling) })
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

/// Draws status item images.
///
/// Normal items are templates (black + alpha): macOS tints them for the menu bar's light, dark, tinted or
/// highlighted look, and hierarchy comes from alpha. An item with an accent or an alarm color is drawn in color
/// instead: only its graphic and value take the color, while its icon and label keep the menu bar's label color
/// resolved for the appearance it is drawn in, so the text stays as legible as a template's.
///
/// Every edge is snapped to the device pixel grid of the display the image is drawn for (1×, 2× or 3×), so strokes
/// and glyphs stay crisp on non-Retina displays too.
@MainActor
enum MenuBarRenderer {
    /// Height of the status item's drawing area.
    static let height: CGFloat = max(22, NSStatusBar.system.thickness.rounded())
    static let graphSamples = 20

    /// Cache key: an image is re-rendered only when one of these inputs changes.
    struct Key: Hashable {
        var parts: [String]
        var levels: [Int]
    }

    // MARK: Ink

    /// Colors and pixel scale of the image being drawn; set for the duration of one drawing handler.
    private struct Ink {
        /// Device pixels per point of the context being drawn into.
        var scale: CGFloat = 2
        /// Icons, labels and secondary text.
        var neutral: NSColor = .black
        /// Values and graphic fills; the accent or alarm color when the item is colored.
        var emphasis: NSColor = .black
        var colored = false
    }

    private static var ink = Ink()

    /// Lowest alpha a track or frame is drawn with. Tracks fainter than this disappear on the translucent bar.
    private enum Alpha {
        static let track: CGFloat = 0.4
        static let frame: CGFloat = 0.2
        static let area: CGFloat = 0.42
        static let label: CGFloat = 0.85
        static let secondarySeries: CGFloat = 0.62
    }

    /// System type sizes the item uses, so it sets like the menu bar's own items instead of invented sizes.
    private enum TypeSize {
        /// The menu bar's font (the clock's): single-line values and symbols.
        static var menuBar: CGFloat { NSFont.menuBarFont(ofSize: 0).pointSize }
        /// Small labels and stacked lines: the system label size, which is also the HIG minimum (10 pt) on macOS.
        static var label: CGFloat { NSFont.labelFontSize }
        /// A stacked value under its label: the system's small size, one step above the label.
        static var stackedValue: CGFloat { NSFont.smallSystemFontSize }
    }

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// Text attributes; the color is resolved when the text is drawn, so it follows the current ink.
    @MainActor private struct TextStyle {
        let font: NSFont
        var role: Role = .emphasis
        enum Role { case emphasis, label }

        var attributes: [NSAttributedString.Key: Any] {
            let color: NSColor = switch role {
            case .emphasis: ink.emphasis
            case .label: ink.neutral.withAlphaComponent(ink.neutral.alphaComponent * Alpha.label)
            }
            return [.font: font, .foregroundColor: color]
        }

        func width(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    /// Symbol for a module showing `value`: fans and heat have their own; the battery symbol reflects
    /// charge level and charging.
    static func symbol(for module: MenuBarModule, value: MenuBarValue? = nil, snapshot: SystemSnapshot?) -> String {
        if module == .weather { return WeatherService.shared.snapshot?.symbol ?? module.symbol }
        if module == .network, snapshot?.connectivity?.online == false { return "wifi.slash" }
        if let symbol = value?.symbol { return symbol }
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

    /// Draws an SF Symbol fitted (up or down) into `rect`, centered on whole device pixels.
    private static func drawSymbol(_ name: String, in rect: NSRect, pointSize: CGFloat, weight: NSFont.Weight = .regular) {
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        if ink.colored { configuration = configuration.applying(.init(paletteColors: [ink.neutral])) }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let fit = min(rect.width / max(1, size.width), rect.height / max(1, size.height))
        let drawn = NSSize(width: size.width * fit, height: size.height * fit)
        image.draw(in: NSRect(x: snapped(rect.midX - drawn.width / 2), y: snapped(rect.midY - drawn.height / 2),
                              width: drawn.width, height: drawn.height))
    }

    /// Nearest device pixel of the context being drawn into.
    private static func snapped(_ value: CGFloat) -> CGFloat { (value * ink.scale).rounded() / ink.scale }

    /// A rect whose edges sit on device pixels.
    private static func snapped(_ rect: NSRect) -> NSRect {
        let minX = snapped(rect.minX), minY = snapped(rect.minY)
        return NSRect(x: minX, y: minY, width: max(1 / ink.scale, snapped(rect.maxX) - minX),
                      height: max(1 / ink.scale, snapped(rect.maxY) - minY))
    }

    /// Baseline that centers the cap height of one line of `font` in the item. Menu bar text is digits and capitals,
    /// so the visual center of the glyphs, not the line box, is what has to line up with icons and graphs.
    private static func centeredBaseline(_ font: NSFont) -> CGFloat {
        snapped((height - font.capHeight) / 2)
    }

    /// Baselines (bottom, top) of two stacked lines whose combined cap height and gap are centered in the item.
    private static func stackedBaselines(bottom: NSFont, top: NSFont, gap: CGFloat) -> (bottom: CGFloat, top: CGFloat) {
        let total = bottom.capHeight + gap + top.capHeight
        let low = snapped((height - total) / 2)
        return (low, snapped(low + bottom.capHeight + gap))
    }

    /// Left edge of content `contentWidth` wide inside a block `blockWidth` wide.
    private static func aligned(_ contentWidth: CGFloat, in blockWidth: CGFloat, _ alignment: MenuBarTextAlignment) -> CGFloat {
        switch alignment {
        case .leading: 0
        case .center: ((blockWidth - contentWidth) / 2).rounded(.toNearestOrAwayFromZero)
        case .trailing: blockWidth - contentWidth
        }
    }

    /// Draws `text` with its baseline at `baseline`; `draw(at:)` itself positions the bottom of the line box.
    private static func drawText(_ text: String, x: CGFloat, baseline: CGFloat, _ style: TextStyle) {
        (text as NSString).draw(at: NSPoint(x: snapped(x), y: baseline + style.font.descender), withAttributes: style.attributes)
    }

    private static func fill(_ path: NSBezierPath, alpha: CGFloat = 1) {
        ink.emphasis.withAlphaComponent(ink.emphasis.alphaComponent * alpha).setFill()
        path.fill()
    }

    private static func fill(_ rect: NSRect, alpha: CGFloat = 1) {
        ink.emphasis.withAlphaComponent(ink.emphasis.alphaComponent * alpha).setFill()
        snapped(rect).fill()
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat, alpha: CGFloat = 1) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        ink.emphasis.withAlphaComponent(ink.emphasis.alphaComponent * alpha).setStroke()
        path.stroke()
    }

    /// Vertical capsule gauge filled from the bottom.
    private static func drawGauge(_ fraction: Double, in rect: NSRect) {
        let rect = snapped(rect)
        let radius = rect.width / 2
        fill(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), alpha: Alpha.track)
        let level = CGFloat(min(1, max(0, fraction)))
        guard level > 0 else { return }
        let filled = snapped(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(rect.width, rect.height * level)))
        fill(NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius))
    }

    /// Pie filling clockwise from the top inside a ring.
    private static func drawPie(_ fraction: Double, in rect: NSRect) {
        let rect = snapped(rect)
        stroke(NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75)), width: 1.5, alpha: 0.55)
        let level = CGFloat(min(1, max(0, fraction)))
        guard level > 0.005 else { return }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let wedge = NSBezierPath()
        wedge.move(to: center)
        wedge.appendArc(withCenter: center, radius: rect.width / 2 - 2.5, startAngle: 90, endAngle: 90 - 360 * level, clockwise: true)
        wedge.close()
        fill(wedge)
    }

    /// One bar per logical CPU, filled from the bottom; every bar is a whole number of device pixels wide.
    private static func drawCores(_ values: [Double], in rect: NSRect) {
        guard !values.isEmpty else { return }
        let gap: CGFloat = values.count > 12 ? 1 : 1.5
        let barWidth = (rect.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) * (barWidth + gap)
            fill(NSRect(x: x, y: rect.minY, width: barWidth, height: rect.height), alpha: Alpha.track)
            let height = rect.height * CGFloat(min(1, max(0, value / 100)))
            guard height > 0.3 else { continue }
            fill(NSRect(x: x, y: rect.minY, width: barWidth, height: height))
        }
    }

    static func coresWidth(_ count: Int) -> CGFloat { max(8, (CGFloat(count) * (count > 12 ? 3 : 3.5)).rounded(.up)) }

    /// A VPN is connected and the network module asks to show it.
    static func showsVPN(_ module: MenuBarModule, settings: MenuBarModuleSettings, snapshot: SystemSnapshot?) -> Bool {
        module == .network && settings.showVPN && snapshot?.connectivity?.vpnActive == true
    }

    private static func frame(_ rect: NSRect) {
        fill(NSBezierPath(roundedRect: snapped(rect), xRadius: 3, yRadius: 3), alpha: Alpha.frame)
    }

    /// History inside a rounded frame: bars, a line or a filled area. The newest sample sits at the right edge.
    private static func drawGraph(_ values: [Double], in rect: NSRect, kind: MenuBarGraphKind, samples: Int) {
        frame(rect)
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let recent = Array(values.suffix(samples))
        switch kind {
        case .bars:
            let barWidth = inner.width / CGFloat(samples)
            for (index, value) in recent.reversed().enumerated() {
                let height = inner.height * CGFloat(min(1, max(0, value)))
                guard height > 0.2 else { continue }
                fill(NSRect(x: inner.maxX - CGFloat(index + 1) * barWidth, y: inner.minY,
                            width: max(1 / ink.scale, barWidth - 1 / ink.scale), height: max(1 / ink.scale, height)))
            }
        case .line, .area:
            guard let path = historyPath(recent, in: inner, samples: samples, baseline: inner.minY, direction: 1) else { return }
            if kind == .area { fillArea(path, from: recent, in: inner, samples: samples, baseline: inner.minY) }
            stroke(path, width: 1.5)
        }
    }

    /// Polyline through `values`, scaled into the half of `rect` that starts at `baseline` and grows in `direction`.
    private static func historyPath(_ values: [Double], in rect: NSRect, samples: Int, baseline: CGFloat,
                                    direction: CGFloat, fullHeight: CGFloat? = nil) -> NSBezierPath? {
        guard values.count > 1 else { return nil }
        let step = rect.width / CGFloat(max(1, samples - 1))
        let span = fullHeight ?? rect.height
        let path = NSBezierPath()
        for (index, value) in values.enumerated() {
            let x = rect.maxX - CGFloat(values.count - 1 - index) * step
            let point = NSPoint(x: x, y: baseline + direction * span * CGFloat(min(1, max(0, value))))
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        return path
    }

    private static func fillArea(_ line: NSBezierPath, from values: [Double], in rect: NSRect, samples: Int, baseline: CGFloat) {
        guard values.count > 1 else { return }
        let step = rect.width / CGFloat(max(1, samples - 1))
        let leftX = rect.maxX - CGFloat(values.count - 1) * step
        guard let area = line.copy() as? NSBezierPath else { return }
        area.line(to: NSPoint(x: rect.maxX, y: baseline))
        area.line(to: NSPoint(x: leftX, y: baseline))
        area.close()
        fill(area, alpha: Alpha.area)
    }

    /// Two-way history: `up` grows from the midline, `down` below it.
    private static func drawMirrorGraph(up: [Double], down: [Double], in rect: NSRect, kind: MenuBarGraphKind, samples: Int) {
        frame(rect)
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let mid = snapped(inner.midY)
        let half = inner.height / 2
        let ups = Array(up.suffix(samples)), downs = Array(down.suffix(samples))
        switch kind {
        case .bars:
            let barWidth = inner.width / CGFloat(samples)
            for (series, direction, alpha) in [(ups, CGFloat(1), CGFloat(1)), (downs, -1, Alpha.secondarySeries)] {
                for (index, value) in series.reversed().enumerated() {
                    let height = half * CGFloat(value)
                    guard height > 0.2 else { continue }
                    let x = inner.maxX - CGFloat(index + 1) * barWidth
                    fill(NSRect(x: x, y: direction > 0 ? mid : mid - height, width: max(1 / ink.scale, barWidth - 1 / ink.scale),
                                height: max(1 / ink.scale, height)), alpha: alpha)
                }
            }
        case .line, .area:
            let upPath = historyPath(ups, in: inner, samples: samples, baseline: mid, direction: 1, fullHeight: half)
            let downPath = historyPath(downs, in: inner, samples: samples, baseline: mid, direction: -1, fullHeight: half)
            if kind == .area {
                if let upPath { fillArea(upPath, from: ups, in: inner, samples: samples, baseline: mid) }
                if let downPath { fillArea(downPath, from: downs, in: inner, samples: samples, baseline: mid) }
            }
            if let upPath { stroke(upPath, width: 1.5) }
            if let downPath { stroke(downPath, width: 1.5, alpha: Alpha.secondarySeries + 0.2) }
            fill(NSRect(x: inner.minX, y: mid - 0.5 / ink.scale, width: inner.width, height: 1 / ink.scale), alpha: 0.45)
        }
    }

    /// Horizontal capsule meter filled from the left.
    private static func drawBar(_ fraction: Double, in rect: NSRect) {
        let rect = snapped(rect)
        let radius = rect.height / 2
        fill(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), alpha: Alpha.track)
        let level = CGFloat(min(1, max(0, fraction)))
        guard level > 0 else { return }
        let filled = snapped(NSRect(x: rect.minX, y: rect.minY, width: max(rect.height, rect.width * level), height: rect.height))
        fill(NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius))
    }

    /// A status item image `width` points wide. With `color` it is drawn in color under `appearance` (the menu bar's,
    /// or the current drawing appearance when nil); without, it is a template the menu bar tints.
    private static func image(width: CGFloat, color: NSColor?, appearance: NSAppearance?, draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: max(1, ceil(width)), height: height), flipped: false) { _ in
            let previous = ink
            defer { ink = previous }
            let render = {
                let scale = NSGraphicsContext.current.map { abs($0.cgContext.userSpaceToDeviceSpaceTransform.a) } ?? 2
                if let color {
                    // Resolve the dynamic colors for the appearance being drawn in, once.
                    let neutral = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
                    ink = Ink(scale: max(1, scale), neutral: neutral, emphasis: color.usingColorSpace(.sRGB) ?? color, colored: true)
                } else {
                    ink = Ink(scale: max(1, scale))
                }
                draw()
            }
            if let appearance, color != nil { appearance.performAsCurrentDrawingAppearance(render) } else { render() }
            return true
        }
        image.isTemplate = color == nil
        return image
    }

    // MARK: Colors

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    /// Alarm colors, darker on the pale bar and brighter on the dark one so both keep a 3:1 contrast.
    static func color(for level: MenuBarLevel) -> NSColor? {
        switch level {
        case .normal: nil
        case .warning: adaptive(0xB34700, 0xFFA23A)
        case .critical: adaptive(0xC0201A, 0xFF6961)
        }
    }

    /// Menu bar tints are darker than the vivid system colors in light appearance, which keeps thin strokes legible
    /// on the pale translucent bar.
    static func color(for accent: MenuBarAccent) -> NSColor? {
        switch accent {
        case .automatic: nil
        case .blue: adaptive(0x0A5CE0, 0x5BA3FF)
        case .teal: adaptive(0x007C8A, 0x4FD1D9)
        case .green: adaptive(0x1B8A3E, 0x4FD97A)
        case .yellow: adaptive(0x8A5F00, 0xFFD54A)
        case .orange: adaptive(0xB34700, 0xFF9F43)
        case .red: adaptive(0xC62828, 0xFF6B6B)
        case .pink: adaptive(0xC2185B, 0xFF7EB6)
        case .purple: adaptive(0x6A3FD1, 0xB28DFF)
        }
    }

    /// The color an item is drawn in: the alarm color wins over the accent; nil keeps the item a template.
    static func itemColor(level: MenuBarLevel, accent: MenuBarAccent) -> NSColor? {
        color(for: level) ?? color(for: accent)
    }

    // MARK: Separate item

    static func moduleKey(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                          snapshot: SystemSnapshot?, history: MenuBarHistory) -> Key {
        var levels: [Int] = []
        let samples = settings.graphWidth.samples
        switch settings.style {
        case .gauge, .pie, .ring, .bar:
            levels.append(Int((reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0) * 40))
        case .cores:
            levels += (snapshot?.cpuCorePercents ?? []).map { Int($0 / 100 * 16) }
        case .graph:
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: samples)
                levels += mirror.up.map { Int($0 * 40) } + mirror.down.map { Int($0 * 40) }
            } else if module == .disk && settings.value == .diskReadWrite {
                let mirror = history.diskMirror(count: samples)
                levels += mirror.up.map { Int($0 * 40) } + mirror.down.map { Int($0 * 40) }
            } else {
                levels += history.graph(for: module, settings: settings, count: samples).map { Int($0 * 40) }
            }
        case .value, .icon:
            break
        }
        return Key(parts: [module.rawValue, String(describing: settings), reading.symbol ?? symbol(for: module, value: settings.value, snapshot: snapshot),
                           showsVPN(module, settings: settings, snapshot: snapshot) ? "vpn" : "",
                           "\(MenuBarThresholds.level(reading, settings: settings).rawValue)"]
                   + reading.lines + reading.reserve, levels: levels)
    }

    /// The item of one module. `appearance` is the menu bar's; it matters only for colored items, which the caller
    /// must re-render when it changes (put it in the render key).
    static func module(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                       snapshot: SystemSnapshot?, history: MenuBarHistory, appearance: NSAppearance? = nil) -> NSImage {
        let color = itemColor(level: MenuBarThresholds.level(reading, settings: settings), accent: settings.accent)
        let layout = moduleLayout(module, settings: settings, reading: reading, snapshot: snapshot, history: history)
        return image(width: layout.width, color: color, appearance: appearance) { for operation in layout.operations { operation() } }
    }

    private static func moduleLayout(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                                     snapshot: SystemSnapshot?, history: MenuBarHistory) -> (width: CGFloat, operations: [() -> Void]) {
        let symbolName = reading.symbol ?? symbol(for: module, value: settings.value, snapshot: snapshot)
        let shortLabel = module.shortLabel(for: settings.value)
        let scale = CGFloat(settings.textSize.scale)
        // Graphics stay within the item: the standard 16 pt, 14 pt when small, 18 pt when large; always even, so
        // they center on whole points.
        let graphicHeight = min(18, ((16 * scale) / 2).rounded() * 2)
        let graphicY = ((height - graphicHeight) / 2).rounded()
        if settings.style == .icon {
            let side = graphicHeight + 2
            return (side, [{ drawSymbol(symbolName, in: NSRect(x: 0, y: (height - side) / 2, width: side, height: side), pointSize: (TypeSize.menuBar * scale).rounded(), weight: .regular) }])
        }
        let showText = settings.style == .value || settings.showValue
        let twoLines = reading.lines.count > 1
        let stackedLabel: Bool
        switch settings.labelPosition {
        case .automatic, .above: stackedLabel = settings.showLabel && showText && !twoLines
        case .beside: stackedLabel = false
        }
        let sideLabel = settings.showLabel && !stackedLabel

        // Smaller text sizes never go below the system label size (the HIG minimum); icons and text share a weight.
        let labelStyle = TextStyle(font: font(max(TypeSize.label, TypeSize.label * scale), .regular), role: .label)
        let sideLabelStyle = TextStyle(font: font(max(TypeSize.label, TypeSize.label * scale), .medium), role: .label)
        let valueSize = twoLines ? TypeSize.label : stackedLabel ? TypeSize.stackedValue : TypeSize.menuBar
        let valueStyle = TextStyle(font: font(max(TypeSize.label, valueSize * scale), twoLines || stackedLabel ? .medium : .regular))

        var x: CGFloat = 0
        var operations: [() -> Void] = []
        let gap: CGFloat = 4
        func add(width: CGFloat, gap: CGFloat = gap, _ operation: @escaping (CGFloat) -> Void) {
            let start = x
            operations.append { operation(start) }
            x += width + gap
        }

        if showsVPN(module, settings: settings, snapshot: snapshot) {
            add(width: 9, gap: 2) { start in drawSymbol("lock.fill", in: NSRect(x: start, y: (height - 11) / 2, width: 9, height: 11), pointSize: 9, weight: .medium) }
        }
        // Offline: the slashed Wi-Fi glyph says it even when the user hid the icon.
        if settings.showIcon || (module == .network && snapshot?.connectivity?.online == false) {
            let glyph = graphicHeight
            add(width: glyph) { start in
                drawSymbol(symbolName, in: NSRect(x: start, y: (height - glyph) / 2, width: glyph, height: glyph), pointSize: (TypeSize.menuBar * scale).rounded(), weight: .regular)
            }
        }
        if sideLabel {
            let label = shortLabel
            add(width: sideLabelStyle.width(label)) { start in
                drawText(label, x: start, baseline: centeredBaseline(sideLabelStyle.font), sideLabelStyle)
            }
        }
        let samples = settings.graphWidth.samples
        let graphWidth = CGFloat(settings.graphWidth.points)
        let fraction = reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0
        switch settings.style {
        case .gauge:
            add(width: 6) { start in drawGauge(fraction, in: NSRect(x: start, y: graphicY, width: 6, height: graphicHeight)) }
        case .bar:
            let barWidth = (24 * scale).rounded()
            add(width: barWidth) { start in drawBar(fraction, in: NSRect(x: start, y: (height - 6) / 2, width: barWidth, height: 6)) }
        case .pie:
            add(width: graphicHeight) { start in drawPie(fraction, in: NSRect(x: start, y: graphicY, width: graphicHeight, height: graphicHeight)) }
        case .ring:
            add(width: graphicHeight) { start in
                drawRing(fraction, symbol: nil, center: NSPoint(x: start + graphicHeight / 2, y: height / 2), radius: graphicHeight / 2 - 1.25, line: RoundGlyph.value)
            }
        case .cores:
            let cores = snapshot?.cpuCorePercents ?? []
            let coreWidth = coresWidth(cores.count)
            add(width: coreWidth) { start in drawCores(cores, in: NSRect(x: start, y: graphicY, width: coreWidth, height: graphicHeight)) }
        case .graph:
            let kind = settings.graphKind
            let rect = { (start: CGFloat) in NSRect(x: start, y: graphicY, width: graphWidth, height: graphicHeight) }
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: samples)
                add(width: graphWidth) { drawMirrorGraph(up: mirror.up, down: mirror.down, in: rect($0), kind: kind, samples: samples) }
            } else if module == .disk && settings.value == .diskReadWrite {
                let mirror = history.diskMirror(count: samples)
                add(width: graphWidth) { drawMirrorGraph(up: mirror.up, down: mirror.down, in: rect($0), kind: kind, samples: samples) }
            } else {
                let values = history.graph(for: module, settings: settings, count: samples)
                add(width: graphWidth) { drawGraph(values, in: rect($0), kind: kind, samples: samples) }
            }
        case .value, .icon:
            break
        }
        if showText {
            let alignment = settings.textAlignment
            if twoLines {
                let lines = reading.lines
                let lineWidth = zip(lines + [""], reading.reserve + [""]).map { max(valueStyle.width($0), valueStyle.width($1)) }.max() ?? 0
                add(width: lineWidth, gap: 0) { start in
                    let baselines = stackedBaselines(bottom: valueStyle.font, top: valueStyle.font, gap: 2.5 * scale)
                    drawText(lines[0], x: start + aligned(valueStyle.width(lines[0]), in: lineWidth, alignment), baseline: baselines.top, valueStyle)
                    drawText(lines[1], x: start + aligned(valueStyle.width(lines[1]), in: lineWidth, alignment), baseline: baselines.bottom, valueStyle)
                }
            } else {
                let value = reading.lines.first ?? "—"
                let reserve = reading.reserve.first ?? value
                let valueWidth = max(valueStyle.width(value), valueStyle.width(reserve))
                if stackedLabel {
                    let label = shortLabel
                    let blockWidth = max(valueWidth, labelStyle.width(label))
                    // Label and value share one edge; the block keeps its reserved width so digits don't shift.
                    add(width: blockWidth, gap: 0) { start in
                        let baselines = stackedBaselines(bottom: valueStyle.font, top: labelStyle.font, gap: 2.5 * scale)
                        drawText(label, x: start + aligned(labelStyle.width(label), in: blockWidth, alignment), baseline: baselines.top, labelStyle)
                        drawText(value, x: start + aligned(valueStyle.width(value), in: blockWidth, alignment), baseline: baselines.bottom, valueStyle)
                    }
                } else {
                    add(width: valueWidth, gap: 0) { start in
                        drawText(value, x: start + valueWidth - valueStyle.width(value), baseline: centeredBaseline(valueStyle.font), valueStyle)
                    }
                }
            }
        } else {
            x -= gap
        }
        return (max(x, 12), operations)
    }

    // MARK: Grouped item

    /// Everything the single grouped icon depends on; equal states draw identical images.
    struct GroupedState: Equatable {
        var style: MenuBarGroupedStyle
        /// Symbol of the metric module (ring center, value style).
        var symbol: String
        /// 0…1 level of the metric module.
        var level: Double
        var attention: Bool
        /// Room for the attention dot is kept while the dot is enabled, so the item never changes width.
        var badgeEnabled = false
        var alarm: MenuBarLevel = .normal
        /// `.bars`: CPU, memory and disk levels; `.sparkline`: recent levels of the metric. 0…1 each.
        var series: [Double] = []
        var accent: MenuBarAccent = .automatic
        /// `.value`: the metric's text and the widest text it can show.
        var text = ""
        var reserve = ""
    }

    static func groupedState(preferences: MenuBarPreferences, snapshot: SystemSnapshot?, history: MenuBarHistory,
                             attention: Bool) -> GroupedState {
        let metric = preferences.groupedMetric
        let settings = preferences.settings(for: metric)
        let reading = MenuBarFormatter.reading(metric, settings: settings, snapshot: snapshot, binaryUnits: preferences.binaryUnits)
        let level = reading.fraction ?? history.graph(for: metric, settings: settings, count: graphSamples).last ?? 0
        let style = preferences.groupedStyle
        var series: [Double] = []
        switch style {
        case .bars:
            series = ([.cpu, .memory, .disk] as [MenuBarModule]).map { module in
                var overview = MenuBarModuleSettings.defaults(for: module)
                overview.value = module == .cpu ? .cpuTotal : module == .memory ? .memoryUsedPercent : .diskUsedPercent
                let reading = MenuBarFormatter.reading(module, settings: overview, snapshot: snapshot, binaryUnits: preferences.binaryUnits)
                return min(1, max(0, reading.fraction ?? 0))
            }
        case .sparkline:
            series = history.graph(for: metric, settings: settings, count: sparklineSamples)
        case .symbol, .dial, .ring, .value:
            break
        }
        let showsText = style == .value && reading.lines.count == 1
        return GroupedState(style: style, symbol: symbol(for: metric, value: settings.value, snapshot: snapshot),
                            level: min(1, max(0, level)), attention: preferences.groupedBadge && attention,
                            badgeEnabled: preferences.groupedBadge,
                            alarm: style.isLive ? MenuBarThresholds.level(reading, settings: settings) : .normal,
                            series: series, accent: preferences.groupedAccent,
                            text: showsText ? reading.lines[0] : "", reserve: showsText ? (reading.reserve.first ?? "") : "")
    }

    static func groupedKey(_ state: GroupedState) -> Key {
        let quantized = state.series.map { Int(($0 * 40).rounded()) }
        let usesSymbol = state.style == .ring || state.style == .value
        return Key(parts: [state.style.rawValue, usesSymbol ? state.symbol : "", state.attention ? "attention" : "",
                           state.badgeEnabled ? "badge" : "", "\(state.alarm.rawValue)", state.accent.rawValue, state.text, state.reserve],
                   levels: state.style == .bars || state.style == .sparkline ? quantized
                       : state.style.isLive && state.style != .value ? [Int((state.level * Double(levelSteps)).rounded())] : [])
    }

    /// Quantization of the live icon: fine enough for the needle to move smoothly, coarse enough that
    /// sampling noise doesn't re-render the image every tick.
    private static let levelSteps = 50
    /// Side of the square every grouped glyph is designed in; even, so it centers on whole points.
    private static let glyphSide: CGFloat = 18
    private static let sparklineWidth: CGFloat = 30
    private static let sparklineSamples = 24
    private static let badgeRoom: CGFloat = 4

    static func grouped(_ state: GroupedState, appearance: NSAppearance? = nil) -> NSImage {
        let color = itemColor(level: state.alarm, accent: state.accent)
        let valueStyle = TextStyle(font: font(TypeSize.menuBar, .regular))
        let valueWidth = state.style == .value ? max(valueStyle.width(state.text), valueStyle.width(state.reserve)) : 0
        let body: CGFloat = switch state.style {
        case .sparkline: sparklineWidth
        case .value: glyphSide + 3 + valueWidth
        default: glyphSide
        }
        let width = body + (state.badgeEnabled ? badgeRoom : 0)
        let level = Double(Int((state.level * Double(levelSteps)).rounded())) / Double(levelSteps)
        let box = NSRect(x: 0, y: (height - glyphSide) / 2, width: glyphSide, height: glyphSide)
        return image(width: width, color: color, appearance: appearance) {
            switch state.style {
            case .symbol:
                drawSymbol("gauge.with.dots.needle.67percent", in: box, pointSize: 15, weight: .regular)
            case .dial:
                drawDial(level, in: box)
            case .ring:
                drawRing(level, symbol: state.symbol, center: NSPoint(x: box.midX, y: box.midY), radius: glyphSide / 2 - 2, line: RoundGlyph.value)
            case .bars:
                drawTrio(state.series, in: box.insetBy(dx: 1.5, dy: 1))
            case .sparkline:
                drawGraph(state.series, in: NSRect(x: 0, y: (height - 16) / 2, width: sparklineWidth, height: 16), kind: .area, samples: sparklineSamples)
            case .value:
                drawSymbol(state.symbol, in: box.insetBy(dx: 1, dy: 1), pointSize: 13, weight: .regular)
                let text = state.text.isEmpty ? "—" : state.text
                // Leading-aligned beside the symbol; the reserved width stays on the trailing side so neighbors don't move.
                drawText(text, x: glyphSide + 3, baseline: centeredBaseline(valueStyle.font), valueStyle)
            }
            if state.attention { drawBadge(center: NSPoint(x: width - 3, y: box.maxY - 3)) }
        }
    }

    /// Stroke weights of the dial and ring: a hairline track under a heavy value arc.
    private enum RoundGlyph {
        static let track: CGFloat = 1.1
        static let value: CGFloat = 2.25
    }

    /// Speedometer: a 250° track, the filled arc and a needle at the level, all from the lower left. The arc's
    /// bounding box, not its center, is centered in `box`, so the dial sits level with neighboring icons.
    private static func drawDial(_ level: Double, in box: NSRect) {
        let start: CGFloat = 215, sweep: CGFloat = 250
        let line = RoundGlyph.value
        let radius = box.width / 2 - line / 2 - 0.5
        // The open bottom spans sin(35°) of the radius below the center; split the slack above and below.
        let drop = radius * sin(35 * .pi / 180)
        let center = NSPoint(x: box.midX, y: snapped(box.midY - (radius - drop) / 2))
        let end = start - sweep * CGFloat(level)
        func arc(to angle: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: angle, clockwise: true)
            return path
        }
        // The menu bar's vibrancy washes out partial alpha, so track and value differ in weight, not opacity.
        stroke(arc(to: start - sweep), width: RoundGlyph.track)
        if level > 0.01 { stroke(arc(to: end), width: line) }
        let radians = end * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(x: center.x + cos(radians) * (radius - 3), y: center.y + sin(radians) * (radius - 3)))
        stroke(needle, width: 1.6)
        fill(NSBezierPath(ovalIn: NSRect(x: center.x - 1.9, y: center.y - 1.9, width: 3.8, height: 3.8)))
    }

    /// Three meters side by side (CPU, memory, disk), each a whole number of points wide.
    private static func drawTrio(_ levels: [Double], in rect: NSRect) {
        let count = max(1, levels.count)
        let gap: CGFloat = 2
        let barWidth = ((rect.width - gap * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        let used = barWidth * CGFloat(count) + gap * CGFloat(count - 1)
        let left = rect.minX + ((rect.width - used) / 2).rounded()
        for (index, level) in levels.enumerated() {
            let x = left + CGFloat(index) * (barWidth + gap)
            drawGauge(level, in: NSRect(x: x, y: rect.minY, width: barWidth, height: rect.height))
        }
    }

    /// Progress ring filling clockwise from the top, with the metric's symbol inside.
    private static func drawRing(_ level: Double, symbol: String?, center: NSPoint, radius: CGFloat, line: CGFloat) {
        let center = NSPoint(x: snapped(center.x), y: snapped(center.y))
        stroke(NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
               width: RoundGlyph.track)
        if level > 0.01 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(level), clockwise: true)
            stroke(arc, width: line)
        }
        // Inside a 16-pt ring the symbol has about 9 pt; that resolves on Retina displays only.
        guard let symbol, ink.scale >= 2 else { return }
        let side = (radius - line) * 2 - 1
        drawSymbol(symbol, in: NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), pointSize: 8, weight: .medium)
    }

    /// A dot with a transparent moat, so it stays distinct where it overlaps the icon; drawn in the item's emphasis ink.
    private static func drawBadge(center: NSPoint) {
        guard let context = NSGraphicsContext.current else { return }
        let center = NSPoint(x: snapped(center.x), y: snapped(center.y))
        context.saveGraphicsState()
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)).fill()
        context.restoreGraphicsState()
        fill(NSBezierPath(ovalIn: NSRect(x: center.x - 2.75, y: center.y - 2.75, width: 5.5, height: 5.5)))
    }
}

/// SwiftUI preview of a rendered status item on a menu-bar-like strip (Settings).
struct MenuBarItemPreview: View {
    let image: NSImage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
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

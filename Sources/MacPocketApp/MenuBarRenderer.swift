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
        case .weather, .aiUsage, .awake, .focus, .bluetooth, .display, .clock: return []
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

    /// Baseline that centers the cap height of one line of `font` in the item. Menu bar text is digits and capitals,
    /// so the visual center of the glyphs, not the line box, is what has to line up with icons and graphs.
    private static func centeredY(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard let font = attributes[.font] as? NSFont else { return 4 }
        return snapped((height - font.capHeight) / 2)
    }

    /// Nearest half point: a whole device pixel on Retina displays, so text stays crisp without drifting a full point.
    private static func snapped(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }

    /// Baselines (bottom, top) of two stacked lines whose combined cap height and gap are centered in the item.
    private static func stackedBaselines(bottom: [NSAttributedString.Key: Any], top: [NSAttributedString.Key: Any],
                                         gap: CGFloat) -> (bottom: CGFloat, top: CGFloat) {
        guard let bottomFont = bottom[.font] as? NSFont, let topFont = top[.font] as? NSFont else { return (1.5, 12.5) }
        let total = bottomFont.capHeight + gap + topFont.capHeight
        let low = snapped((height - total) / 2)
        return (low, low + bottomFont.capHeight + gap)
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
    private static func drawText(_ text: String, x: CGFloat, baseline: CGFloat, _ attributes: [NSAttributedString.Key: Any]) {
        let descender = (attributes[.font] as? NSFont)?.descender ?? 0
        (text as NSString).draw(at: NSPoint(x: x, y: baseline + descender), withAttributes: attributes)
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

    /// Pie filling clockwise from the top inside a thin ring.
    private static func drawPie(_ fraction: Double, in rect: NSRect) {
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.6, dy: 0.6))
        ring.lineWidth = 1.2
        NSColor.black.withAlphaComponent(0.35).setStroke()
        ring.stroke()
        let level = CGFloat(min(1, max(0, fraction)))
        guard level > 0.005 else { return }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let wedge = NSBezierPath()
        wedge.move(to: center)
        wedge.appendArc(withCenter: center, radius: rect.width / 2 - 2, startAngle: 90, endAngle: 90 - 360 * level, clockwise: true)
        wedge.close()
        NSColor.black.setFill()
        wedge.fill()
    }

    /// One thin bar per logical CPU, filled from the bottom.
    private static func drawCores(_ values: [Double], in rect: NSRect) {
        guard !values.isEmpty else { return }
        let gap: CGFloat = values.count > 12 ? 1 : 1.5
        let barWidth = (rect.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) * (barWidth + gap)
            NSColor.black.withAlphaComponent(0.22).setFill()
            NSRect(x: x, y: rect.minY, width: barWidth, height: rect.height).fill()
            let height = rect.height * CGFloat(min(1, max(0, value / 100)))
            guard height > 0.3 else { continue }
            NSColor.black.setFill()
            NSRect(x: x, y: rect.minY, width: barWidth, height: height).fill()
        }
    }

    static func coresWidth(_ count: Int) -> CGFloat { max(8, CGFloat(count) * (count > 12 ? 3 : 3.5)) }

    /// A VPN is connected and the network module asks to show it.
    static func showsVPN(_ module: MenuBarModule, settings: MenuBarModuleSettings, snapshot: SystemSnapshot?) -> Bool {
        module == .network && settings.showVPN && snapshot?.connectivity?.vpnActive == true
    }

    /// History inside a faint rounded frame: bars, a line or a filled area. The newest sample sits at the right edge.
    private static func drawGraph(_ values: [Double], in rect: NSRect, kind: MenuBarGraphKind, samples: Int) {
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let recent = Array(values.suffix(samples))
        switch kind {
        case .bars:
            let barWidth = inner.width / CGFloat(samples)
            NSColor.black.setFill()
            for (index, value) in recent.reversed().enumerated() {
                let height = inner.height * CGFloat(min(1, max(0, value)))
                guard height > 0.2 else { continue }
                NSRect(x: inner.maxX - CGFloat(index + 1) * barWidth, y: inner.minY,
                       width: max(0.5, barWidth - 0.4), height: height).fill()
            }
        case .line, .area:
            guard let path = historyPath(recent, in: inner, samples: samples, baseline: inner.minY, direction: 1) else { return }
            if kind == .area { fillArea(path, from: recent, in: inner, samples: samples, baseline: inner.minY) }
            stroke(path)
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

    private static func stroke(_ path: NSBezierPath) {
        path.lineWidth = 1.25
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        NSColor.black.setStroke()
        path.stroke()
    }

    private static func fillArea(_ line: NSBezierPath, from values: [Double], in rect: NSRect, samples: Int,
                                 baseline: CGFloat, fullHeight: CGFloat? = nil, direction: CGFloat = 1) {
        guard let first = values.indices.first, values.count > 1 else { return }
        let step = rect.width / CGFloat(max(1, samples - 1))
        let leftX = rect.maxX - CGFloat(values.count - 1 - first) * step
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: rect.maxX, y: baseline))
        area.line(to: NSPoint(x: leftX, y: baseline))
        area.close()
        NSColor.black.withAlphaComponent(0.32).setFill()
        area.fill()
    }

    /// Two-way history: `up` grows from the midline, `down` below it.
    private static func drawMirrorGraph(up: [Double], down: [Double], in rect: NSRect, kind: MenuBarGraphKind, samples: Int) {
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let mid = inner.midY
        let half = inner.height / 2
        let ups = Array(up.suffix(samples)), downs = Array(down.suffix(samples))
        switch kind {
        case .bars:
            let barWidth = inner.width / CGFloat(samples)
            for (index, value) in ups.reversed().enumerated() {
                let height = half * CGFloat(value)
                guard height > 0.2 else { continue }
                NSColor.black.setFill()
                NSRect(x: inner.maxX - CGFloat(index + 1) * barWidth, y: mid, width: max(0.5, barWidth - 0.4), height: height).fill()
            }
            for (index, value) in downs.reversed().enumerated() {
                let height = half * CGFloat(value)
                guard height > 0.2 else { continue }
                NSColor.black.withAlphaComponent(0.7).setFill()
                NSRect(x: inner.maxX - CGFloat(index + 1) * barWidth, y: mid - height, width: max(0.5, barWidth - 0.4), height: height).fill()
            }
        case .line, .area:
            let upPath = historyPath(ups, in: inner, samples: samples, baseline: mid, direction: 1, fullHeight: half)
            let downPath = historyPath(downs, in: inner, samples: samples, baseline: mid, direction: -1, fullHeight: half)
            if kind == .area {
                if let upPath { fillArea(upPath, from: ups, in: inner, samples: samples, baseline: mid) }
                if let downPath { fillArea(downPath, from: downs, in: inner, samples: samples, baseline: mid) }
            }
            if let upPath { stroke(upPath) }
            if let downPath { stroke(downPath) }
            let axis = NSBezierPath()
            axis.move(to: NSPoint(x: inner.minX, y: mid)); axis.line(to: NSPoint(x: inner.maxX, y: mid))
            axis.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.4).setStroke()
            axis.stroke()
        }
    }

    /// Horizontal capsule meter filled from the left.
    private static func drawBar(_ fraction: Double, in rect: NSRect) {
        let radius = rect.height / 2
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let level = CGFloat(min(1, max(0, fraction)))
        guard level > 0 else { return }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: max(rect.height, rect.width * level), height: rect.height),
                     xRadius: radius, yRadius: radius).fill()
    }

    private static func template(width: CGFloat, draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: max(1, ceil(width)), height: height), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Threshold color

    static func color(for level: MenuBarLevel) -> NSColor? {
        switch level {
        case .normal: nil
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    /// Menu bar tints are darker than the vivid system colors in light appearance, which keeps thin strokes legible
    /// on the pale translucent bar.
    static func color(for accent: MenuBarAccent) -> NSColor? {
        func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
            NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
        }
        switch accent {
        case .automatic: return nil
        case .blue: return adaptive(0x0A5CE0, 0x5BA3FF)
        case .teal: return adaptive(0x007C8A, 0x4FD1D9)
        case .green: return adaptive(0x1B8A3E, 0x4FD97A)
        case .yellow: return adaptive(0x9A6B00, 0xFFD54A)
        case .orange: return adaptive(0xC25500, 0xFF9F43)
        case .red: return adaptive(0xC62828, 0xFF6B6B)
        case .pink: return adaptive(0xC2185B, 0xFF7EB6)
        case .purple: return adaptive(0x6A3FD1, 0xB28DFF)
        }
    }

    /// A template image recolored for a warning or critical level. Colored images no longer follow the menu bar
    /// appearance, so only alarm states use them; the normal state stays a template.
    static func colored(_ image: NSImage, level: MenuBarLevel, accent: MenuBarAccent = .automatic) -> NSImage {
        guard let color = color(for: level) ?? color(for: accent) else { return image }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
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

    static func module(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                       snapshot: SystemSnapshot?, history: MenuBarHistory) -> NSImage {
        colored(moduleTemplate(module, settings: settings, reading: reading, snapshot: snapshot, history: history),
                level: MenuBarThresholds.level(reading, settings: settings), accent: settings.accent)
    }

    private static func moduleTemplate(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                                       snapshot: SystemSnapshot?, history: MenuBarHistory) -> NSImage {
        let symbolName = reading.symbol ?? symbol(for: module, value: settings.value, snapshot: snapshot)
        let shortLabel = module.shortLabel(for: settings.value)
        let scale = CGFloat(settings.textSize.scale)
        let symbolPoints = (14 * scale).rounded()
        if settings.style == .icon {
            return template(width: 18 * scale) { drawSymbol(symbolName, in: NSRect(x: 0, y: (height - 18 * scale) / 2, width: 18 * scale, height: 18 * scale), pointSize: symbolPoints) }
        }
        let showText = settings.style == .value || settings.showValue
        let twoLines = reading.lines.count > 1
        let stackedLabel: Bool
        switch settings.labelPosition {
        case .automatic, .above: stackedLabel = settings.showLabel && showText && !twoLines
        case .beside: stackedLabel = false
        }
        let sideLabel = settings.showLabel && !stackedLabel

        let labelAttributes = attributes(font(7.5 * scale, .semibold), alpha: 0.72)
        let sideLabelAttributes = attributes(font(8.5 * scale, .semibold), alpha: 0.72)
        let valueAttributes = attributes(font((twoLines ? 9 : stackedLabel ? 10 : 12.5) * scale))
        // Graphics stay within the 22-pt item: the standard 16 pt, 14 pt when small, 18 pt when large.
        let graphicHeight = min(18, (16 * scale).rounded())
        let graphicY = ((height - graphicHeight) / 2).rounded()

        var x: CGFloat = 0
        var operations: [(CGFloat) -> Void] = []
        let gap: CGFloat = 4
        func add(width: CGFloat, gap: CGFloat = gap, _ operation: @escaping (CGFloat) -> Void) {
            let start = x
            operations.append { _ in operation(start) }
            x += width + gap
        }

        if showsVPN(module, settings: settings, snapshot: snapshot) {
            add(width: 9, gap: 2) { start in drawSymbol("lock.fill", in: NSRect(x: start, y: 5, width: 9, height: 12), pointSize: 9) }
        }
        // Offline: the slashed Wi-Fi glyph says it even when the user hid the icon.
        if settings.showIcon || (module == .network && snapshot?.connectivity?.online == false) {
            let glyph = (15 * scale).rounded()
            add(width: glyph) { start in drawSymbol(symbolName, in: NSRect(x: start, y: (height - glyph) / 2, width: glyph, height: glyph), pointSize: symbolPoints - 1) }
        }
        if sideLabel {
            let label = shortLabel
            add(width: width(label, sideLabelAttributes)) { start in
                drawText(label, x: start, baseline: centeredY(sideLabelAttributes), sideLabelAttributes)
            }
        }
        let samples = settings.graphWidth.samples
        let graphWidth = CGFloat(settings.graphWidth.points)
        let fraction = reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0
        switch settings.style {
        case .gauge:
            add(width: 5, gap: 4) { start in drawGauge(fraction, in: NSRect(x: start, y: graphicY, width: 5, height: graphicHeight)) }
        case .bar:
            let barWidth = (24 * scale).rounded()
            add(width: barWidth, gap: 4) { start in drawBar(fraction, in: NSRect(x: start, y: (height - 5) / 2, width: barWidth, height: 5)) }
        case .pie:
            add(width: graphicHeight - 1, gap: 4) { start in drawPie(fraction, in: NSRect(x: start, y: graphicY + 0.5, width: graphicHeight - 1, height: graphicHeight - 1)) }
        case .ring:
            let diameter = graphicHeight - 1
            add(width: diameter, gap: 4) { start in
                drawRing(fraction, symbol: nil, center: NSPoint(x: start + diameter / 2, y: height / 2), radius: diameter / 2 - 1.3, line: 2)
            }
        case .cores:
            let cores = snapshot?.cpuCorePercents ?? []
            let coreWidth = coresWidth(cores.count)
            add(width: coreWidth, gap: 4) { start in drawCores(cores, in: NSRect(x: start, y: graphicY, width: coreWidth, height: graphicHeight)) }
        case .graph:
            let kind = settings.graphKind
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: samples)
                add(width: graphWidth, gap: 4) { start in
                    drawMirrorGraph(up: mirror.up, down: mirror.down, in: NSRect(x: start, y: graphicY, width: graphWidth, height: graphicHeight), kind: kind, samples: samples)
                }
            } else if module == .disk && settings.value == .diskReadWrite {
                let mirror = history.diskMirror(count: samples)
                add(width: graphWidth, gap: 4) { start in
                    drawMirrorGraph(up: mirror.up, down: mirror.down, in: NSRect(x: start, y: graphicY, width: graphWidth, height: graphicHeight), kind: kind, samples: samples)
                }
            } else {
                let values = history.graph(for: module, settings: settings, count: samples)
                add(width: graphWidth, gap: 4) { start in
                    drawGraph(values, in: NSRect(x: start, y: graphicY, width: graphWidth, height: graphicHeight), kind: kind, samples: samples)
                }
            }
        case .value, .icon:
            break
        }
        if showText {
            if twoLines {
                let lineWidth = zip(reading.lines + [""], reading.reserve + [""]).map { max(width($0, valueAttributes), width($1, valueAttributes)) }.max() ?? 0
                let lines = reading.lines
                let baselines = stackedBaselines(bottom: valueAttributes, top: valueAttributes, gap: 3 * scale)
                let alignment = settings.textAlignment
                add(width: lineWidth, gap: 0) { start in
                    drawText(lines[0], x: start + aligned(width(lines[0], valueAttributes), in: lineWidth, alignment), baseline: baselines.top, valueAttributes)
                    drawText(lines[1], x: start + aligned(width(lines[1], valueAttributes), in: lineWidth, alignment), baseline: baselines.bottom, valueAttributes)
                }
            } else {
                let value = reading.lines.first ?? "—"
                let reserve = reading.reserve.first ?? value
                let valueWidth = max(width(value, valueAttributes), width(reserve, valueAttributes))
                if stackedLabel {
                    let label = shortLabel
                    let blockWidth = max(valueWidth, width(label, labelAttributes))
                    let baselines = stackedBaselines(bottom: valueAttributes, top: labelAttributes, gap: 2.5 * scale)
                    let alignment = settings.textAlignment
                    // Label and value share one edge; the block keeps its reserved width so digits don't shift.
                    add(width: blockWidth, gap: 0) { start in
                        drawText(label, x: start + aligned(width(label, labelAttributes), in: blockWidth, alignment), baseline: baselines.top, labelAttributes)
                        drawText(value, x: start + aligned(width(value, valueAttributes), in: blockWidth, alignment), baseline: baselines.bottom, valueAttributes)
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

    /// Everything the single grouped icon depends on; equal states draw identical images.
    struct GroupedState: Equatable {
        var style: MenuBarGroupedStyle
        /// Symbol of the metric module (ring center).
        var symbol: String
        /// 0…1 level of the metric module.
        var level: Double
        var attention: Bool
        var alarm: MenuBarLevel = .normal
        /// `.bars`: CPU, memory and disk levels; `.sparkline`: recent levels of the metric. 0…1 each.
        var series: [Double] = []
        var accent: MenuBarAccent = .automatic
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
        case .symbol, .dial, .ring:
            break
        }
        return GroupedState(style: style, symbol: symbol(for: metric, value: settings.value, snapshot: snapshot),
                            level: min(1, max(0, level)), attention: preferences.groupedBadge && attention,
                            alarm: style.isLive ? MenuBarThresholds.level(reading, settings: settings) : .normal,
                            series: series, accent: preferences.groupedAccent)
    }

    static func groupedKey(_ state: GroupedState) -> Key {
        let quantized = state.series.map { Int(($0 * 40).rounded()) }
        return Key(parts: [state.style.rawValue, state.style == .ring ? state.symbol : "", state.attention ? "attention" : "",
                           "\(state.alarm.rawValue)", state.accent.rawValue],
                   levels: state.style == .bars || state.style == .sparkline ? quantized
                       : state.style.isLive ? [Int((state.level * Double(levelSteps)).rounded())] : [])
    }

    /// Quantization of the live icon: fine enough for the needle to move smoothly, coarse enough that
    /// sampling noise doesn't re-render the image every tick.
    private static let levelSteps = 50
    private static let iconWidth: CGFloat = 19
    private static let sparklineWidth: CGFloat = 30
    private static let sparklineSamples = 24
    private static let badgeRoom: CGFloat = 3

    static func grouped(_ state: GroupedState) -> NSImage {
        colored(groupedTemplate(state), level: state.alarm, accent: state.accent)
    }

    private static func groupedTemplate(_ state: GroupedState) -> NSImage {
        let body = state.style == .sparkline ? sparklineWidth : iconWidth
        let width = body + (state.attention ? badgeRoom : 0)
        let level = Double(Int((state.level * Double(levelSteps)).rounded())) / Double(levelSteps)
        return template(width: width) {
            switch state.style {
            case .symbol:
                drawSymbol("gauge.with.dots.needle.50percent", in: NSRect(x: 0, y: 2, width: iconWidth, height: 18), pointSize: 14)
            case .dial:
                drawDial(level, center: NSPoint(x: iconWidth / 2, y: 9.4), radius: 7.5)
            case .ring:
                drawRing(level, symbol: state.symbol, center: NSPoint(x: iconWidth / 2, y: height / 2), radius: 7.2)
            case .bars:
                drawTrio(state.series, in: NSRect(x: 1, y: 3, width: iconWidth - 2, height: 16))
            case .sparkline:
                drawGraph(state.series, in: NSRect(x: 0, y: 3, width: sparklineWidth, height: 16), kind: .area, samples: sparklineSamples)
            }
            if state.attention { drawBadge(center: NSPoint(x: width - 3, y: height - 4.5)) }
        }
    }

    /// Speedometer: a 250° track, the filled arc and a needle at the level, all from the lower left.
    private static func drawDial(_ level: Double, center: NSPoint, radius: CGFloat) {
        let start: CGFloat = 215, sweep: CGFloat = 250
        let end = start - sweep * CGFloat(level)
        func arc(to angle: CGFloat, alpha: CGFloat) {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: angle, clockwise: true)
            path.lineWidth = 2
            path.lineCapStyle = .round
            NSColor.black.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
        arc(to: start - sweep, alpha: 0.3)
        if level > 0.01 { arc(to: end, alpha: 1) }
        let radians = end * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(x: center.x + cos(radians) * (radius - 2.6), y: center.y + sin(radians) * (radius - 2.6)))
        needle.lineWidth = 1.6
        needle.lineCapStyle = .round
        NSColor.black.setStroke()
        needle.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6)).fill()
    }

    /// Three slim vertical meters side by side.
    private static func drawTrio(_ levels: [Double], in rect: NSRect) {
        let count = max(1, levels.count)
        let gap: CGFloat = 2.5
        let barWidth = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        for (index, level) in levels.enumerated() {
            let x = rect.minX + CGFloat(index) * (barWidth + gap)
            drawGauge(level, in: NSRect(x: x, y: rect.minY, width: barWidth, height: rect.height))
        }
    }

    /// Progress ring filling clockwise from the top, with the metric's symbol inside.
    private static func drawRing(_ level: Double, symbol: String?, center: NSPoint, radius: CGFloat, line: CGFloat = 2.2) {
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = line
        NSColor.black.withAlphaComponent(0.28).setStroke()
        track.stroke()
        if level > 0.01 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(level), clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
        }
        guard let symbol else { return }
        drawSymbol(symbol, in: NSRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9), pointSize: 7.5)
    }

    /// A dot with a transparent moat, so it stays distinct where it overlaps the icon.
    private static func drawBadge(center: NSPoint) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)).fill()
        context.restoreGraphicsState()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)).fill()
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

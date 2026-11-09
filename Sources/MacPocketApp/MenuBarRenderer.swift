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
            ping: snapshot.connectivity?.pingMilliseconds, wifiRSSI: snapshot.connectivity?.wifiRSSI.map(Double.init)))
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
        case .weather, .aiUsage: return []
        case .cpu:
            return recent.map { sample in
                switch settings.value {
                case .cpuUser: (sample.cpuUser ?? 0) / 100
                case .cpuSystem: (sample.cpuSystem ?? 0) / 100
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
            return recent.map { settings.value == .memoryPressure ? ($0.memoryPressure ?? 0) / 100 : $0.memoryFraction ?? 0 }
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

    // MARK: Threshold color

    static func color(for level: MenuBarLevel) -> NSColor? {
        switch level {
        case .normal: nil
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    /// A template image recolored for a warning or critical level. Colored images no longer follow the menu bar
    /// appearance, so only alarm states use them; the normal state stays a template.
    static func colored(_ image: NSImage, level: MenuBarLevel) -> NSImage {
        guard let color = color(for: level) else { return image }
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
        if settings.style == .gauge || settings.style == .pie {
            levels.append(Int((reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0) * 40))
        } else if settings.style == .cores {
            levels += (snapshot?.cpuCorePercents ?? []).map { Int($0 / 100 * 16) }
        } else if settings.style == .graph {
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: graphSamples)
                levels += mirror.up.map { Int($0 * 40) } + mirror.down.map { Int($0 * 40) }
            } else if module == .disk && settings.value == .diskReadWrite {
                let mirror = history.diskMirror(count: graphSamples)
                levels += mirror.up.map { Int($0 * 40) } + mirror.down.map { Int($0 * 40) }
            } else {
                levels += history.graph(for: module, settings: settings, count: graphSamples).map { Int($0 * 40) }
            }
        }
        return Key(parts: [module.rawValue, String(describing: settings), symbol(for: module, value: settings.value, snapshot: snapshot),
                           showsVPN(module, settings: settings, snapshot: snapshot) ? "vpn" : "",
                           "\(MenuBarThresholds.level(reading, settings: settings).rawValue)"]
                   + reading.lines + reading.reserve, levels: levels)
    }

    static func module(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                       snapshot: SystemSnapshot?, history: MenuBarHistory) -> NSImage {
        colored(moduleTemplate(module, settings: settings, reading: reading, snapshot: snapshot, history: history),
                level: MenuBarThresholds.level(reading, settings: settings))
    }

    private static func moduleTemplate(_ module: MenuBarModule, settings: MenuBarModuleSettings, reading: MenuBarReading,
                                       snapshot: SystemSnapshot?, history: MenuBarHistory) -> NSImage {
        let symbolName = symbol(for: module, value: settings.value, snapshot: snapshot)
        let shortLabel = module.shortLabel(for: settings.value)
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

        if showsVPN(module, settings: settings, snapshot: snapshot) {
            add(width: 9, gap: 2) { start in drawSymbol("lock.fill", in: NSRect(x: start, y: 5, width: 9, height: 12), pointSize: 9) }
        }
        // Offline: the slashed Wi-Fi glyph says it even when the user hid the icon.
        if settings.showIcon || (module == .network && snapshot?.connectivity?.online == false) {
            add(width: 15) { start in drawSymbol(symbolName, in: NSRect(x: start, y: 3, width: 15, height: 16)) }
        }
        if sideLabel {
            let label = shortLabel
            add(width: width(label, sideLabelAttributes)) { start in
                drawText(label, x: start, baseline: centeredY(sideLabelAttributes), sideLabelAttributes)
            }
        }
        switch settings.style {
        case .gauge:
            let fraction = reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0
            add(width: 5, gap: 4) { start in drawGauge(fraction, in: NSRect(x: start, y: 3, width: 5, height: 16)) }
        case .pie:
            let fraction = reading.fraction ?? history.graph(for: module, settings: settings, count: 1).last ?? 0
            add(width: 15, gap: 4) { start in drawPie(fraction, in: NSRect(x: start, y: 3.5, width: 15, height: 15)) }
        case .cores:
            let cores = snapshot?.cpuCorePercents ?? []
            let coreWidth = coresWidth(cores.count)
            add(width: coreWidth, gap: 4) { start in drawCores(cores, in: NSRect(x: start, y: 3, width: coreWidth, height: 16)) }
        case .graph:
            if module == .network && settings.value == .networkUpDown {
                let mirror = history.networkMirror(count: graphSamples)
                add(width: 28, gap: 4) { start in drawMirrorGraph(up: mirror.up, down: mirror.down, in: NSRect(x: start, y: 3, width: 28, height: 16)) }
            } else if module == .disk && settings.value == .diskReadWrite {
                let mirror = history.diskMirror(count: graphSamples)
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
                    let label = shortLabel
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

    /// Everything the single grouped icon depends on; equal states draw identical images.
    struct GroupedState: Equatable {
        var style: MenuBarGroupedStyle
        /// Symbol of the metric module (ring center).
        var symbol: String
        /// 0…1 level of the metric module.
        var level: Double
        var attention: Bool
        var alarm: MenuBarLevel = .normal
    }

    static func groupedState(preferences: MenuBarPreferences, snapshot: SystemSnapshot?, history: MenuBarHistory,
                             attention: Bool) -> GroupedState {
        let metric = preferences.groupedMetric
        let settings = preferences.settings(for: metric)
        let reading = MenuBarFormatter.reading(metric, settings: settings, snapshot: snapshot, binaryUnits: preferences.binaryUnits)
        let level = reading.fraction ?? history.graph(for: metric, settings: settings, count: graphSamples).last ?? 0
        return GroupedState(style: preferences.groupedStyle,
                            symbol: symbol(for: metric, value: settings.value, snapshot: snapshot),
                            level: min(1, max(0, level)), attention: preferences.groupedBadge && attention,
                            alarm: preferences.groupedStyle.isLive ? MenuBarThresholds.level(reading, settings: settings) : .normal)
    }

    static func groupedKey(_ state: GroupedState) -> Key {
        Key(parts: [state.style.rawValue, state.style == .ring ? state.symbol : "", state.attention ? "attention" : "", "\(state.alarm.rawValue)"],
            levels: state.style.isLive ? [Int((state.level * Double(levelSteps)).rounded())] : [])
    }

    /// Quantization of the live icon: fine enough for the needle to move smoothly, coarse enough that
    /// sampling noise doesn't re-render the image every tick.
    private static let levelSteps = 50
    private static let iconWidth: CGFloat = 19
    private static let badgeRoom: CGFloat = 3

    static func grouped(_ state: GroupedState) -> NSImage {
        colored(groupedTemplate(state), level: state.alarm)
    }

    private static func groupedTemplate(_ state: GroupedState) -> NSImage {
        let width = iconWidth + (state.attention ? badgeRoom : 0)
        let level = Double(Int((state.level * Double(levelSteps)).rounded())) / Double(levelSteps)
        return template(width: width) {
            switch state.style {
            case .symbol:
                drawSymbol("gauge.with.dots.needle.50percent", in: NSRect(x: 0, y: 2, width: iconWidth, height: 18), pointSize: 14)
            case .dial:
                drawDial(level, center: NSPoint(x: iconWidth / 2, y: 9.4), radius: 7.5)
            case .ring:
                drawRing(level, symbol: state.symbol, center: NSPoint(x: iconWidth / 2, y: height / 2), radius: 7.2)
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

    /// Progress ring filling clockwise from the top, with the metric's symbol inside.
    private static func drawRing(_ level: Double, symbol: String, center: NSPoint, radius: CGFloat) {
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = 2.2
        NSColor.black.withAlphaComponent(0.28).setStroke()
        track.stroke()
        if level > 0.01 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(level), clockwise: true)
            arc.lineWidth = 2.2
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
        }
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

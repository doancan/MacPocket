import AppKit
import XCTest
@testable import MacPocketApp
@testable import MacPocketCore

/// Renders every menu bar option combination with the real renderer. With MACPOCKET_MENUBAR_GALLERY=<dir> it also
/// writes contact sheets (light and dark menu bar) for visual review.
@MainActor final class MenuBarRendererTests: XCTestCase {
    private func snapshot(at index: Int) -> SystemSnapshot {
        let phase = Double(index)
        var snapshot = SystemSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_000 + phase), hardwareModel: "fixture", logicalCPUCount: 10,
            cpuUserPercent: 20 + 30 * abs(sin(phase / 4)), cpuSystemPercent: 8 + 6 * abs(cos(phase / 3)), cpuIdlePercent: 50,
            physicalMemoryBytes: 32 << 30, freeMemoryBytes: 2 << 30, wiredMemoryBytes: 4 << 30,
            compressedMemoryBytes: 1 << 30, appMemoryBytes: 14 << 30, swapUsedBytes: 0, uptimeSeconds: 100,
            thermalState: "nominal",
            volumes: [VolumeSnapshot(name: "Macintosh HD", path: "/", totalBytes: 1_000 << 30, availableBytes: 380 << 30)],
            power: PowerSnapshot(source: "Battery Power", batteryPresent: true, chargePercent: 64, isCharging: false, lowPowerMode: false,
                                 minutesRemaining: 215))
        snapshot.cpuCorePercents = (0..<10).map { 15 + Double(($0 * 37 + index * 11) % 70) }
        snapshot.memoryPressurePercent = 30 + 20 * abs(sin(phase / 5))
        snapshot.network = NetworkSnapshot(receivedBytesPerSecond: 400_000 * (1 + abs(sin(phase / 3))), sentBytesPerSecond: 90_000 * (1 + abs(cos(phase / 4))),
                                           primaryInterface: "en0", localIPv4: "10.0.0.2")
        snapshot.diskIO = DiskIOSnapshot(readBytesPerSecond: 2_000_000 * abs(sin(phase / 2)), writeBytesPerSecond: 800_000 * abs(cos(phase / 2)))
        snapshot.fans = [FanSnapshot(rpm: 1800 + phase * 10, minimumRPM: 1200, maximumRPM: 5800)]
        snapshot.temperatures = [TemperatureReading(name: "CPU Die", celsius: 52 + phase / 2)]
        snapshot.gpu = GPUSnapshot(utilizationPercent: 20 + 30 * abs(sin(phase / 6)), rendererPercent: 18, memoryInUseBytes: 3 << 30)
        snapshot.connectivity = ConnectivitySnapshot(online: true, link: .wifi, vpnActive: true, wifiRSSI: -58, pingMilliseconds: 24)
        return snapshot
    }

    private func history() -> (MenuBarHistory, SystemSnapshot) {
        let history = MenuBarHistory()
        for index in 0..<60 { history.record(snapshot(at: index)) }
        return (history, snapshot(at: 60))
    }

    private func render(_ module: MenuBarModule, _ settings: MenuBarModuleSettings, _ history: MenuBarHistory, _ snapshot: SystemSnapshot,
                        external: MenuBarReading? = nil) -> NSImage {
        let reading = MenuBarFormatter.reading(module, settings: settings, snapshot: snapshot, binaryUnits: true, external: external)
        return MenuBarRenderer.module(module, settings: settings, reading: reading, snapshot: snapshot, history: history)
    }

    private func sample(_ module: MenuBarModule) -> MenuBarReading? {
        switch module {
        case .awake: MenuBarReading(lines: ["42 dk"], reserve: ["9:59"], fraction: 0.6, magnitude: 60, accessibility: "x", symbol: "cup.and.saucer.fill")
        case .focus: MenuBarReading(lines: ["18 dk"], reserve: ["9:59"], fraction: 0.7, magnitude: 70, accessibility: "x", symbol: "scope")
        case .bluetooth: MenuBarReading(lines: ["72%"], reserve: ["100%"], fraction: 0.72, magnitude: 72, accessibility: "x", symbol: "battery.75percent")
        case .display: MenuBarReading(lines: ["68%"], reserve: ["100%"], fraction: 0.68, magnitude: 68, accessibility: "x", symbol: "sun.max.fill")
        default: nil
        }
    }

    func testEveryOptionCombinationRendersAMenuBarSizedImage() throws {
        let (history, snapshot) = history()
        var rendered = 0
        for module in MenuBarModule.allCases {
            for value in module.valueOptions {
                for style in module.styleOptions {
                    for kind in MenuBarGraphKind.allCases where style == .graph || kind == .bars {
                        for width in MenuBarGraphWidth.allCases where style == .graph || width == .standard {
                            for size in MenuBarTextSize.allCases {
                                for position in MenuBarLabelPosition.allCases {
                                    var settings = MenuBarModuleSettings.defaults(for: module)
                                    settings.value = value; settings.style = style; settings.graphKind = kind
                                    settings.graphWidth = width; settings.textSize = size; settings.labelPosition = position
                                    settings.showLabel = true; settings.showIcon = true; settings.showValue = true
                                    let image = render(module, settings, history, snapshot, external: sample(module))
                                    let context = "\(module) \(value) \(style) \(kind) \(width) \(size) \(position)"
                                    XCTAssertEqual(image.size.height, MenuBarRenderer.height, context)
                                    XCTAssertGreaterThan(image.size.width, 8, context)
                                    XCTAssertLessThan(image.size.width, 260, context)
                                    rendered += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(rendered, 1_000)
    }

    func testAccentColorsProduceColoredImagesAndAutomaticStaysTemplate() {
        let (history, snapshot) = history()
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        XCTAssertTrue(render(.cpu, settings, history, snapshot).isTemplate)
        for accent in MenuBarAccent.allCases where accent != .automatic {
            settings.accent = accent
            XCTAssertFalse(render(.cpu, settings, history, snapshot).isTemplate, accent.rawValue)
        }
    }

    func testGraphWidthChangesTheItemWidth() {
        let (history, snapshot) = history()
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        settings.style = .graph
        var widths: [Double] = []
        for width in MenuBarGraphWidth.allCases {
            settings.graphWidth = width
            widths.append(Double(render(.cpu, settings, history, snapshot).size.width))
        }
        XCTAssertEqual(widths, widths.sorted())
        XCTAssertLessThan(widths[0], widths[2])
    }

    func testTextSizeScalesTheItem() {
        let (history, snapshot) = history()
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        var widths: [Double] = []
        for size in MenuBarTextSize.allCases {
            settings.textSize = size
            widths.append(Double(render(.cpu, settings, history, snapshot).size.width))
        }
        XCTAssertLessThan(widths[0], widths[2])
    }

    func testGroupedStylesRenderAndDiffer() {
        let (history, snapshot) = history()
        var keys = Set<String>()
        for style in MenuBarGroupedStyle.allCases {
            var preferences = MenuBarPreferences()
            preferences.groupedStyle = style
            let state = MenuBarRenderer.groupedState(preferences: preferences, snapshot: snapshot, history: history, attention: false)
            let image = MenuBarRenderer.grouped(state)
            XCTAssertEqual(image.size.height, MenuBarRenderer.height)
            keys.insert(MenuBarRenderer.groupedKey(state).parts.joined(separator: "|"))
        }
        XCTAssertEqual(keys.count, MenuBarGroupedStyle.allCases.count)
    }

    func testRenderKeyChangesWithEveryAppearanceOption() {
        let (history, snapshot) = history()
        func key(_ change: (inout MenuBarModuleSettings) -> Void) -> MenuBarRenderer.Key {
            var settings = MenuBarModuleSettings.defaults(for: .cpu)
            settings.style = .graph
            change(&settings)
            let reading = MenuBarFormatter.reading(.cpu, settings: settings, snapshot: snapshot, binaryUnits: true)
            return MenuBarRenderer.moduleKey(.cpu, settings: settings, reading: reading, snapshot: snapshot, history: history)
        }
        let base = key { _ in }
        XCTAssertNotEqual(base, key { $0.graphKind = .line })
        XCTAssertNotEqual(base, key { $0.graphWidth = .wide })
        XCTAssertNotEqual(base, key { $0.textSize = .large })
        XCTAssertNotEqual(base, key { $0.labelPosition = .beside })
        XCTAssertNotEqual(base, key { $0.accent = .pink })
    }

    /// Rows (in points from the bottom) between which the image has ink.
    private func inkRows(_ image: NSImage) -> (low: CGFloat, high: CGFloat)? {
        let scale: CGFloat = 4
        let width = Int(image.size.width * scale), height = Int(image.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = image.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var low = height, high = -1
        for y in 0..<height {
            for x in 0..<width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                low = min(low, height - 1 - y); high = max(high, height - 1 - y)
            }
        }
        return high < 0 ? nil : (CGFloat(low) / scale, CGFloat(high + 1) / scale)
    }

    func testStackedTextIsCenteredVerticallyForEveryAlignmentAndSize() throws {
        let (history, snapshot) = history()
        for size in MenuBarTextSize.allCases {
            for alignment in MenuBarTextAlignment.allCases {
                var settings = MenuBarModuleSettings.defaults(for: .cpu)
                settings.textSize = size; settings.textAlignment = alignment
                let stacked = try XCTUnwrap(inkRows(render(.cpu, settings, history, snapshot)))
                // "CPU" over "%50": no descenders, so the ink block must sit in the middle of the 22-pt item.
                XCTAssertEqual(stacked.low, MenuBarRenderer.height - stacked.high, accuracy: 1.5, "stacked \(size) \(alignment)")
                var network = MenuBarModuleSettings.defaults(for: .network)
                network.textSize = size; network.textAlignment = alignment; network.showVPN = false
                let two = try XCTUnwrap(inkRows(render(.network, network, history, snapshot)))
                XCTAssertEqual(two.low, MenuBarRenderer.height - two.high, accuracy: 2.0, "two lines \(size) \(alignment)")
            }
        }
    }

    func testSingleLineValueIsCenteredVertically() throws {
        let (history, snapshot) = history()
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        settings.showLabel = false
        let ink = try XCTUnwrap(inkRows(render(.cpu, settings, history, snapshot)))
        XCTAssertEqual(ink.low, MenuBarRenderer.height - ink.high, accuracy: 1.0)
    }

    func testAlignmentMovesTheStackedLabel() throws {
        let (history, snapshot) = history()
        func leftInk(_ alignment: MenuBarTextAlignment) -> CGFloat {
            var settings = MenuBarModuleSettings.defaults(for: .cpu)
            settings.textAlignment = alignment
            let image = render(.cpu, settings, history, snapshot)
            return inkColumns(image).low
        }
        XCTAssertLessThan(leftInk(.leading), leftInk(.trailing) + 0.01)
    }

    private func inkColumns(_ image: NSImage) -> (low: CGFloat, high: CGFloat) {
        let scale: CGFloat = 4
        let width = Int(image.size.width * scale), height = Int(image.size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        // Ink of the top text row only (the label), so alignment shows in its left edge.
        var low = width, high = -1
        for y in 0..<(height / 3) { for x in 0..<width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { low = min(low, x); high = max(high, x) } }
        return (CGFloat(low) / scale, CGFloat(high + 1) / scale)
    }

    func testContactSheets() throws {
        guard let directory = ProcessInfo.processInfo.environment["MACPOCKET_MENUBAR_GALLERY"] else { throw XCTSkip("Set MACPOCKET_MENUBAR_GALLERY to write contact sheets.") }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let (history, snapshot) = history()
        for dark in [false, true] {
            let surface = MenuBarSurface(dark: dark)
            var rows: [(String, [NSImage])] = []
            for module in MenuBarModule.allCases {
                var images: [NSImage] = []
                for style in module.styleOptions {
                    var settings = MenuBarModuleSettings.defaults(for: module)
                    settings.style = style; settings.showLabel = true; settings.showIcon = true
                    images.append(render(module, settings, history, snapshot, external: sample(module)))
                    if style == .graph {
                        for kind in [MenuBarGraphKind.line, .area] {
                            settings.graphKind = kind
                            images.append(render(module, settings, history, snapshot, external: sample(module)))
                        }
                        settings.graphKind = .area; settings.graphWidth = .wide
                        images.append(render(module, settings, history, snapshot, external: sample(module)))
                    }
                }
                for accent in MenuBarAccent.allCases where accent != .automatic {
                    var settings = MenuBarModuleSettings.defaults(for: module)
                    settings.accent = accent
                    images.append(render(module, settings, history, snapshot, external: sample(module)))
                }
                var critical = MenuBarModuleSettings.defaults(for: module)
                critical.colorMode = .thresholds; critical.warningThreshold = 1; critical.criticalThreshold = 2
                if critical.value.thresholdUnit != nil { images.append(render(module, critical, history, snapshot, external: sample(module))) }
                rows.append((module.rawValue, images))
            }
            for (title, module, value) in [("align cpu", MenuBarModule.cpu, MenuBarValue.cpuTotal), ("align net", .network, .networkUpDown),
                                           ("align disk", .disk, .diskReadWrite), ("align mem", .memory, .memoryUsedBytes)] {
                var images: [NSImage] = []
                for size in MenuBarTextSize.allCases {
                    for alignment in MenuBarTextAlignment.allCases {
                        var settings = MenuBarModuleSettings.defaults(for: module)
                        settings.value = value; settings.textAlignment = alignment; settings.textSize = size; settings.showLabel = true
                        images.append(render(module, settings, history, snapshot))
                    }
                    var beside = MenuBarModuleSettings.defaults(for: module)
                    beside.value = value; beside.textSize = size; beside.labelPosition = .beside; beside.showLabel = true; beside.showIcon = true
                    images.append(render(module, beside, history, snapshot))
                }
                rows.append((title, images))
            }
            var grouped: [NSImage] = []
            for style in MenuBarGroupedStyle.allCases {
                var preferences = MenuBarPreferences(); preferences.groupedStyle = style
                grouped.append(MenuBarRenderer.grouped(MenuBarRenderer.groupedState(preferences: preferences, snapshot: snapshot, history: history, attention: style == .ring)))
            }
            rows.append(("grouped", grouped))
            try sheet(rows, surface: surface).write(to: URL(fileURLWithPath: directory).appendingPathComponent(dark ? "dark.png" : "light.png"))
        }
    }

    private func sheet(_ rows: [(String, [NSImage])], surface: MenuBarSurface) -> Data {
        let scale: CGFloat = 3, rowHeight: CGFloat = 30, labelWidth: CGFloat = 70, gap: CGFloat = 14
        let width = (rows.map { $0.1.reduce(labelWidth) { $0 + $1.size.width + gap } }.max() ?? 400) + 20
        let height = rowHeight * CGFloat(rows.count) + 10
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        surface.appearance.performAsCurrentDrawingAppearance {
            (surface.dark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            for (rowIndex, row) in rows.enumerated() {
                let y = height - CGFloat(rowIndex + 1) * rowHeight - 2
                (row.0 as NSString).draw(at: NSPoint(x: 6, y: y + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: surface.foreground])
                var x = labelWidth
                for image in row.1 {
                    surface.flatten(image).draw(in: NSRect(x: x, y: y + 4, width: image.size.width, height: image.size.height))
                    x += image.size.width + gap
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}

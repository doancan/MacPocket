import AppKit
import MacPocketCore
import SwiftUI

/// Marks MacPocket's own screenshot windows so captures can leave them out.
protocol ScreenshotChrome: NSWindow {}

/// What the user picked on the frozen screens.
enum ScreenshotSelection {
    /// A rectangle in points, origin top-left of that screen.
    case area(display: CGDirectDisplayID, rect: CGRect)
    case window(CGWindowID)
    case fullscreen(CGDirectDisplayID)
    case previousArea
}

/// One frozen screen: its image (native pixels) and geometry.
struct FrozenScreen {
    let display: CGDirectDisplayID
    let frame: NSRect // AppKit global, bottom-left origin
    let scale: CGFloat
    let image: CGImage
}

/// A window under the pointer at freeze time, in AppKit global coordinates.
struct FrozenWindow {
    let id: CGWindowID
    let frame: NSRect
}

/// Covers every screen with its frozen picture and lets the user drag an area, click a window (Space toggles window
/// mode) or pick a mode from the bar. Esc cancels.
@MainActor
final class ScreenshotSelectionOverlay {
    private var panels: [SelectionPanel] = []
    private var completion: ((ScreenshotSelection?) -> Void)?
    private var windowMode: Bool
    private let windows: [FrozenWindow]
    private let showsModeBar: Bool
    private let hasPreviousArea: Bool

    init(screens: [FrozenScreen], windows: [FrozenWindow], startInWindowMode: Bool, showsModeBar: Bool, hasPreviousArea: Bool) {
        self.windows = windows
        windowMode = startInWindowMode
        self.showsModeBar = showsModeBar
        self.hasPreviousArea = hasPreviousArea
        panels = screens.map { screen in
            let panel = SelectionPanel(screen: screen)
            panel.selectionView.owner = self
            return panel
        }
    }

    func begin(completion: @escaping (ScreenshotSelection?) -> Void) {
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)
        let pointer = NSEvent.mouseLocation
        for panel in panels {
            panel.selectionView.windowMode = windowMode
            panel.selectionView.showsModeBar = showsModeBar && NSMouseInRect(pointer, panel.frame, false)
            panel.orderFrontRegardless()
        }
        (panels.first { NSMouseInRect(pointer, $0.frame, false) } ?? panels.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    // MARK: Called by the views

    func window(at point: NSPoint) -> FrozenWindow? { windows.first { NSMouseInRect(point, $0.frame, false) } }

    var canUsePreviousArea: Bool { hasPreviousArea }

    func toggleWindowMode() {
        windowMode.toggle()
        panels.forEach { $0.selectionView.windowMode = windowMode; $0.selectionView.needsDisplay = true }
    }

    func setWindowMode(_ on: Bool) { if windowMode != on { toggleWindowMode() } }

    func pointerMoved() { panels.forEach { $0.selectionView.needsDisplay = true } }

    func finish(_ selection: ScreenshotSelection?) {
        guard let completion else { return }
        self.completion = nil
        NSCursor.pop()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        // Let the panels leave the screen before anything captures it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { completion(selection) }
    }
}

// MARK: - Panel

private final class SelectionPanel: NSPanel, ScreenshotChrome {
    let selectionView: SelectionView

    init(screen: FrozenScreen) {
        selectionView = SelectionView(screen: screen)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = selectionView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - View

private final class SelectionView: NSView {
    weak var owner: ScreenshotSelectionOverlay?
    let screen: FrozenScreen
    var windowMode = false { didSet { modeBar?.rootView = makeModeBar() } }
    var showsModeBar = false { didSet { updateModeBar() } }
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var modeBar: NSHostingView<ScreenshotModeBar>?
    private lazy var nsImage = NSImage(cgImage: screen.image, size: screen.frame.size)

    init(screen: FrozenScreen) {
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self))
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Mode bar

    private func updateModeBar() {
        if showsModeBar, modeBar == nil {
            let bar = NSHostingView(rootView: makeModeBar())
            bar.frame = NSRect(x: (bounds.width - 600) / 2, y: 90, width: 600, height: 64)
            addSubview(bar)
            modeBar = bar
        } else if !showsModeBar {
            modeBar?.removeFromSuperview()
            modeBar = nil
        }
    }

    private func makeModeBar() -> ScreenshotModeBar {
        ScreenshotModeBar(windowMode: windowMode, previousAvailable: owner?.canUsePreviousArea ?? false) { [weak self] choice in
            guard let self, let owner = self.owner else { return }
            switch choice {
            case .area: owner.setWindowMode(false)
            case .window: owner.setWindowMode(true)
            case .fullscreen: owner.finish(.fullscreen(self.screen.display))
            case .previous: owner.finish(.previousArea)
            case .cancel: owner.finish(nil)
            }
        }
    }

    // MARK: Events

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: owner?.finish(nil) // Esc
        case 49: owner?.toggleWindowMode() // Space
        case 36, 76: // Return: whole screen
            owner?.finish(.fullscreen(screen.display))
        default: super.keyDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) { owner?.pointerMoved() }
    override func mouseEntered(with event: NSEvent) { window?.makeKey(); owner?.pointerMoved() }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if windowMode {
            let global = NSPoint(x: point.x + screen.frame.minX, y: point.y + screen.frame.minY)
            if let window = owner?.window(at: global) { owner?.finish(.window(window.id)) }
            return
        }
        dragStart = point
        dragCurrent = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart, let end = dragCurrent else { return }
        dragStart = nil; dragCurrent = nil
        let rect = ScreenshotGeometry.rect(from: start, to: end)
        guard rect.width >= 3, rect.height >= 3 else { needsDisplay = true; return }
        // To top-left origin, points.
        let topLeft = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        owner?.finish(.area(display: screen.display, rect: topLeft))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds)
        let pointer = window.map { $0.convertPoint(fromScreen: NSEvent.mouseLocation) } ?? .zero
        let pointerInside = bounds.contains(pointer)
        NSColor.black.withAlphaComponent(0.35).setFill()

        if windowMode {
            let global = NSPoint(x: pointer.x + screen.frame.minX, y: pointer.y + screen.frame.minY)
            if pointerInside, let target = owner?.window(at: global) {
                let local = target.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                let path = NSBezierPath(rect: bounds)
                path.append(NSBezierPath(rect: local).reversed)
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                local.fill()
                NSColor.controlAccentColor.setStroke()
                let border = NSBezierPath(rect: local.insetBy(dx: 1, dy: 1))
                border.lineWidth = 2
                border.stroke()
            } else {
                bounds.fill()
            }
            return
        }

        if let start = dragStart, let current = dragCurrent {
            let rect = ScreenshotGeometry.rect(from: start, to: current)
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: rect).reversed)
            path.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            drawLabel(ScreenshotGeometry.sizeLabel(rect, scale: screen.scale), near: NSPoint(x: rect.maxX, y: rect.minY))
        } else {
            bounds.fill()
        }
        guard pointerInside else { return }
        drawCrosshair(at: pointer)
        drawMagnifier(at: pointer)
    }

    private func drawCrosshair(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.move(to: NSPoint(x: 0, y: point.y.rounded() + 0.5))
        path.line(to: NSPoint(x: bounds.width, y: point.y.rounded() + 0.5))
        path.move(to: NSPoint(x: point.x.rounded() + 0.5, y: 0))
        path.line(to: NSPoint(x: point.x.rounded() + 0.5, y: bounds.height))
        path.stroke()
    }

    /// A round loupe beside the pointer: 15 × 15 screen pixels at 8×, with a pixel grid and the pointer's pixel framed.
    private func drawMagnifier(at point: NSPoint) {
        let pixels = 15, zoom: CGFloat = 8
        let size = CGFloat(pixels) * zoom
        var origin = NSPoint(x: point.x + 24, y: point.y - size - 24)
        if origin.x + size > bounds.width { origin.x = point.x - size - 24 }
        if origin.y < 0 { origin.y = point.y + 24 }
        let loupe = NSRect(origin: origin, size: NSSize(width: size, height: size))
        let pixelX = Int((point.x * screen.scale).rounded(.down)) - pixels / 2
        let pixelY = Int(((bounds.height - point.y) * screen.scale).rounded(.down)) - pixels / 2
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(ovalIn: loupe)
        clip.addClip()
        NSColor.black.setFill()
        loupe.fill()
        if let crop = screen.image.cropping(to: CGRect(x: pixelX, y: pixelY, width: pixels, height: pixels)),
           let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .none
            context.draw(crop, in: loupe)
        }
        NSColor.gray.withAlphaComponent(0.25).setStroke()
        let grid = NSBezierPath()
        for index in 1..<pixels {
            let offset = CGFloat(index) * zoom
            grid.move(to: NSPoint(x: loupe.minX + offset, y: loupe.minY)); grid.line(to: NSPoint(x: loupe.minX + offset, y: loupe.maxY))
            grid.move(to: NSPoint(x: loupe.minX, y: loupe.minY + offset)); grid.line(to: NSPoint(x: loupe.maxX, y: loupe.minY + offset))
        }
        grid.stroke()
        NSColor.white.setStroke()
        let center = NSRect(x: loupe.midX - zoom / 2, y: loupe.midY - zoom / 2, width: zoom, height: zoom)
        NSBezierPath(rect: center).stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let ring = NSBezierPath(ovalIn: loupe.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2
        ring.stroke()
        let pixelLabel = "\(Int((point.x * screen.scale).rounded())), \(Int(((bounds.height - point.y) * screen.scale).rounded()))"
        drawLabel(pixelLabel, near: NSPoint(x: loupe.minX, y: loupe.minY - 4), anchorTop: true)
    }

    private func drawLabel(_ text: String, near point: NSPoint, anchorTop: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var box = NSRect(x: point.x + 6, y: point.y - size.height - 10, width: size.width + 12, height: size.height + 6)
        if anchorTop { box.origin = NSPoint(x: point.x, y: point.y - box.height) }
        box.origin.x = min(max(4, box.origin.x), bounds.width - box.width - 4)
        box.origin.y = min(max(4, box.origin.y), bounds.height - box.height - 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
    }
}

// MARK: - Mode bar

struct ScreenshotModeBar: View {
    enum Choice { case area, window, fullscreen, previous, cancel }
    let windowMode: Bool
    let previousAvailable: Bool
    let choose: (Choice) -> Void

    var body: some View {
        HStack(spacing: 6) {
            button("Alan", symbol: "rectangle.dashed", selected: !windowMode) { choose(.area) }
            button("Pencere", symbol: "macwindow", selected: windowMode) { choose(.window) }
            button("Tam Ekran", symbol: "display", selected: false) { choose(.fullscreen) }
            button("Önceki Alan", symbol: "arrow.uturn.backward.square", selected: false) { choose(.previous) }
                .disabled(!previousAvailable)
            Divider().frame(height: 28)
            Button { choose(.cancel) } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30) }
                .buttonStyle(.plain)
                .help("Vazgeç (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func button(_ title: LocalizedStringKey, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(selected ? Color.accentColor.opacity(0.85) : .clear, in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

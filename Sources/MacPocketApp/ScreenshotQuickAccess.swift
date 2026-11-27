import AppKit
import MacPocketCore
import SwiftUI
import MacPocketShared

/// The preview cards after each capture, stacked in the bottom-left corner of the screen under the pointer.
/// Hover for Copy, Save, Edit and Close; drag the picture into another app to hand over the file.
@MainActor
final class ScreenshotQuickAccess {
    static let shared = ScreenshotQuickAccess()
    private var cards: [QuickAccessCard] = []
    static let cardSize = NSSize(width: 236, height: 168)

    func show(_ capture: ScreenshotCapture) {
        let card = QuickAccessCard(capture: capture) { [weak self] card in self?.close(card) }
        cards.insert(card, at: 0)
        if cards.count > 5 { close(cards[cards.count - 1]) }
        layout(animated: true)
        card.present()
    }

    func close(_ card: QuickAccessCard) {
        card.dismiss()
        cards.removeAll { $0 === card }
        layout(animated: true)
    }
    func closeAll() {
        for card in cards { card.dismiss(animated: false) }
        cards = []
    }

    private func layout(animated: Bool) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        for (index, card) in cards.enumerated() {
            let frame = NSRect(x: area.minX + 16, y: area.minY + 16 + CGFloat(index) * (Self.cardSize.height + 10),
                               width: Self.cardSize.width, height: Self.cardSize.height)
            card.move(to: frame, animated: animated)
        }
    }
}

@MainActor
final class QuickAccessCard {
    let model: QuickAccessModel
    private let panel: QuickAccessPanel
    private var closeWork: DispatchWorkItem?

    init(capture: ScreenshotCapture, close: @escaping (QuickAccessCard) -> Void) {
        model = QuickAccessModel(capture: capture)
        panel = QuickAccessPanel()
        model.close = { [weak self] in if let self { close(self) } }
        model.hoverChanged = { [weak self] hovering in self?.scheduleAutoClose(paused: hovering) }
        panel.contentView = NSHostingView(rootView: QuickAccessCardView(model: model))
    }

    func present() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        scheduleAutoClose(paused: false)
    }

    func move(to frame: NSRect, animated: Bool) {
        if !panel.isVisible || !animated {
            panel.setFrame(frame.offsetBy(dx: -40, dy: 0), display: false)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    func dismiss(animated: Bool = true) {
        model.cancelOutput()
        closeWork?.cancel()
        closeWork = nil
        if !animated { panel.orderOut(nil); panel.contentView = nil; return }
        let panel = panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
    }

    private func scheduleAutoClose(paused: Bool) {
        closeWork?.cancel()
        guard !paused, let seconds = ScreenshotService.shared.settings.overlayAutoClose else { return }
        let work = DispatchWorkItem { [weak self] in self?.model.close?() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    }
}

private final class QuickAccessPanel: NSPanel, ScreenshotChrome {
    override var canBecomeKey: Bool { true }
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: ScreenshotQuickAccess.cardSize), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }
}

@MainActor
final class QuickAccessModel: ObservableObject {
    @Published var capture: ScreenshotCapture
    @Published var savedFlash = false
    @Published private(set) var working = false
    private var outputTask: Task<Void, Never>?
    private var active = true
    var close: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?

    init(capture: ScreenshotCapture) { self.capture = capture }

    var thumbnail: NSImage {
        NSImage(cgImage: capture.image, size: NSSize(width: CGFloat(capture.image.width) / capture.scale,
                                                    height: CGFloat(capture.image.height) / capture.scale))
    }

    func copy() {
        guard active, !working else { return }
        let capture = capture
        working = true
        outputTask = Task { [weak self] in
            guard let self else { return }
            defer { self.working = false; self.outputTask = nil }
            do {
                let data = try await ScreenshotAsyncOutput.encode(capture.image, format: .png, quality: 1, scale: Double(capture.scale))
                try Task.checkCancellation()
                guard self.active else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
                PocketToast.show(String(localized: "Panoya kopyalandı"), symbol: "doc.on.doc")
                self.close?()
            } catch is CancellationError {} catch { self.showError(error) }
        }
    }

    func save() {
        guard active, !working else { return }
        if let url = capture.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        let capture = capture
        working = true
        outputTask = Task { [weak self] in
            guard let self else { return }
            defer { self.working = false; self.outputTask = nil }
            do {
                let url = try await ScreenshotService.shared.saveAsync(capture)
                try Task.checkCancellation()
                guard self.active else { return }
                self.capture.fileURL = url
                self.savedFlash = true
            } catch is CancellationError {} catch { self.showError(error) }
        }
    }

    func cancelOutput() { active = false; outputTask?.cancel() }
    private func showError(_ error: Error) {
        guard active else { return }
        PocketToast.show(String(localized: "Görüntü dışa aktarılamadı: \(error.localizedDescription)"), symbol: "exclamationmark.triangle")
    }

    func edit() {
        guard active, !working else { return }
        ScreenshotEditor.open(capture) { [weak self] updated in self?.capture = updated }
        close?()
    }
    func pin() { guard active, !working else { return }; if ScreenshotService.shared.pin(capture) { close?() } }

    /// Saved files are immediate; unsaved long images use AppKit's background file-promise protocol.
    func dragWriter() -> (any NSPasteboardWriting)? {
        guard active, !working else { return nil }
        if let url = capture.fileURL, FileManager.default.fileExists(atPath: url.path) { return url as NSURL }
        return ScreenshotFilePromise(capture: capture, settings: ScreenshotService.shared.settings).provider()
    }

    func dragEnded(moved: Bool) {
        if moved && ScreenshotService.shared.settings.closeOverlayAfterDrag { close?() }
    }
}

private struct QuickAccessCardView: View {
    @ObservedObject var model: QuickAccessModel
    @State private var hovering = false

    var body: some View {
        ZStack {
            QuickAccessDragArea(model: model, image: model.thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if hovering {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.35)).allowsHitTesting(false)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        action("Kopyala", symbol: "doc.on.doc") { model.copy() }
                        action(model.capture.fileURL == nil ? "Kaydet" : "Göster", symbol: model.capture.fileURL == nil ? "square.and.arrow.down" : "folder") { model.save() }
                    }
                    HStack(spacing: 8) {
                        action("Düzenle", symbol: "pencil.tip.crop.circle") { model.edit() }
                        action("Sabitle", symbol: "pin") { model.pin() }
                    }
                }
                .disabled(model.working)
                VStack {
                    HStack {
                        Button { model.close?() } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22)
                                .background(.black.opacity(0.55), in: Circle()).foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Kapat")
                        .accessibilityLabel("Kapat")
                        Spacer()
                    }
                    Spacer()
                    Text(verbatim: "\(model.capture.image.width) × \(model.capture.image.height)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                }
                .padding(8)
            }
        }
        .padding(4)
        .adaptiveGlass(.regular, in: .rect(cornerRadius: 16))
        .onHover { hovering = $0; model.hoverChanged?($0) }
        .onChange(of: model.working) { model.hoverChanged?(model.working || hovering) }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Ekranda sabitle") { model.pin() }
            Button("Kopyala") { model.copy() }
            Button("Düzenle") { model.edit() }
            Button("Kapat") { model.close?() }
        }
        .overlay { if model.working { ProgressView().padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .accessibilityAction(named: Text("Ekranda sabitle")) { model.pin() }
    }

    private func action(_ title: LocalizedStringKey, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 26)
                .background(.white.opacity(0.92), in: Capsule())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
    }
}

/// The picture as an AppKit drag source: dragging hands the file to other apps and reports whether it was
/// dropped.
private struct QuickAccessDragArea: NSViewRepresentable {
    let model: QuickAccessModel
    let image: NSImage

    func makeNSView(context: Context) -> DragView { DragView(model: model, image: image) }
    func updateNSView(_ view: DragView, context: Context) { view.image = image; view.needsDisplay = true }

    final class DragView: NSView, NSDraggingSource {
        let model: QuickAccessModel
        var image: NSImage
        private var downPoint: NSPoint?

        init(model: QuickAccessModel, image: NSImage) {
            self.model = model
            self.image = image
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.25).setFill()
            bounds.fill()
            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = NSSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
        }

        override func mouseDown(with event: NSEvent) { downPoint = event.locationInWindow }

        override func mouseDragged(with event: NSEvent) {
            MainActor.assumeIsolated {
                guard let start = downPoint, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4,
                      let writer = model.dragWriter() else { return }
                downPoint = nil
                let item = NSDraggingItem(pasteboardWriter: writer)
                item.setDraggingFrame(bounds, contents: image)
                beginDraggingSession(with: [item], event: event, source: self)
            }
        }

        override func mouseUp(with event: NSEvent) {
            if downPoint != nil, event.clickCount == 2 { MainActor.assumeIsolated { model.edit() } }
            downPoint = nil
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy] : [.copy]
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            MainActor.assumeIsolated { model.dragEnded(moved: operation != []) }
        }
    }
}

import AppKit
import ImageIO
import MacPocketCore
import SwiftUI

@MainActor
final class ScreenshotPins: ObservableObject {
    @Published private(set) var items: [PinnedScreenshotModel] = []
    private var windows: [UUID: PinnedScreenshotWindow] = [:]
    private var screenObserver: NSObjectProtocol?
    private var retired: [PinnedScreenshotModel] = []
    var usedPixels: Int { (items + retired).reduce(0) { $0 + $1.capture.image.width * $1.capture.image.height } }

    @discardableResult func pin(_ capture: ScreenshotCapture) -> Bool {
        if let window = windows[capture.id] { window.orderFrontRegardless(); return true }
        guard ScreenshotPinPolicy.allows(width: capture.image.width, height: capture.image.height, count: items.count + retired.count, usedPixels: usedPixels),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            PocketToast.show(String(localized: "Sabitleme sınırına ulaşıldı. Önce sabit görüntülerden birini kapat."), symbol: "pin.slash")
            return false
        }
        let model = PinnedScreenshotModel(capture: capture)
        let window = PinnedScreenshotWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = String(localized: "Sabit Ekran Görüntüsü")
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 260, height: 200)
        window.onClose = { [weak self] in self?.close(capture.id) }
        model.outputFinished = { [weak self] in self?.retired.removeAll { !$0.working } }
        model.opacityChanged = { [weak window] in window?.alphaValue = $0 }
        window.contentView = NSHostingView(rootView: PinnedScreenshotView(model: model))
        window.setFrame(ScreenshotPinPolicy.frame(pixels: CGSize(width: capture.image.width, height: capture.image.height), scale: capture.scale,
                                                visible: screen.visibleFrame, anchor: NSEvent.mouseLocation), display: false)
        windows[capture.id] = window
        items.append(model)
        window.orderFrontRegardless()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refit() }
            }
        }
        return true
    }
    func show(_ id: UUID) { windows[id]?.orderFrontRegardless() }
    func close(_ id: UUID) {
        guard let model = items.first(where: { $0.id == id }) else { return }
        model.cancel()
        if model.working { retired.append(model) }
        let window = windows.removeValue(forKey: id)
        window?.onClose = nil
        window?.close()
        window?.contentView = nil
        items.removeAll { $0.id == id }
        if items.isEmpty, let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
    }
    func closeAll() { for item in items { close(item.id) } }
    private func refit() {
        guard let fallback = NSScreen.main else { return }
        for (id, window) in windows {
            guard let model = items.first(where: { $0.id == id }) else { continue }
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? fallback
            window.setFrame(ScreenshotPinPolicy.frame(pixels: CGSize(width: model.capture.image.width, height: model.capture.image.height),
                                                     scale: model.capture.scale, visible: screen.visibleFrame, anchor: center), display: true)
        }
    }
    #if DEBUG
    var diagnosticResources: [String: Int] { ["pins": items.count, "pinWindows": windows.count, "pinObserver": screenObserver == nil ? 0 : 1,
        "pinOutputs": items.filter(\.working).count + retired.filter(\.working).count] }
    func diagnosticWindow(_ id: UUID) -> NSWindow? { windows[id] }
    #endif
}

private final class PinnedScreenshotWindow: NSPanel, ScreenshotChrome {
    var onClose: (() -> Void)?
    private var closing = false
    override var canBecomeKey: Bool { true }
    override func close() {
        guard !closing else { return }
        closing = true
        let callback = onClose
        onClose = nil
        super.close()
        callback?()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
}

@MainActor
final class PinnedScreenshotModel: ObservableObject, Identifiable {
    nonisolated let id: UUID
    @Published private(set) var capture: ScreenshotCapture
    @Published var opacity = 1.0 { didSet { opacityChanged?(min(1, max(0.35, opacity))) } }
    @Published var zoom: Double = 0 // 0 fits; other values scale the capture's logical size.
    @Published private(set) var working = false
    var outputFinished: (() -> Void)?
    var opacityChanged: ((Double) -> Void)?
    private var task: Task<Void, Never>?
    private var active = true
    init(capture: ScreenshotCapture) { self.capture = capture; id = capture.id }
    func cancel() { active = false; task?.cancel() }
    func copy() {
        guard active, !working else { return }
        working = true
        let image = capture.image
        task = Task { [weak self] in
            defer { self?.working = false; self?.task = nil; self?.outputFinished?() }
            do {
                let data = try await ScreenshotAsyncOutput.encode(image, format: .png, quality: 1, scale: Double(self?.capture.scale ?? 1))
                try Task.checkCancellation()
                guard let self, self.active else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
                PocketToast.show(String(localized: "Panoya kopyalandı"), symbol: "doc.on.doc")
            } catch is CancellationError {} catch { PocketToast.show(error.localizedDescription, symbol: "exclamationmark.triangle") }
        }
    }
    func edit() {
        guard active else { return }
        ScreenshotEditor.open(capture) { [weak self] updated in self?.capture = updated }
    }
    func save() {
        guard active, !working else { return }
        if let file = capture.fileURL { NSWorkspace.shared.activateFileViewerSelecting([file]); return }
        working = true
        let current = capture
        task = Task { [weak self] in
            defer { self?.working = false; self?.task = nil; self?.outputFinished?() }
            do {
                let file = try await ScreenshotService.shared.saveAsync(current)
                try Task.checkCancellation()
                guard let self, self.active else { return }
                self.capture.fileURL = file
            } catch is CancellationError {} catch { PocketToast.show(error.localizedDescription, symbol: "exclamationmark.triangle") }
        }
    }
}

private struct PinnedScreenshotView: View {
    @ObservedObject var model: PinnedScreenshotModel
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { model.copy() } label: { Label("Kopyala", systemImage: "doc.on.doc") }.keyboardShortcut("c", modifiers: .command).help("Kopyala")
                Button { model.save() } label: {
                    if model.capture.fileURL == nil { Label("Kaydet", systemImage: "square.and.arrow.down") }
                    else { Label("Finder’da Göster", systemImage: "folder") }
                }.help(model.capture.fileURL == nil ? Text("Kaydet") : Text("Finder’da Göster"))
                Button { model.edit() } label: { Label("Düzenle", systemImage: "pencil") }.help("Düzenle")
                Spacer(minLength: 0)
                Picker("Yakınlaştırma", selection: $model.zoom) {
                    Text("Sığdır").tag(0.0)
                    Text(verbatim: "50%").tag(0.5)
                    Text(verbatim: "100%").tag(1.0)
                    Text(verbatim: "200%").tag(2.0)
                }.labelsHidden().frame(width: 105)
                    .pocketMenuPicker()
            }
            .labelStyle(.iconOnly).disabled(model.working)
            HStack {
                Text(verbatim: "\(model.capture.image.width) × \(model.capture.image.height)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Slider(value: $model.opacity, in: 0.35...1) { Text("Saydamlık") }.labelsHidden().frame(width: 100)
            }
            GeometryReader { proxy in
                PinnedImageCanvas(capture: model.capture, zoom: model.zoom, viewport: proxy.size)
            }
        }.padding(10).background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PinnedImageCanvas: NSViewRepresentable {
    let capture: ScreenshotCapture
    let zoom: Double
    let viewport: CGSize
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = Document()
        scroll.setAccessibilityLabel(String(localized: "Sabit ekran görüntüsü"))
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let document = scroll.documentView as? Document else { return }
        let scale = capture.scale.isFinite && capture.scale > 0 ? capture.scale : 1
        let points = CGSize(width: CGFloat(capture.image.width) / scale, height: CGFloat(capture.image.height) / scale)
        let factor = zoom > 0 ? CGFloat(zoom) : min(1, max(1, viewport.width - 16) / points.width, max(1, viewport.height - 16) / points.height)
        document.image = capture.image
        document.frame.size = CGSize(width: max(1, points.width * factor), height: max(1, points.height * factor))
        document.needsDisplay = true
    }
    final class Document: NSView {
        var image: CGImage?
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let image, let context = NSGraphicsContext.current?.cgContext, bounds.width > 0, bounds.height > 0 else { return }
            // Draw only the visible source rows: long captures never require a full-height display texture.
            let rect = dirtyRect.intersection(bounds)
            let sx = CGFloat(image.width) / bounds.width, sy = CGFloat(image.height) / bounds.height
            let pixels = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let crop = image.cropping(to: pixels) else { return }
            let destination = CGRect(x: pixels.minX / sx, y: pixels.minY / sy, width: pixels.width / sx, height: pixels.height / sy)
            context.saveGState()
            context.clip(to: rect)
            context.translateBy(x: destination.minX, y: destination.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(crop, in: CGRect(origin: .zero, size: destination.size))
            context.restoreGState()
        }
    }
}

enum ScreenshotAsyncOutput {
    private struct LoadError: LocalizedError {
        var errorDescription: String? { String(localized: "Görüntü okunamadı veya bellek sınırını aşıyor.") }
    }
    static func load(_ entry: ScreenshotHistoryEntry) async throws -> ScreenshotCapture {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: entry.path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = metadata[kCGImagePropertyPixelWidth] as? Int, let height = metadata[kCGImagePropertyPixelHeight] as? Int,
                  ScreenshotPinPolicy.allows(width: width, height: height, count: 0, usedPixels: 0),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw LoadError() }
            try Task.checkCancellation()
            let dpi = metadata[kCGImagePropertyDPIWidth] as? Double ?? 72
            let scale = dpi.isFinite && dpi > 0 ? min(8, max(0.25, dpi / 72)) : 1
            return ScreenshotCapture(image: image, scale: scale, fileURL: url, date: entry.date, mode: entry.mode)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    static func encode(_ image: CGImage, format: ScreenshotFormat, quality: Double, scale: Double = 1) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); let data = try ScreenshotEncoder.encode(image, as: format, quality: quality, scale: scale); try Task.checkCancellation(); return data }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    static func write(_ image: CGImage, to url: URL, format: ScreenshotFormat, quality: Double, scale: Double) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try ScreenshotEncoder.encode(image, as: format, quality: quality, scale: scale)
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}

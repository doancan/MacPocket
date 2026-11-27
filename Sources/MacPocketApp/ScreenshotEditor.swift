import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers
import MacPocketShared

/// The annotation editor: arrow, highlighter, pixelate and text over a capture, with undo, copy and save.
@MainActor
enum ScreenshotEditor {
    private static var windows: [NSWindow] = []
    private static var models: [Int: ScreenshotEditorModel] = [:]
    static var hasUnsavedChanges: Bool { models.values.contains { $0.dirty || $0.outputBusy || $0.editingText != nil } }
    static func closeAll() { for window in windows { window.close() } }
    #if DEBUG
    static var diagnosticWindows: Int { windows.count }
    static var diagnosticModel: ScreenshotEditorModel? { models.values.first }
    #endif

    static func open(_ capture: ScreenshotCapture, onSave: @escaping (ScreenshotCapture) -> Void = { _ in }) {
        guard ScreenshotService.shared.moduleRunning, !ScreenshotService.shared.busy else { return }
        let model = ScreenshotEditorModel(capture: capture, onSave: onSave)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let pointSize = NSSize(width: CGFloat(capture.image.width) / capture.scale, height: CGFloat(capture.image.height) / capture.scale)
        let fit = min(1, (area.width * 0.85) / pointSize.width, (area.height * 0.85 - 60) / pointSize.height)
        let size = NSSize(width: max(820, pointSize.width * fit + 120), height: max(520, pointSize.height * fit + 120))
        let window = ScreenshotEditorWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = capture.fileURL?.lastPathComponent ?? String(localized: "Ekran Görüntüsünü Düzenle")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScreenshotEditorView(model: model))
        window.center()
        windows.append(window)
        let number = window.windowNumber
        models[number] = model
        window.onClosed = {
            model.cancelOutput()
            models.removeValue(forKey: number)
            windows.removeAll { $0.windowNumber == number }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.window = window
    }
}

private final class ScreenshotEditorWindow: NSWindow, ScreenshotChrome {
    var onClosed: (() -> Void)?
    override func close() {
        let callback = onClosed
        onClosed = nil
        callback?()
        super.close()
        contentView = nil
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case arrow, highlight, pixelate, text
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .highlight: "highlighter"
        case .pixelate: "checkerboard.rectangle"
        case .text: "textformat"
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .arrow: "Ok"
        case .highlight: "Vurgulayıcı"
        case .pixelate: "Pikselleştir"
        case .text: "Metin"
        }
    }
}

@MainActor
final class ScreenshotEditorModel: ObservableObject {
    @Published private(set) var capture: ScreenshotCapture
    @Published private(set) var annotations: [Annotation] = [] { didSet { render() } }
    @Published private(set) var rendered: CGImage
    @Published var tool = EditorTool.arrow
    @Published var color = AnnotationColor.red
    /// 0 thin, 1 medium, 2 thick.
    @Published var weight = 1
    @Published var editingText: (point: CGPoint, text: String)?
    @Published private(set) var dirty = false
    @Published private(set) var outputBusy = false
    @Published private(set) var renderFailed = false
    private var outputTask: Task<Void, Never>?
    private var closed = false
    private var redoStack: [Annotation] = []
    private let onSave: (ScreenshotCapture) -> Void
    weak var window: NSWindow?

    init(capture: ScreenshotCapture, onSave: @escaping (ScreenshotCapture) -> Void) {
        self.capture = capture
        self.onSave = onSave
        rendered = capture.image
    }

    var imageSize: CGSize { CGSize(width: capture.image.width, height: capture.image.height) }

    /// Stroke width and text size in image pixels for the chosen weight.
    var strokeWidth: Double { [3.0, 5.0, 8.0][weight] * capture.scale }
    var textSize: Double { [16.0, 24.0, 36.0][weight] * capture.scale }
    var pixelBlock: Double { [8.0, 12.0, 18.0][weight] * capture.scale }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ annotation: Annotation) {
        guard !outputBusy, !closed else { return }
        annotations.append(annotation)
        redoStack.removeAll()
        dirty = true
    }

    func undo() {
        guard !outputBusy, !closed else { return }
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        dirty = true
    }

    func redo() {
        guard !outputBusy, !closed else { return }
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
        dirty = true
    }

    func commitText() {
        guard let editing = editingText else { return }
        editingText = nil
        let text = editing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { add(.text(text, at: editing.point, color: color, size: textSize)) }
    }

    private func render() {
        guard let image = AnnotationRenderer.render(capture.image, annotations: annotations) else { renderFailed = true; return }
        rendered = image
        renderFailed = false
    }

    // MARK: Output

    func copy() {
        guard !outputBusy, !closed else { return }
        commitText()
        guard !renderFailed else { return }
        let image = rendered, scale = Double(capture.scale)
        outputBusy = true
        outputTask = Task { [weak self] in
            guard let self else { return }
            defer { self.outputBusy = false; self.outputTask = nil }
            do {
                let data = try await ScreenshotAsyncOutput.encode(image, format: .png, quality: 1, scale: scale)
                try Task.checkCancellation()
                guard !self.closed else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
                PocketToast.show(String(localized: "Panoya kopyalandı"), symbol: "doc.on.doc")
            } catch is CancellationError {} catch { self.showOutputError(error) }
        }
    }
    func pin() {
        guard !outputBusy, !closed else { return }
        commitText()
        guard !renderFailed else { return }
        let current = dirty ? ScreenshotCapture(image: rendered, scale: capture.scale, fileURL: nil, date: Date(), mode: capture.mode) : capture
        _ = ScreenshotService.shared.pin(current)
    }

    /// Overwrites the capture's file, or saves a new one in the screenshot folder when it has none.
    func save() {
        guard !outputBusy, !closed else { return }
        commitText()
        guard !renderFailed else { return }
        saveUpdated(to: capture.fileURL)
    }

    func saveAs() {
        guard !outputBusy, !closed else { return }
        commitText()
        guard !renderFailed else { return }
        let panel = NSSavePanel()
        let format = ScreenshotService.shared.settings.format
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .png]
        panel.nameFieldStringValue = capture.fileURL?.lastPathComponent
            ?? ScreenshotFiles.url(in: URL(fileURLWithPath: "/"), at: capture.date, prefix: String(localized: "Ekran Resmi"), format: format) { _ in false }.lastPathComponent
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.saveUpdated(to: url)
            }
        }
    }

    private func saveUpdated(to url: URL?) {
        guard !outputBusy, !closed, !renderFailed else { return }
        var updated = capture
        updated.image = rendered
        let settings = ScreenshotService.shared.settings
        outputBusy = true
        outputTask = Task { [weak self] in
            guard let self else { return }
            defer { self.outputBusy = false; self.outputTask = nil }
            do {
                if let url {
                    let format = ScreenshotFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() } ?? settings.format
                    try await ScreenshotAsyncOutput.write(updated.image, to: url, format: format, quality: settings.quality, scale: Double(updated.scale))
                    updated.fileURL = url
                } else {
                    updated.fileURL = try await ScreenshotService.shared.saveAsync(updated)
                }
                try Task.checkCancellation()
                guard !self.closed else { return }
                if let url = updated.fileURL { ScreenshotService.shared.noteSaved(url, image: updated.image, mode: updated.mode) }
                self.finishSave(updated)
            } catch is CancellationError {} catch { self.showOutputError(error) }
        }
    }

    func cancelOutput() { closed = true; outputTask?.cancel() }
    private func showOutputError(_ error: Error) {
        guard !closed else { return }
        PocketToast.show(String(localized: "Görüntü dışa aktarılamadı: \(error.localizedDescription)"), symbol: "exclamationmark.triangle")
    }

    private func finishSave(_ updated: ScreenshotCapture) {
        capture = updated
        annotations = []
        redoStack = []
        dirty = false
        window?.title = updated.fileURL?.lastPathComponent ?? window?.title ?? ""
        onSave(updated)
        PocketToast.show(String(localized: "Kaydedildi"), symbol: "checkmark.circle")
    }
}

// MARK: - View

struct ScreenshotEditorView: View {
    @ObservedObject var model: ScreenshotEditorModel
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            GeometryReader { proxy in
                let fit = fitRect(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    EditorCanvasBackground()
                    Image(decorative: model.rendered, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                        .offset(x: fit.minX, y: fit.minY)
                    livePreview(fit: fit)
                    if let editing = model.editingText {
                        let point = toView(editing.point, fit: fit)
                        TextField("Metin", text: Binding(get: { model.editingText?.text ?? "" }, set: { model.editingText?.text = $0 }))
                            .textFieldStyle(.plain)
                            .font(.system(size: model.textSize / scaleFactor(fit: fit), weight: .bold))
                            .foregroundStyle(Color(cgColor: model.color.cgColor))
                            .frame(minWidth: 120, alignment: .leading)
                            .fixedSize()
                            .padding(2)
                            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3])) }
                            .offset(x: point.x - 2, y: point.y - 2)
                            .focused($textFocused)
                            .onSubmit { model.commitText() }
                            .onAppear { textFocused = true }
                    }
                }
                .contentShape(Rectangle())
                .gesture(drawGesture(fit: fit))
                .onTapGesture { location in tapped(at: location, fit: fit) }
                .overlay(alignment: .top) { hint.padding(.top, PocketSpacing.m) }
                .overlay(alignment: .leading) { toolRail.padding(.leading, PocketSpacing.m) }
            }
            .disabled(model.outputBusy)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background { KeyCommands(model: model) }
    }

    // MARK: Title bar

    /// The window's own title row: file name after the traffic lights, file actions on the right.
    private var titleBar: some View {
        HStack(spacing: PocketSpacing.s) {
            Text(verbatim: model.capture.fileURL?.lastPathComponent ?? String(localized: "Ekran Görüntüsünü Düzenle"))
                .font(.callout.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if model.dirty { Circle().fill(.secondary).frame(width: 6, height: 6).help("Kaydedilmemiş değişiklikler") }
            if model.outputBusy { ProgressView().controlSize(.small) }
            if model.renderFailed { Image(systemName: "exclamationmark.triangle").help("Görüntü işlenemedi; dışa aktarmadan önce son değişikliği geri al.") }
            Spacer(minLength: PocketSpacing.m)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Geri al (⌘Z)").accessibilityLabel("Geri al")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Yinele (⇧⌘Z)").accessibilityLabel("Yinele")
            Button("Kopyala") { model.copy() }
            Button("Sabitle") { model.pin() }
            Button("Farklı Kaydet…") { model.saveAs() }
            Button("Kaydet") { model.save() }
                .buttonStyle(.pocketPrimary)
                .keyboardShortcut("s", modifiers: .command)
        }
        .controlSize(.regular)
        .disabled(model.outputBusy)
        .padding(.leading, 84)
        .padding(.trailing, PocketSpacing.m)
        .frame(height: 44)
    }

    // MARK: Tool rail

    private var toolRail: some View {
        VStack(spacing: 6) {
            ForEach(EditorTool.allCases) { tool in
                Button { model.tool = tool } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(model.tool == tool ? .white : .white.opacity(0.85))
                        .background(model.tool == tool ? Color.accentColor : .clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tool.title)
                .accessibilityLabel(tool.title)
            }
            railSeparator
            LazyVGrid(columns: [GridItem(.fixed(22), spacing: 4), GridItem(.fixed(22), spacing: 4)], spacing: 4) {
                ForEach(AnnotationColor.palette, id: \.self) { color in
                    Button { model.color = color } label: {
                        Circle().fill(Color(cgColor: color.cgColor))
                            .frame(width: 16, height: 16)
                            .overlay { Circle().strokeBorder(.white.opacity(model.color == color ? 1 : 0.3), lineWidth: model.color == color ? 2 : 1) }
                            .padding(2)
                            .overlay { Circle().strokeBorder(Color.accentColor.opacity(model.color == color ? 0.95 : 0), lineWidth: 2) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 48)
            .disabled(model.tool == .pixelate)
            .opacity(model.tool == .pixelate ? 0.35 : 1)
            railSeparator
            ForEach(0..<3, id: \.self) { weight in
                Button { model.weight = weight } label: {
                    Circle().fill(.white).frame(width: CGFloat(5 + weight * 3), height: CGFloat(5 + weight * 3))
                        .frame(width: 30, height: 22)
                        .background(model.weight == weight ? Color.white.opacity(0.18) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Kalınlık")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .adaptiveGlass(.regular.tint(.black.opacity(0.35)), in: .rect(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
        .onChange(of: model.tool) { model.commitText() }
    }

    private var railSeparator: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 22, height: 1).padding(.vertical, 3)
    }

    private var hint: some View {
        Group {
            switch model.tool {
            case .arrow: Text("Ok çizmek için sürükle")
            case .highlight: Text("Vurgulamak için alan sürükle")
            case .pixelate: Text("Gizlemek için alan sürükle")
            case .text: Text("Metin eklemek için tıkla; bitirince ↩")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.black.opacity(0.35), in: Capsule())
        .allowsHitTesting(false)
    }

    // MARK: Geometry

    private func fitRect(in size: CGSize) -> CGRect {
        let image = model.imageSize
        let available = CGSize(width: max(1, size.width - 170), height: max(1, size.height - 80))
        let scale = min(available.width / image.width, available.height / image.height, 1 / max(1, model.capture.scale))
        let width = image.width * scale, height = image.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Image pixels per view point.
    private func scaleFactor(fit: CGRect) -> CGFloat { model.imageSize.width / max(1, fit.width) }

    private func toImage(_ point: CGPoint, fit: CGRect) -> CGPoint {
        let factor = scaleFactor(fit: fit)
        return CGPoint(x: (point.x - fit.minX) * factor, y: (point.y - fit.minY) * factor)
    }

    private func toView(_ point: CGPoint, fit: CGRect) -> CGPoint {
        let factor = scaleFactor(fit: fit)
        return CGPoint(x: point.x / factor + fit.minX, y: point.y / factor + fit.minY)
    }

    // MARK: Drawing

    private func drawGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard model.tool != .text else { return }
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil }
                guard model.tool != .text else { return }
                let start = toImage(value.startLocation, fit: fit), end = toImage(value.location, fit: fit)
                let rect = ScreenshotGeometry.rect(from: start, to: end)
                switch model.tool {
                case .arrow: model.add(.arrow(from: start, to: end, color: model.color, width: model.strokeWidth))
                case .highlight: if rect.width > 2, rect.height > 2 { model.add(.highlight(rect, color: model.color)) }
                case .pixelate: if rect.width > 2, rect.height > 2 { model.add(.pixelate(rect, block: model.pixelBlock)) }
                case .text: break
                }
            }
    }

    private func tapped(at location: CGPoint, fit: CGRect) {
        guard model.tool == .text, fit.contains(location) else { model.commitText(); return }
        model.commitText()
        model.editingText = (toImage(location, fit: fit), "")
    }

    @ViewBuilder
    private func livePreview(fit: CGRect) -> some View {
        if let start = dragStart, let current = dragCurrent {
            let color = Color(cgColor: model.color.cgColor)
            switch model.tool {
            case .arrow:
                ArrowShape(from: start, to: current, width: model.strokeWidth / scaleFactor(fit: fit))
                    .fill(color)
            case .highlight:
                Path(ScreenshotGeometry.rect(from: start, to: current)).fill(color.opacity(0.4)).blendMode(.multiply)
            case .pixelate:
                Path(ScreenshotGeometry.rect(from: start, to: current))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 1, dash: [4]))
            case .text:
                EmptyView()
            }
        }
    }
}

/// A filled arrow (shaft and head) for the live preview; same proportions as the renderer.
private struct ArrowShape: Shape {
    let from: CGPoint, to: CGPoint, width: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 1 else { return path }
        let head = Annotation.arrowHead(width: width)
        let headLength = min(head.length, length * 0.6)
        let ux = dx / length, uy = dy / length
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        path.addPath(Path { shaft in shaft.move(to: from); shaft.addLine(to: base) }
            .strokedPath(StrokeStyle(lineWidth: width, lineCap: .round)))
        path.move(to: to)
        path.addLine(to: CGPoint(x: base.x - uy * head.halfWidth, y: base.y + ux * head.halfWidth))
        path.addLine(to: CGPoint(x: base.x + uy * head.halfWidth, y: base.y - ux * head.halfWidth))
        path.closeSubpath()
        return path
    }
}

/// ⌘Z / ⇧⌘Z and Esc for the editor window.
private struct KeyCommands: View {
    @ObservedObject var model: ScreenshotEditorModel
    var body: some View {
        ZStack {
            Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command)
            Button("") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            Button("") { model.copy() }.keyboardShortcut("c", modifiers: .command).disabled(model.editingText != nil)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dark canvas with a faint dot grid, so any screenshot (light or dark) stands out.
private struct EditorCanvasBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [Color(white: 0.24), Color(white: 0.13)]),
                                               center: CGPoint(x: size.width / 2, y: size.height * 0.4), startRadius: 0,
                                               endRadius: max(size.width, size.height) * 0.75))
            let spacing: CGFloat = 16
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.07)))
                    x += spacing
                }
                y += spacing
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

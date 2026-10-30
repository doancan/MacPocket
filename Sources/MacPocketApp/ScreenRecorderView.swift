import AppKit
import AVFoundation
import MacPocketCore
import ScreenCaptureKit
import SwiftUI

/// Records the display under the pointer with ScreenCaptureKit (macOS 15+), including system audio and the
/// microphone if wanted, which the system's ⇧⌘5 recorder can't capture. MacPocket's own windows are left out.
@MainActor
final class ScreenRecorderService: NSObject, ObservableObject {
    static let shared = ScreenRecorderService()

    @Published var settings = ScreenRecordingSettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            registerShortcut()
        }
    }
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastFile: URL?
    @Published private(set) var message: String?
    var recordingShortcut = false { didSet { registerShortcut() } }

    private var stream: AnyObject?
    private var output: AnyObject?
    private var file: URL?
    private lazy var hotKey = PocketGlobalHotKey { [weak self] in Task { await self?.toggle() } }
    private let hud = RecordingHUD()

    static var isSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    var isRecording: Bool { startedAt != nil }

    func start() { registerShortcut() }

    private func registerShortcut() {
        if let shortcut = settings.shortcut, !recordingShortcut, Self.isSupported { hotKey.register(shortcut) } else { hotKey.unregister() }
    }

    var folder: URL {
        settings.folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
    }

    func toggle() async {
        isRecording ? await stop() : await begin()
    }

    func begin() async {
        guard #available(macOS 15.0, *), !isRecording else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            message = String(localized: "Kayıt için MacPocket’e Ekran Kaydı izni ver; sonra tekrar dene.")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let pointer = NSEvent.mouseLocation
            let screenID = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }?
                .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            guard let display = content.displays.first(where: { $0.displayID == screenID?.uint32Value }) ?? content.displays.first else {
                message = String(localized: "Kaydedilecek ekran bulunamadı.")
                return
            }
            let ownApps = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }?
                .backingScaleFactor ?? 2
            configuration.width = Int(Double(display.width) * scale)
            configuration.height = Int(Double(display.height) * scale)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
            configuration.showsCursor = settings.showCursor
            configuration.capturesAudio = settings.systemAudio
            configuration.excludesCurrentProcessAudio = true
            configuration.captureMicrophone = settings.microphone

            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = ScreenRecordingFiles.url(in: folder, at: Date(), prefix: String(localized: "Ekran Kaydı")) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = file
            recordingConfiguration.outputFileType = .mov
            recordingConfiguration.videoCodecType = settings.codec == .hevc ? .hevc : .h264
            let recording = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addRecordingOutput(recording)
            try await stream.startCapture()
            self.stream = stream
            output = recording
            self.file = file
            startedAt = Date()
            message = nil
            hud.show(startedAt: startedAt!, stop: { [weak self] in Task { await self?.stop() } })
        } catch {
            message = String(localized: "Kayıt başlatılamadı: \(error.localizedDescription)")
        }
    }

    func stop() async {
        guard #available(macOS 15.0, *), let stream = stream as? SCStream else { return }
        hud.hide()
        do { try await stream.stopCapture() } catch { message = error.localizedDescription }
        self.stream = nil
        output = nil
        startedAt = nil
        if let file {
            lastFile = file
            PocketToast.show(String(localized: "Kayıt kaydedildi: \(file.lastPathComponent)"), symbol: "record.circle")
        }
        file = nil
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.folder = url.path
    }
}

@available(macOS 15.0, *)
extension ScreenRecorderService: SCRecordingOutputDelegate {
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let text = error.localizedDescription
        Task { @MainActor in
            self.message = String(localized: "Kayıt durdu: \(text)")
            await self.stop()
        }
    }
}

/// Elapsed time and a stop button, top centre; left out of the recording with the rest of MacPocket.
@MainActor
final class RecordingHUD {
    private var panel: NSPanel?

    func show(startedAt: Date, stop: @escaping () -> Void) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: RecordingHUDView(startedAt: startedAt, stop: stop))
        if let screen = NSScreen.main {
            let size = NSSize(width: 260, height: 60)
            panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 16,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecordingHUDView: View {
    let startedAt: Date
    let stop: () -> Void

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false).font(.callout.weight(.semibold)).monospacedDigit()
            Spacer(minLength: 0)
            // Plain on the glass HUD: a glass button here would be glass on glass.
            Button("Durdur", action: stop).buttonStyle(.borderless).foregroundStyle(.red).font(.callout.weight(.semibold))
        }
        .padding(.horizontal, PocketSpacing.l)
        .frame(height: 46)
        .modifier(RecordingHUDSurface())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecordingHUDSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule()).overlay { Capsule().strokeBorder(PocketTheme.line) }
        }
    }
}

/// Tools → Ekran Kaydı.
struct ScreenRecorderView: View {
    @ObservedObject private var service = ScreenRecorderService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekran Kaydı",
                              subtitle: "İmlecin bulunduğu ekranı sistem sesi ve istersen mikrofonla birlikte kaydet; ⇧⌘5’in kaydedemediği sesi de alır.",
                              icon: "record.circle") {
                if ScreenRecorderService.isSupported {
                    Button { Task { await service.toggle() } } label: {
                        Label(service.isRecording ? "Durdur" : "Kaydı başlat", systemImage: service.isRecording ? "stop.fill" : "record.circle")
                    }
                    .buttonStyle(.pocketPrimary)
                    .controlSize(.large)
                }
            }
            if !ScreenRecorderService.isSupported {
                PocketMessage("Ses dahil kayıt macOS 15 veya sonrası gerektirir. Bu sürümde ⇧⌘5 ile sessiz kayıt alabilirsin.", tone: .warning)
            }
            if let message = service.message { PocketMessage(message, tone: .warning) }
            if let start = service.startedAt {
                HStack(spacing: PocketSpacing.m) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Kaydediliyor").font(.headline)
                    Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
                }
                .pocketCard()
            }
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Ayarlar", icon: "slider.horizontal.3")
                Toggle("Sistem sesini kaydet", isOn: $service.settings.systemAudio)
                Toggle("Mikrofonu kaydet", isOn: $service.settings.microphone)
                Toggle("İmleci göster", isOn: $service.settings.showCursor)
                HStack(spacing: PocketSpacing.xl) {
                    Picker("Kare hızı", selection: $service.settings.framesPerSecond) {
                        ForEach(ScreenRecordingSettings.frameRateChoices, id: \.self) { Text("\($0) kare/sn").tag($0) }
                    }
                    .fixedSize()
                    Picker("Biçim", selection: $service.settings.codec) {
                        Text("HEVC (küçük dosya)").tag(ScreenRecordingSettings.Codec.hevc)
                        Text("H.264 (her yerde açılır)").tag(ScreenRecordingSettings.Codec.h264)
                    }
                    .fixedSize()
                }
                LabeledContent("Kayıt klasörü") {
                    HStack {
                        Text(service.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).foregroundStyle(.secondary).lineLimit(1)
                        Button("Değiştir…") { service.chooseFolder() }
                    }
                }
                LabeledContent("Başlat / durdur") {
                    KeyComboRecorder(combo: $service.settings.shortcut, allowsClearing: true, recording: { service.recordingShortcut = $0 })
                }
            }
            .disabled(service.isRecording)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
            if let file = service.lastFile {
                HStack {
                    Image(systemName: "film")
                    Text(file.lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    Button("Aç") { NSWorkspace.shared.open(file) }
                }
                .pocketCard()
            }
            Spacer(minLength: 0)
        }
        .pocketPage()
    }
}

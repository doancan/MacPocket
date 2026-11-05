import AppKit
import MacPocketCore
@preconcurrency import ScreenCaptureKit
import SwiftUI

private actor ScrollImageAssembler {
    private var stitch = ScrollScreenshotStitcher()
    private var observed: CGImage?
    struct Progress: Sendable {
        let update: ScrollScreenshotStitcher.Update?
        let width: Int
        let height: Int
        let sections: Int
    }
    func receive(_ image: CGImage) throws -> Progress {
        try Task.checkCancellation()
        defer { observed = image }
        guard let observed, ScrollScreenshotStitcher.difference(observed, image) < 0.8 else {
            return Progress(update: nil, width: stitch.width, height: stitch.height, sections: stitch.sections)
        }
        let update = try stitch.append(image)
        return Progress(update: update, width: stitch.width, height: stitch.height, sections: stitch.sections)
    }
    func finish() throws -> CGImage { try stitch.render() }
}

@MainActor
final class ScrollingScreenshotSession: ObservableObject {
    typealias FrameSource = @MainActor () async throws -> CGImage
    struct Result { let image: CGImage; let partial: Bool; let limited: Bool }
    @Published private(set) var height = 0
    @Published private(set) var sections = 0
    @Published private(set) var status = String(localized: "Çekim hazırlanıyor…")
    @Published private(set) var finishing = false
    private var cancelled = false
    private var finishAt: TimeInterval?
    private var window: ScrollCaptureWindow?
    private var keyMonitor: Any?
    private var assembler = ScrollImageAssembler()

    func requestFinish() { guard finishAt == nil else { return }; finishAt = ProcessInfo.processInfo.systemUptime; finishing = true }
    func cancel() { cancelled = true; close() }

    func run(frame: CGRect, source: @escaping FrameSource, maximumDuration: TimeInterval = 90) async throws -> Result? {
        show(near: frame)
        defer { close(); assembler = ScrollImageAssembler() }
        let start = ProcessInfo.processInfo.systemUptime
        var partial = false, limited = false
        while !cancelled {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            if now - start >= maximumDuration { limited = true; break }
            let image: CGImage
            do { image = try await source() }
            catch {
                if Task.isCancelled || cancelled { return nil }
                if sections == 0 { throw error }; partial = true; break
            }
            try Task.checkCancellation(); if cancelled { return nil }
            let progress = try await assembler.receive(image)
            height = progress.height; sections = progress.sections
            switch progress.update {
            case .started?, .appended?: status = String(localized: "Aşağı kaydır; yeni bölümler ekleniyor."); partial = false
            case .unmatched?, .ambiguous?:
                status = String(localized: "Son hareket eşleşmedi. Biraz yukarı dönüp daha yavaş kaydır."); partial = true
            case .revisited?: status = String(localized: "Bu bölüm zaten çekildi; aşağı kaydırarak devam et."); partial = false
            case .limitReached?: limited = true
            case .unchanged?: break
            case nil: status = String(localized: "Görüntünün durulması bekleniyor…"); partial = true
            }
            if limited { break }
            let current = ProcessInfo.processInfo.systemUptime
            if let finishAt, sections > 0, (progress.update != nil || current - finishAt > 1) { break }
            // Finishing a view that never settled must fail rather than returning invented output.
            if let finishAt, current - finishAt > 2 { break }
            try await Task.sleep(for: .milliseconds(140))
        }
        if cancelled || Task.isCancelled { return nil }
        finishing = true; status = String(localized: "Uzun görüntü hazırlanıyor…")
        return Result(image: try await assembler.finish(), partial: partial, limited: limited)
    }

    /// Cache the filter once. Each request captures only the selected region; no scrolling/input permission is used.
    static func source(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat) async throws -> FrameSource {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0,
              scale.isFinite, scale > 0 else { throw ScreenshotService.CaptureError.noDisplay }
        let ids = Set(NSApp.windows.filter { $0 is ScreenshotChrome }.map { CGWindowID($0.windowNumber) })
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { ids.contains($0.windowID) })
        let config = SCStreamConfiguration()
        config.sourceRect = rect; config.width = Int((rect.width * scale).rounded()); config.height = Int((rect.height * scale).rounded())
        config.showsCursor = false; config.captureResolution = .best; config.capturesAudio = false
        return {
            try Task.checkCancellation()
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation(); return image
        }
    }
    // Create chrome before caching the filter so the HUD never feeds back into the capture.
    func prepare(near frame: CGRect) { show(near: frame) }
    private func show(near frame: CGRect) {
        guard window == nil, let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) ?? NSScreen.main else { return }
        let window = ScrollCaptureWindow(contentRect: .zero, styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = String(localized: "Kaydırmalı Ekran Görüntüsü")
        window.isReleasedWhenClosed = false; window.level = .floating; window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: ScrollCaptureHUD(session: self))
        let area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(440, area.width), height: CGFloat = 190
        let y = frame.minY - height - 12 >= area.minY ? frame.minY - height - 12 : min(area.maxY - height, frame.maxY + 12)
        window.setFrame(CGRect(x: min(max(area.minX, frame.midX - width / 2), area.maxX - width), y: max(area.minY, y), width: width, height: height), display: false)
        self.window = window; window.orderFrontRegardless()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard event.window === window, event.keyCode == 53 else { return false }; self?.cancel(); return true
            }
            return consumed ? nil : event
        }
    }
    private func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil
        window?.close(); window?.contentView = nil; window = nil
    }
    #if DEBUG
    var diagnosticWindow: NSWindow? { window }
    var diagnosticResources: Int { (window == nil ? 0 : 1) + (keyMonitor == nil ? 0 : 1) }
    #endif
}

private final class ScrollCaptureWindow: NSPanel, ScreenshotChrome { override var canBecomeKey: Bool { true } }
private struct ScrollCaptureHUD: View {
    @ObservedObject var session: ScrollingScreenshotSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Yalnız kaydırılan içeriği seç. Yavaşça aşağı kaydır; Bitir ile görüntüyü hazırla.").font(.callout)
            Text(session.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(session.sections) bölüm · \(session.height) piksel").font(.caption).monospacedDigit()
                Spacer()
                Button("Vazgeç") { session.cancel() }
                Button("Bitir") { session.requestFinish() }.disabled(session.finishing).buttonStyle(.borderedProminent)
            }
        }.padding(12).background(Color(nsColor: .windowBackgroundColor))
    }
}

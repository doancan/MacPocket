#if DEBUG
import AppKit
import ImageIO
import MacPocketCore
import SwiftUI

/// Synthetic frames through the production session and output pipeline. Never captures the desktop or writes
/// the clipboard.
@MainActor enum ScreenshotRuntimeAudit {
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested else { return [:] }
        let runtime = PocketModuleRuntime.shared, service = ScreenshotService.shared
        let original = service.settings
        var settings = original
        settings.shortcuts = [:]
        settings.copyToClipboard = false
        settings.saveToFolder = false
        settings.showOverlay = false
        settings.playSound = false
        service.settings = settings
        runtime.setAvailable(.screenshot, true)
        defer { service.stopForModule(); runtime.setAvailable(.screenshot, false); service.settings = original }
        var checks: [String: Bool] = [:]
        let first = frame(top: 0), second = frame(top: 80)
        let session = ScrollingScreenshotSession()
        var calls = 0
        let source: ScrollingScreenshotSession.FrameSource = {
            try await Task.sleep(for: .milliseconds(25))
            calls += 1
            if calls == 4 { session.requestFinish() }
            return calls <= 2 ? first : second
        }
        checks["screenshotClaimsBusySynchronously"] = service.diagnosticCapture(session, source: source) && service.busy
        checks["screenshotRejectsConcurrentCapture"] = !service.diagnosticCapture(ScrollingScreenshotSession(), source: source)
        _ = await waitUntil { session.diagnosticWindow?.isVisible == true }
        if let hud = session.diagnosticWindow {
            let nodes = snapshot(hud, to: destination.appendingPathExtension("scroll-hud.png"))
            checks["screenshotHudFinishCancelAccessible"] = [String(localized: "Bitir"), String(localized: "Vazgeç")].allSatisfy { title in nodes.contains { $0["name"] == title } }
        }
        checks["screenshotSessionCompletes"] = await waitUntil { !service.busy }
        checks["screenshotSessionStitchesExpectedHeight"] = service.latestCapture?.image.height == first.height + 80
        checks["screenshotSessionPreservesSourceScale"] = service.latestCapture?.scale == 2
        checks["screenshotSessionReleasesHud"] = session.diagnosticResources == 0 && service.moduleDiagnosticResources["captureTask"] == 0
        checks["screenshotSessionDoesNotSaveWhenDisabled"] = service.latestCapture?.fileURL == nil
        if let root = ModuleRuntimeAudit.dataURL("screenshot-exports-" + UUID().uuidString) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let capture = ScreenshotCapture(image: first, scale: 2, fileURL: nil, date: Date(), mode: .scrolling)
            var exportSettings = settings
            exportSettings.format = .png
            let writer = ScreenshotFilePromise(capture: capture, settings: exportSettings), url = root.appendingPathComponent("promise.png")
            let provider = writer.provider()
            checks["screenshotPromiseRetainsDelegate"] = provider.userInfo as AnyObject === writer
            checks["screenshotPromiseUsesBackgroundQueue"] = writer.operationQueue(for: provider) !== OperationQueue.main
            do {
                try await Task.detached { try writer.write(to: url) }.value
                let entry = ScreenshotHistoryEntry(path: url.path, date: Date(), mode: .scrolling, pixelWidth: first.width, pixelHeight: first.height)
                let loaded = try await ScreenshotAsyncOutput.load(entry)
                checks["screenshotExportRoundTripPreservesGeometryScale"] = loaded.image.width == first.width && loaded.image.height == first.height && loaded.scale == 2
                do { try await Task.detached { try writer.write(to: url) }.value; checks["screenshotPromiseNeverOverwrites"] = false }
                catch { checks["screenshotPromiseNeverOverwrites"] = true }
            } catch { checks["screenshotExportRoundTripPreservesGeometryScale"] = false }
        }
        let latest = service.latestCapture?.id

        let cancelled = ScrollingScreenshotSession()
        _ = service.diagnosticCapture(cancelled) {
            // ScreenCaptureKit can finish an in-flight request after cancellation. Model that late
            // completion.
            try await Task.detached { try await Task.sleep(for: .milliseconds(200)); return first }.value
        }
        _ = await waitUntil { cancelled.diagnosticResources > 0 }
        service.cancelCapture()
        checks["screenshotCancellationDrainsTask"] = await waitUntil { !service.busy }
        checks["screenshotCancellationPreventsPublication"] = service.latestCapture?.id == latest && cancelled.diagnosticResources == 0

        let interrupted = ScrollingScreenshotSession()
        var frames = 0
        do {
            let partial = try await interrupted.run(frame: CGRect(x: 100, y: 100, width: 320, height: 280), source: {
                frames += 1
                if frames > 2 { throw CocoaError(.fileReadCorruptFile) }
                return first
            })
            checks["screenshotSourceFailurePreservesOnlyTrustedImage"] = partial?.partial == true && partial?.image.height == first.height
            checks["screenshotSourceFailureClosesHud"] = interrupted.diagnosticResources == 0
        } catch { checks["screenshotSourceFailurePreservesOnlyTrustedImage"] = false }

        let pinned = ScreenshotCapture(image: frame(top: 0, height: 1400), scale: 2, fileURL: nil, date: Date(), mode: .scrolling)
        checks["screenshotPinOpens"] = service.pin(pinned)
        checks["screenshotPinDeduplicatesSameCapture"] = service.pin(pinned) && service.pins.items.count == 1
        if let model = service.pins.items.first, let window = service.pins.diagnosticWindow(pinned.id) {
            _ = await waitUntil { scrollView(window.contentView)?.documentView?.bounds.height ?? 0 > 0 }
            checks["screenshotPinFloatsAcrossSpaces"] = window.level == .floating && window.collectionBehavior.contains(.canJoinAllSpaces)
            checks["screenshotPinFitsScreen"] = NSScreen.screens.contains { $0.visibleFrame.contains(window.frame) }
            model.opacity = 0.5
            checks["screenshotPinOpacityUpdatesNativeWindow"] = window.alphaValue == 0.5
            model.opacity = 1
            model.zoom = 1
            _ = await waitUntil { (scrollView(window.contentView)?.documentView?.bounds.height ?? 0) > 650 }
            checks["screenshotPinFullSizeUsesScrollableCanvas"] = scrollView(window.contentView)?.documentView?.bounds.height == 700
            let nodes = snapshot(window, to: destination.appendingPathExtension("screenshot-pin.png"))
            checks["screenshotPinControlsAccessible"] = [String(localized: "Kopyala"), String(localized: "Düzenle"), String(localized: "Yakınlaştırma"), String(localized: "Saydamlık")].allSatisfy { title in nodes.contains { $0["name"] == title } }
        }
        let preview = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 740), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        preview.contentView = NSHostingView(rootView: ScrollView { ScreenshotView().padding(20) }.background { PocketTheme.background })
        preview.center()
        preview.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(350))
        let pageNodes = snapshot(preview, to: destination.appendingPathExtension("screenshot-tool.png"))
        checks["screenshotScrollingModeAccessible"] = pageNodes.contains { $0["name"]?.contains(String(localized: "Kaydırmalı")) == true }
        if let scroll = scrollView(preview.contentView), let document = scroll.documentView {
            document.scroll(CGPoint(x: 0, y: max(0, document.bounds.height - scroll.contentSize.height)))
            try? await Task.sleep(for: .milliseconds(100))
            _ = snapshot(preview, to: destination.appendingPathExtension("screenshot-tool-pins.png"))
        }
        preview.close()
        preview.contentView = nil

        ScreenshotEditor.open(pinned)
        checks["screenshotEditorTracked"] = ScreenshotEditor.diagnosticWindows == 1
        if let editor = ScreenshotEditor.diagnosticModel {
            editor.add(.highlight(CGRect(x: 5, y: 5, width: 40, height: 40), color: .red))
            checks["screenshotUnsavedEditsBlockModuleStop"] = !service.canSuspendModule
            runtime.setAvailable(.screenshot, false)
            checks["screenshotRuntimeProtectsUnsavedEdits"] = runtime.available.contains(.screenshot)
        }
        ScreenshotEditor.closeAll()
        checks["screenshotEditorReleasesOnClose"] = ScreenshotEditor.diagnosticWindows == 0 && service.canSuspendModule
        service.pins.diagnosticWindow(pinned.id)?.performClose(nil)
        checks["screenshotNativeCloseReleasesPinResources"] = service.pins.diagnosticResources.values.allSatisfy { $0 == 0 }

        let sleeping = ScrollingScreenshotSession()
        _ = service.diagnosticCapture(sleeping) { try await Task.sleep(for: .seconds(2)); return first }
        _ = await waitUntil { sleeping.diagnosticResources > 0 }
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        checks["screenshotDisplayChangeCancelsSession"] = await waitUntil { !service.busy && sleeping.diagnosticResources == 0 }
        _ = service.pin(pinned)
        let closing = ScrollingScreenshotSession()
        _ = service.diagnosticCapture(closing) {
            try await Task.detached { try await Task.sleep(for: .milliseconds(200)); return first }.value
        }
        _ = await waitUntil { closing.diagnosticResources > 0 }
        service.stopForModule()
        checks["screenshotStopDrainsLateCapture"] = await waitUntil { !service.busy }
        checks["screenshotModuleStopClearsAllResources"] = service.moduleDiagnosticResources.values.allSatisfy { $0 == 0 } && service.latestCapture == nil
        checks["screenshotDisabledModuleRejectsPins"] = !service.pin(pinned)
        return checks
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + 8
        repeat { if condition() { return true }; try? await Task.sleep(for: .milliseconds(25)) } while ProcessInfo.processInfo.systemUptime < end
        return condition()
    }
    private static func scrollView(_ view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView($0) }.first
    }
    private static func snapshot(_ window: NSWindow, to url: URL) -> [[String: String]] {
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        }
        let nodes = ToolUIAudit.accessibilityNodes(window)
        if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url.appendingPathExtension("ax.json")) }
        return nodes
    }
    private static func frame(top: Int, height: Int = 280) -> CGImage {
        let width = 320
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let seed = (UInt32(top + y) &* 2_654_435_761) ^ (UInt32(x) &* 2_246_822_519), i = (y * width + x) * 4
            bytes[i] = UInt8(truncatingIfNeeded: seed >> 4)
            bytes[i + 1] = UInt8(truncatingIfNeeded: seed >> 12)
            bytes[i + 2] = UInt8(truncatingIfNeeded: seed >> 20)
        } }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
#endif

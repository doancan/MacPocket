import AppKit
import ScreenCaptureKit

public enum WindowPreviewError: Error, LocalizedError {
    case permissionRequired, ambiguous, unavailable, expired
    public var errorDescription: String? {
        switch self {
        case .permissionRequired: String(localized: "Önizleme için macOS Ekran Kaydı izni gerekiyor.")
        case .ambiguous: String(localized: "Pencere güvenle eşleştirilemedi; yanlış pencereyi göstermemek için önizleme alınmadı.")
        case .unavailable: String(localized: "Pencere görüntüsü şu anda alınamıyor.")
        case .expired: String(localized: "Uygulama yeniden başlatıldı. Pencere listesini yenile.")
        }
    }
}

/// A captured window image. CGImage is immutable, so sharing it across actors is safe.
public struct WindowImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let capturedAt: Date

    public init(cgImage: CGImage, capturedAt: Date = Date()) {
        self.cgImage = cgImage; self.capturedAt = capturedAt
    }
}

public protocol WindowPreviewCapturing: Sendable {
    func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage
}

public enum WindowPreviewSizing {
    /// Preserve native Retina detail, bounded by the caller's pixel budget. Never upscale the source.
    public static func pixels(contentSize: CGSize, pixelScale: CGFloat, maxPixels: CGSize) -> CGSize? {
        guard [contentSize.width, contentSize.height, pixelScale, maxPixels.width, maxPixels.height]
            .allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let scale = min(pixelScale, min(16_384, maxPixels.width) / contentSize.width, min(16_384, maxPixels.height) / contentSize.height)
        return CGSize(width: max(1, floor(contentSize.width * scale)), height: max(1, floor(contentSize.height * scale)))
    }
}

/// Captures windows by WindowServer id, in memory only; images are never saved or transmitted.
public actor WindowPreviewProvider: WindowPreviewCapturing {
    /// ScreenCaptureKit exposes an immutable inventory snapshot; it is shared read-only by callers
    /// awaiting the same discovery, never mutated across actors.
    private struct ContentSnapshot: @unchecked Sendable { let value: SCShareableContent }
    private var content: SCShareableContent?
    private var contentFetchedAt = Date.distantPast
    private var contentRequest: Task<ContentSnapshot, Error>?
    public init() {}
    public static var permitted: Bool { CGPreflightScreenCaptureAccess() }
    @MainActor public static func requestPermission() { CGRequestScreenCaptureAccess() }

    /// Captures `window` scaled to fit `maxPixels` (never upscaled).
    public func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage {
        try Task.checkCancellation()
        guard window.canCapturePreview else { throw WindowPreviewError.unavailable }
        guard Self.permitted else { throw WindowPreviewError.permissionRequired }
        let live = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: window.processID), !app.isTerminated else { return false }
            return CatalogWindowIdentity.matchesProcessLaunch(expected: window.launchedAt,
                actual: CatalogWindowIdentity.processLaunchDate(pid: window.processID, applicationDate: app.launchDate))
        }
        guard live else { throw WindowPreviewError.expired }
        guard maxPixels.width.isFinite, maxPixels.height.isFinite, maxPixels.width > 0, maxPixels.height > 0 else { throw WindowPreviewError.unavailable }
        let target = try await scWindow(for: window)
        try Task.checkCancellation()
        let filter = SCContentFilter(desktopIndependentWindow: target)
        guard let pixels = WindowPreviewSizing.pixels(contentSize: filter.contentRect.size, pixelScale: CGFloat(filter.pointPixelScale),
                                                     maxPixels: maxPixels) else { throw WindowPreviewError.unavailable }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return WindowImage(cgImage: image, capturedAt: Date())
    }

    /// PNG for callers that need encoded data (diagnostics, CLI).
    public func preview(_ window: SwitchableWindow) async throws -> Data {
        let image = try await image(for: window, maxPixels: CGSize(width: 840, height: 520))
        guard let data = NSBitmapImageRep(cgImage: image.cgImage).representation(using: .png, properties: [:]) else {
            throw WindowPreviewError.unavailable
        }
        return data
    }

    private func scWindow(for window: SwitchableWindow) async throws -> SCWindow {
        if let id = window.windowID {
            if let match = try await shareable(maxAge: 1.5).windows.first(where: { $0.windowID == id && $0.owningApplication?.processID == window.processID }) { return match }
            // The window may be newer than the cached list.
            if let match = try await shareable(maxAge: 0).windows.first(where: { $0.windowID == id && $0.owningApplication?.processID == window.processID }) { return match }
            throw WindowPreviewError.unavailable
        }
        // Legacy path for entries without a WindowServer id: require one unique title match.
        let untitled = window.title == WindowCatalog.untitledWindowTitle
        let matches = try await shareable(maxAge: 1.5).windows.filter { candidate in
            candidate.owningApplication?.processID == window.processID && candidate.windowLayer == 0
                && (untitled ? (candidate.title ?? "").isEmpty : candidate.title == window.title)
        }
        guard matches.count == 1, let target = matches.first else { throw WindowPreviewError.ambiguous }
        return target
    }

    /// The shareable-content query costs tens of milliseconds; reuse it across a burst of captures.
    private func shareable(maxAge: TimeInterval) async throws -> SCShareableContent {
        if let content, Date().timeIntervalSince(contentFetchedAt) <= maxAge { return content }
        if let contentRequest { return try await contentRequest.value.value }
        // Actor reentrancy otherwise starts one discovery for every concurrent thumbnail.
        let request = Task { ContentSnapshot(value: try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)) }
        contentRequest = request
        defer { contentRequest = nil }
        let fresh = try await request.value.value
        content = fresh
        contentFetchedAt = Date()
        return fresh
    }
}

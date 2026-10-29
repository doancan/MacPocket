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
}

/// Captures windows by WindowServer id, in memory only; images are never saved or transmitted.
public actor WindowPreviewProvider {
    private var content: SCShareableContent?
    private var contentFetchedAt = Date.distantPast
    public init() {}
    public static var permitted: Bool { CGPreflightScreenCaptureAccess() }
    @MainActor public static func requestPermission() { CGRequestScreenCaptureAccess() }

    /// Captures `window` scaled to fit `maxPixels` (never upscaled).
    public func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage {
        guard Self.permitted else { throw WindowPreviewError.permissionRequired }
        let target = try await scWindow(for: window)
        let configuration = SCStreamConfiguration()
        let scale = min(1, maxPixels.width / max(1, target.frame.width), maxPixels.height / max(1, target.frame.height))
        configuration.width = max(1, Int(target.frame.width * scale))
        configuration.height = max(1, Int(target.frame.height * scale))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        if #available(macOS 14.2, *) { configuration.ignoreShadowsSingleWindow = true }
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target),
                                                               configuration: configuration)
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
            if let match = try await shareable(maxAge: 1.5).windows.first(where: { $0.windowID == id }) { return match }
            // The window may be newer than the cached list.
            if let match = try await shareable(maxAge: 0).windows.first(where: { $0.windowID == id }) { return match }
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
        let fresh = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        content = fresh
        contentFetchedAt = Date()
        return fresh
    }
}

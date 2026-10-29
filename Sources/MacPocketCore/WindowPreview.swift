import AppKit
import ScreenCaptureKit

public enum WindowPreviewError: Error, LocalizedError {
    case permissionRequired, ambiguous, unavailable, expired
    public var errorDescription: String? {
        switch self {
        case .permissionRequired: "Önizleme için macOS Ekran Kaydı izni gerekiyor."
        case .ambiguous: "Aynı başlıklı pencereler güvenle ayırt edilemedi; yanlış pencereyi göstermemek için önizleme alınmadı."
        case .unavailable: "Pencere görüntüsü şu anda alınamıyor."
        case .expired: "Uygulama yeniden başlatıldı. Pencere listesini yenile."
        }
    }
}

public actor WindowPreviewProvider {
    public init() {}
    public static var permitted: Bool { CGPreflightScreenCaptureAccess() }
    @MainActor public static func requestPermission() { CGRequestScreenCaptureAccess() }

    /// Captures only a uniquely matched selected window, in memory; never saved or transmitted.
    public func preview(_ window: SwitchableWindow) async throws -> Data {
        guard Self.permitted else { throw WindowPreviewError.permissionRequired }
        let live = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: window.processID) else { return false }
            return app.launchDate == window.launchedAt
        }
        guard live else { throw WindowPreviewError.expired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let matches = content.windows.filter { $0.owningApplication?.processID == window.processID && $0.title == window.title && $0.windowLayer == 0 }
        guard matches.count == 1, let target = matches.first else { throw WindowPreviewError.ambiguous }
        let configuration = SCStreamConfiguration()
        let aspect = max(0.1, min(10, target.frame.width / max(1, target.frame.height)))
        configuration.width = 560
        configuration.height = max(60, min(560, Int(560 / aspect)))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw WindowPreviewError.unavailable }
        return data
    }
}

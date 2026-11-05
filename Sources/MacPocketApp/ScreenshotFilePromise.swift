import AppKit
import MacPocketCore
import UniformTypeIdentifiers

/// AppKit owns the provider through fulfillment; its userInfo retains the otherwise weak delegate.
/// Encoding starts only after a drop, on a serial background queue, rather than blocking mouseDragged.
final class ScreenshotFilePromise: NSObject, NSFilePromiseProviderDelegate, Sendable {
    private let capture: ScreenshotCapture
    private let settings: ScreenshotSettings
    private let name: String
    private let queue: OperationQueue

    @MainActor init(capture: ScreenshotCapture, settings: ScreenshotSettings) {
        self.capture = capture; self.settings = settings
        name = ScreenshotFiles.url(in: URL(fileURLWithPath: "/"), at: capture.date, prefix: String(localized: "Ekran Resmi"), format: settings.format) { _ in false }.lastPathComponent
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated
        self.queue = queue
        super.init()
    }
    @MainActor func provider() -> NSFilePromiseProvider {
        let provider = NSFilePromiseProvider(fileType: UTType(filenameExtension: settings.format.fileExtension)?.identifier ?? UTType.png.identifier, delegate: self)
        provider.userInfo = self; return provider
    }
    @MainActor func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }
    @MainActor func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do { try write(to: url); completionHandler(nil) } catch { completionHandler(error) }
    }
    nonisolated func write(to url: URL) throws {
        var coordinationError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                let data = try ScreenshotEncoder.encode(capture.image, as: settings.format, quality: settings.quality, scale: Double(capture.scale))
                try data.write(to: target, options: .withoutOverwriting)
            } catch { writeError = error }
        }
        if let error = writeError ?? coordinationError { throw error }
    }
}

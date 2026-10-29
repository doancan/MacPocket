import Foundation
import ImageIO
import Vision

public struct SimilarImageMatch: Identifiable, Sendable {
    public var id: String { file.id }
    public let file: ScannedFile
    public let distance: Float
}
public struct SimilarImageGroup: Identifiable, Sendable {
    public var id: String { reference.id }
    public let reference: ScannedFile
    public let matches: [SimilarImageMatch]
}
public struct SimilarImagesOptions: Sendable {
    public var distanceThreshold: Float = 0.6
    public var maximumImages = 250
    public var maximumDuration: TimeInterval = 60
    public init() {}
}
public struct SimilarImagesReport: Sendable {
    public let root: URL
    public let scannedAt: Date
    public let groups: [SimilarImageGroup]
    public let discoveredImages: Int
    public let analyzedImages: Int
    public let skippedImages: Int
    public let inaccessibleCount: Int
    public let partial: Bool
    public let issues: [String]
    public let threshold: Float
}
public struct SimilarImagesProgress: Sendable {
    public let message: String
}

public enum SimilarImagesError: Error, LocalizedError {
    case imageTooLarge, unreadableImage, missingFeature
    public var errorDescription: String? {
        switch self {
        case .imageTooLarge: String(localized: "Görsel 64 MiB veya 100 megapiksel sınırını aşıyor.")
        case .unreadableImage: String(localized: "Görsel veya ilk karesi okunamadı.")
        case .missingFeature: String(localized: "Vision bu görsel için karşılaştırma verisi üretemedi.")
        }
    }
}

private final class SimilarVisionWork: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false
    func start(_ request: VNRequest) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.request = request
    }
    func finish() { lock.lock(); request = nil; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; request?.cancel(); lock.unlock() }
}

public actor SimilarImagesService {
    public init() {}
    public static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "bmp", "gif"]
    public func scan(_ root: URL, options: SimilarImagesOptions = .init(),
                     progress: @Sendable (SimilarImagesProgress) async -> Void = { _ in }) async throws -> SimilarImagesReport {
        try Task.checkCancellation()
        let started = Date()
        let seconds = min(120, max(10, options.maximumDuration))
        let deadline = started.addingTimeInterval(seconds)
        let limit = min(500, max(2, options.maximumImages))
        let threshold = options.distanceThreshold.isFinite ? min(1.5, max(0.05, options.distanceThreshold)) : 0.6
        var scanOptions = FileScanOptions()
        scanOptions.allowedExtensions = Self.supportedExtensions
        scanOptions.maximumRetainedFiles = limit
        scanOptions.maximumDuration = min(20, seconds / 3)
        scanOptions.maximumEntries = 100_000
        scanOptions.includeHidden = false
        await progress(.init(message: String(localized: "Desteklenen görseller bulunuyor…")))
        let files = try await FileScanner().scan(root, options: scanOptions)
        let work = SimilarVisionWork()
        return try await withTaskCancellationHandler {
            try await analyze(files, started: started, deadline: deadline, threshold: threshold, work: work, progress: progress)
        } onCancel: { work.cancel() }
    }

    private func analyze(_ scan: FileScanReport, started: Date, deadline: Date, threshold: Float,
                         work: SimilarVisionWork, progress: @Sendable (SimilarImagesProgress) async -> Void) async throws -> SimilarImagesReport {
        var observations: [(ScannedFile, VNFeaturePrintObservation)] = []
        var issues = Array(scan.issues.prefix(12))
        var skipped = 0
        var partial = scan.limitReached || !scan.retainedAllFiles || scan.inaccessibleCount > 0
        for file in scan.files {
            try Task.checkCancellation()
            if Date() >= deadline { partial = true; break }
            await progress(.init(message: String(localized: "\(observations.count + skipped + 1) / \(scan.files.count) görsel analiz ediliyor…")))
            do {
                let feature = try autoreleasepool { try featurePrint(file, work: work) }
                observations.append((file, feature))
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                skipped += 1
                if issues.count < 12 { issues.append("\(file.url.lastPathComponent): \(error.localizedDescription)") }
            }
            await Task.yield()
        }
        var groups: [SimilarImageGroup] = []
        var matchCount = 0
        var comparisons = 0
        var stop = false
        for left in observations.indices {
            if stop { break }
            try Task.checkCancellation()
            var matches: [SimilarImageMatch] = []
            for right in observations.indices where right > left {
                try Task.checkCancellation()
                if Date() >= deadline || matchCount >= 1_000 { partial = true; stop = true; break }
                var distance: Float = 0
                do {
                    try observations[left].1.computeDistance(&distance, to: observations[right].1)
                    if distance.isFinite, distance >= 0, distance <= threshold {
                        matches.append(.init(file: observations[right].0, distance: distance)); matchCount += 1
                    }
                } catch {
                    partial = true
                    if issues.count < 12 { issues.append(String(localized: "Bir görsel çifti karşılaştırılamadı: \(error.localizedDescription)")) }
                }
                comparisons += 1
                if comparisons.isMultiple(of: 128) {
                    await progress(.init(message: String(localized: "\(comparisons) çift karşılaştırıldı · \(matchCount) aday")))
                    await Task.yield()
                }
            }
            if !matches.isEmpty { groups.append(.init(reference: observations[left].0, matches: matches.sorted { $0.distance < $1.distance })) }
        }
        try Task.checkCancellation()
        return .init(root: scan.root, scannedAt: started, groups: groups,
                     discoveredImages: scan.fileCount, analyzedImages: observations.count, skippedImages: skipped,
                     inaccessibleCount: scan.inaccessibleCount, partial: partial || skipped > 0, issues: issues, threshold: threshold)
    }

    private func featurePrint(_ file: ScannedFile, work: SimilarVisionWork) throws -> VNFeaturePrintObservation {
        let image = try Self.thumbnail(for: file, maximumPixelSize: 1_536)
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFit
        try work.start(request)
        defer { work.finish() }
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        guard try FileIdentity.read(file.url) == file.identity else { throw FileServiceError.changed }
        guard let feature = request.results?.first else { throw SimilarImagesError.missingFeature }
        return feature
    }
    /// Bounded, orientation-correct decoding shared with the result preview.
    public static func thumbnail(for file: ScannedFile, maximumPixelSize: Int = 310) throws -> CGImage {
        guard file.bytes <= 67_108_864 else { throw SimilarImagesError.imageTooLarge }
        guard try FileIdentity.read(file.url) == file.identity,
              try canonicalFileURL(file.url).path == file.url.path else { throw FileServiceError.changed }
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { throw SimilarImagesError.unreadableImage }
        guard width.doubleValue * height.doubleValue <= 100_000_000 else { throw SimilarImagesError.imageTooLarge }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(1_536, max(32, maximumPixelSize)),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw SimilarImagesError.unreadableImage }
        guard try FileIdentity.read(file.url) == file.identity else { throw FileServiceError.changed }
        return image
    }

}

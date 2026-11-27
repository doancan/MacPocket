import AppKit
import MacPocketCore
@preconcurrency import ScreenCaptureKit

/// MacPocket's screenshot tool: shortcuts, freezing the screens, capturing an area, window or screen with
/// ScreenCaptureKit, then saving, copying, the preview card and the history.
@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("ScreenshotService")
    #endif
    private(set) var moduleRunning = false

    @Published var settings: ScreenshotSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            registerShortcuts()
        }
    }
    @Published private(set) var history: ScreenshotHistory
    /// Modes whose shortcut macOS refused or that macOS's own screenshot shortcuts also use.
    @Published private(set) var failedShortcuts: Set<ScreenshotMode> = []
    /// A screenshot app that takes over ⇧⌘3/4/5 while running (e.g. CleanShot X).
    @Published private(set) var conflictingApp: String?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    @Published private(set) var latestCapture: ScreenshotCapture?
    var recordingShortcut = false { didSet { registerShortcuts() } }
    let pins = ScreenshotPins()

    private var hotKeys: [ScreenshotMode: PocketGlobalHotKey] = [:]
    private var observers: [NSObjectProtocol] = []
    private var overlay: ScreenshotSelectionOverlay?
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    private var scrollingSession: ScrollingScreenshotSession?
    private static let previousAreaKey = "MacPocket.screenshot.previousArea"
    private static let historyURL: URL = {
        #if DEBUG
        if let url = ModuleRuntimeAudit.dataURL("screenshot-history.json") { return url }
        #endif
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacPocket", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("screenshot-history.json")
    }()

    private init() {
        settings = ScreenshotSettings.load(from: .standard)
        history = (try? Data(contentsOf: Self.historyURL)).flatMap { try? JSONDecoder().decode(ScreenshotHistory.self, from: $0) } ?? ScreenshotHistory()
        history.prune(now: Date()) { FileManager.default.fileExists(atPath: $0) }
    }

    func stopForModule() {
        moduleRunning = false
        cancelCapture()
        pins.closeAll()
        latestCapture = nil
        ScreenshotQuickAccess.shared.closeAll()
        ScreenshotEditor.closeAll()
        hotKeys.values.forEach { $0.unregister() }
        hotKeys = [:]
        overlay?.finish(nil)
        overlay = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        failedShortcuts = []
        failedRegistrations = []
    }

    func start() {
        guard !moduleRunning, PocketModule.screenshot.isAvailable() else { return }
        moduleRunning = true
        registerShortcuts()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkConflicts() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkConflicts() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelCapture() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelCapture() }
            })
        }
    }

    /// macOS's own screenshot shortcuts and screenshot apps aren't refused by `RegisterEventHotKey`; look
    /// them up.
    func checkConflicts() {
        let symbolic = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        let system = ScreenshotShortcutConflicts.system(settings.shortcuts, symbolicHotKeys: symbolic)
        failedShortcuts = failedRegistrations.union(system)
        conflictingApp = ScreenshotShortcutConflicts.runningApp(bundleIDs: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private var failedRegistrations: Set<ScreenshotMode> = []

    private func registerShortcuts() {
        guard moduleRunning else { return }
        var failed: Set<ScreenshotMode> = []
        for mode in ScreenshotMode.allCases {
            let hotKey = hotKeys[mode] ?? PocketGlobalHotKey { [weak self] in self?.capture(mode) }
            hotKeys[mode] = hotKey
            if let combo = settings.shortcuts[mode], !recordingShortcut {
                if !hotKey.register(combo) { failed.insert(mode) }
            } else {
                hotKey.unregister()
            }
        }
        failedRegistrations = failed
        checkConflicts()
    }

    var folder: URL {
        settings.folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func dismissMessage() { message = nil }

    // MARK: Capturing

    func capture(_ mode: ScreenshotMode) {
        guard moduleRunning, !busy, overlay == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            message = String(localized: "Ekran görüntüsü almak için MacPocket’e Ekran Kaydı izni ver; sonra tekrar dene.")
            return
        }
        beginCapture { [weak self] in await self?.run(mode) }
    }

    @discardableResult private func beginCapture(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard moduleRunning, !busy, overlay == nil else { return false }
        busy = true
        let id = UUID()
        captureID = id
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.captureID == id { self.busy = false; self.captureTask = nil; self.captureID = nil; self.scrollingSession = nil } }
            await operation()
        }
        return true
    }

    private func run(_ mode: ScreenshotMode) async {
        do {
            switch mode {
            case .fullscreen:
                guard let display = Self.displayUnderPointer() else { return }
                let image = try await Self.captureDisplay(display)
                try await finish(image, mode: .fullscreen, scale: Self.scale(for: display, image: image))
            case .previousArea:
                try await capturePreviousArea()
            case .area, .window, .allInOne, .scrolling:
                let screens = try await freezeScreens()
                let selection = try await select(on: screens, mode: mode)
                try await handle(selection, screens: screens, mode: mode)
            }
        } catch is CancellationError {
        } catch {
            guard moduleRunning, !Task.isCancelled else { return }
            message = String(localized: "Ekran görüntüsü alınamadı: \(error.localizedDescription)")
            PocketToast.show(message ?? error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    func cancelCapture() {
        captureTask?.cancel()
        overlay?.finish(nil)
        scrollingSession?.cancel()
    }

    var canSuspendModule: Bool { !busy && !ScreenshotEditor.hasUnsavedChanges && !pins.items.contains { $0.working } }

    private func handle(_ selection: ScreenshotSelection?, screens: [FrozenScreen], mode: ScreenshotMode) async throws {
        switch selection {
        case nil:
            return
        case let .area(display, rect):
            guard let screen = screens.first(where: { $0.display == display }),
                  let pixels = ScreenshotGeometry.pixelRect(rect, scale: screen.scale, imageSize: CGSize(width: screen.image.width, height: screen.image.height)),
                  let crop = screen.image.cropping(to: pixels) else { return }
            savePreviousArea(display: display, rect: rect)
            try await finish(crop, mode: .area, scale: screen.scale)
        case let .fullscreen(display):
            if let screen = screens.first(where: { $0.display == display }) { try await finish(screen.image, mode: .fullscreen, scale: screen.scale) }
        case let .window(id):
            let result = try await Self.captureWindow(id)
            try await finish(result.image, mode: .window, scale: result.scale)
        case let .scrolling(display, rect):
            try Task.checkCancellation()
            guard let screen = screens.first(where: { $0.display == display }) else { throw CaptureError.noDisplay }
            let rect = rect.intersection(CGRect(origin: .zero, size: screen.frame.size))
            guard rect.width * screen.scale >= 32, rect.height * screen.scale >= 64 else { throw ScrollScreenshotStitcher.Failure.invalidFrame }
            savePreviousArea(display: display, rect: rect)
            let area = CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            let session = ScrollingScreenshotSession()
            scrollingSession = session
            defer { session.cancel() }
            session.prepare(near: area)
            let source = try await ScrollingScreenshotSession.source(displayID: display, rect: rect, scale: screen.scale)
            try await performScrolling(session, frame: area, source: source, scale: screen.scale)
        case .previousArea:
            try await capturePreviousArea(frozen: screens)
        }
    }

    private func performScrolling(_ session: ScrollingScreenshotSession, frame: CGRect, source: @escaping ScrollingScreenshotSession.FrameSource, scale: CGFloat) async throws {
        guard let result = try await session.run(frame: frame, source: source) else { return }
        try await finish(result.image, mode: .scrolling, scale: scale)
        if result.partial { message = String(localized: "Son hareket eşleşmedi; yalnız doğrulanmış bölümler kaydedildi.") }
        else if result.limited { message = String(localized: "Yakalama sınırına ulaşıldı; şimdiye kadarki bölümler kaydedildi.") }
    }

    private func select(on screens: [FrozenScreen], mode: ScreenshotMode) async throws -> ScreenshotSelection? {
        try Task.checkCancellation()
        let overlay = ScreenshotSelectionOverlay(screens: screens, windows: Self.windowsOnScreen(), startInWindowMode: mode == .window,
                                                 showsModeBar: mode == .allInOne, hasPreviousArea: loadPreviousArea() != nil)
        if mode == .scrolling { overlay.setScrollingMode(true) }
        self.overlay = overlay
        defer { self.overlay = nil }
        return await withCheckedContinuation { continuation in
            overlay.begin { continuation.resume(returning: $0) }
        }
    }

    private func capturePreviousArea(frozen: [FrozenScreen]? = nil) async throws {
        guard let previous = loadPreviousArea() else {
            message = String(localized: "Henüz önceki bir alan yok; önce bir alan seç.")
            return
        }
        let image: CGImage
        if let screen = frozen?.first(where: { $0.display == previous.display }) {
            image = screen.image
        } else {
            image = try await Self.captureDisplay(previous.display)
        }
        let scale = frozen?.first { $0.display == previous.display }?.scale ?? Self.scale(for: previous.display, image: image)
        guard let pixels = ScreenshotGeometry.pixelRect(previous.rect, scale: scale, imageSize: CGSize(width: image.width, height: image.height)),
              let crop = image.cropping(to: pixels) else { return }
        try await finish(crop, mode: .previousArea, scale: scale)
    }

    // MARK: After capture

    private func finish(_ image: CGImage, mode: ScreenshotMode, scale: CGFloat) async throws {
        try Task.checkCancellation()
        guard moduleRunning else { return }
        let settings = settings
        var capture = ScreenshotCapture(image: image, scale: scale, fileURL: nil, date: Date(), mode: mode)
        let png = settings.copyToClipboard ? try await ScreenshotAsyncOutput.encode(image, format: .png, quality: 1, scale: Double(scale)) : nil
        try Task.checkCancellation()
        if settings.saveToFolder {
            do { capture.fileURL = try await saveAsync(capture, encodedData: settings.format == .png ? png : nil) }
            catch is CancellationError { throw CancellationError() }
            catch { message = String(localized: "Ekran görüntüsü kaydedilemedi: \(error.localizedDescription)") }
        }
        try Task.checkCancellation()
        guard moduleRunning else { return }
        if let png { NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png, forType: .png) }
        latestCapture = capture
        if settings.playSound { NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif", byReference: true)?.play() }
        if settings.showOverlay { ScreenshotQuickAccess.shared.show(capture) }
    }

    func saveAsync(_ capture: ScreenshotCapture, encodedData: Data? = nil) async throws -> URL {
        if let url = capture.fileURL, FileManager.default.fileExists(atPath: url.path) { return url }
        let settings = settings, folder = folder, prefix = String(localized: "Ekran Resmi")
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try encodedData ?? ScreenshotEncoder.encode(capture.image, as: settings.format, quality: settings.quality, scale: Double(capture.scale))
            return try ScreenshotFileWriter.write(data, folder: folder, date: capture.date, prefix: prefix, format: settings.format)
        }
        let url = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        if !Task.isCancelled { noteSaved(url, image: capture.image, mode: capture.mode) }
        return url
    }

    @discardableResult func pin(_ capture: ScreenshotCapture) -> Bool {
        guard moduleRunning, !busy else { return false }
        return pins.pin(capture)
    }

    func removeFromHistory(_ id: UUID) {
        history.remove(id)
        saveHistory()
    }

    /// Re-saves the history after an edit overwrote or added a file.
    func noteSaved(_ url: URL, image: CGImage, mode: ScreenshotMode) {
        history.add(ScreenshotHistoryEntry(path: url.path, date: Date(), mode: mode, pixelWidth: image.width, pixelHeight: image.height))
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: Self.historyURL, options: .atomic) }
    }

    // MARK: Previous area

    private struct PreviousArea: Codable { var display: CGDirectDisplayID; var rect: CGRect }

    private func savePreviousArea(display: CGDirectDisplayID, rect: CGRect) {
        if let data = try? JSONEncoder().encode(PreviousArea(display: display, rect: rect)) { UserDefaults.standard.set(data, forKey: Self.previousAreaKey) }
    }

    private func loadPreviousArea() -> PreviousArea? {
        guard let area = UserDefaults.standard.data(forKey: Self.previousAreaKey).flatMap({ try? JSONDecoder().decode(PreviousArea.self, from: $0) }),
              NSScreen.screens.contains(where: { $0.displayID == area.display }) else { return nil }
        return area
    }

    // MARK: ScreenCaptureKit

    private func freezeScreens() async throws -> [FrozenScreen] {
        var frozen: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let display = screen.displayID else { continue }
            try Task.checkCancellation()
            let image = try await Self.captureDisplay(display)
            frozen.append(FrozenScreen(display: display, frame: screen.frame, scale: Self.scale(for: display, image: image), image: image))
        }
        return frozen
    }

    /// The display at native resolution, without the pointer and without MacPocket's screenshot chrome.
    static func captureDisplay(_ id: CGDirectDisplayID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        let chrome = Set(NSApp.windows.filter { $0 is ScreenshotChrome && $0.isVisible }.map { CGWindowID($0.windowNumber) })
        let excluded = content.windows.filter { chrome.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// One window on its own, with its shadow and a transparent background.
    static func captureWindow(_ id: CGWindowID) async throws -> (image: CGImage, scale: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = false
        configuration.shouldBeOpaque = false
        return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration), scale)
    }

    private static func scale(for display: CGDirectDisplayID, image: CGImage) -> CGFloat {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == display }), screen.frame.width > 0 else { return 1 }
        return CGFloat(image.width) / screen.frame.width
    }

    enum CaptureError: LocalizedError {
        case noDisplay, noWindow
        var errorDescription: String? {
            switch self {
            case .noDisplay: String(localized: "Ekran bulunamadı.")
            case .noWindow: String(localized: "Pencere artık açık değil.")
            }
        }
    }

    /// Normal windows on screen, front to back, in AppKit global coordinates; MacPocket's chrome is left out.
    private static func windowsOnScreen() -> [FrozenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let chrome = Set(NSApp.windows.filter { $0 is ScreenshotChrome }.map { CGWindowID($0.windowNumber) })
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID, !chrome.contains(number),
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width > 40, bounds.height > 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return FrozenWindow(id: number, frame: NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height))
        }
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.displayID
    }
}

/// One capture handed to the preview card and the editor.
struct ScreenshotCapture: Identifiable, Sendable {
    let id = UUID()
    var image: CGImage
    var scale: CGFloat
    var fileURL: URL?
    let date: Date
    let mode: ScreenshotMode
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

#if DEBUG
extension ScreenshotService {
    @discardableResult func diagnosticCapture(_ session: ScrollingScreenshotSession, source: @escaping ScrollingScreenshotSession.FrameSource) -> Bool {
        guard ModuleRuntimeAudit.requested else { return false }
        return beginCapture { [weak self] in
            guard let self else { return }
            self.scrollingSession = session
            defer { session.cancel() }
            do {
                try await self.performScrolling(session, frame: CGRect(x: 120, y: 160, width: 400, height: 300), source: source, scale: 2)
            } catch is CancellationError {} catch { self.message = error.localizedDescription }
        }
    }
    var moduleDiagnosticResources: [String: Int] {
        var resources = pins.diagnosticResources
        resources.merge(["observers": observers.count, "hotKeys": hotKeys.count, "overlay": overlay == nil ? 0 : 1,
                         "captureTask": captureTask == nil ? 0 : 1, "scrollHUD": scrollingSession?.diagnosticResources ?? 0,
                         "editors": ScreenshotEditor.diagnosticWindows], uniquingKeysWith: { _, new in new })
        return resources
    }
}
#endif

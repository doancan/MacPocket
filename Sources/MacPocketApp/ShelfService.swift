import AppKit
import ImageIO
import MacPocketCore
import UniformTypeIdentifiers

struct ShelfRow: Equatable, Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let symbol: String
    let url: URL?
    let unavailable: Bool
    let pinned: Bool
}

@MainActor
final class ShelfService: ObservableObject {
    static let shared = ShelfService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("ShelfService")
    #endif
    @Published private(set) var shelf = ShelfCollection()
    @Published private(set) var rows: [ShelfRow] = []
    @Published var selection: Set<UUID> = []
    @Published private(set) var message: String?
    @Published private(set) var loading = false
    @Published private(set) var preparing = 0
    @Published private(set) var shortcutRegistered = false
    @Published var shortcut: KeyCombo? = {
        guard let data = UserDefaults.standard.data(forKey: shortcutKey) else { return KeyCombo(keyCode: 1, modifiers: [.control, .option]) }
        return (try? JSONDecoder().decode(KeyCombo?.self, from: data)) ?? nil
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: Self.shortcutKey); registerShortcut() }
    }
    @Published var shakeToOpen = UserDefaults.standard.bool(forKey: "MacPocket.shelf.shakeToOpen") {
        didSet { UserDefaults.standard.set(shakeToOpen, forKey: "MacPocket.shelf.shakeToOpen"); syncMouseMonitor() }
    }
    var recordingShortcut = false { didSet { registerShortcut() } }
    private(set) var moduleRunning = false
    private var loaded = false
    private var loadTask: Task<Void, Never>?
    private var transferTimeouts: [UUID: Task<Void, Never>] = [:]
    private var transfers: [UUID: (ShelfPromiseTransfer, Int)] = [:]
    private var imageTasks: [UUID: Task<Void, Never>] = [:]
    private var scopedURLs: [UUID: URL] = [:]
    private var mouseMonitor: Any?
    private var dragBaseline = 0
    private var dragSamples: [(TimeInterval, CGFloat)] = []
    private lazy var hotKey = PocketGlobalHotKey { [weak self] in self?.toggle() }
    private lazy var panel = ShelfPanelController(service: self)
    private static let shortcutKey = "MacPocket.shelf.shortcut"
    private let directory: URL = {
        #if DEBUG
        if let url = ModuleRuntimeAudit.dataURL("shelf") { return url }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPocket/Shelf", isDirectory: true)
    }()
    private var filesDirectory: URL { directory.appendingPathComponent("Files", isDirectory: true) }
    private var archiveURL: URL { directory.appendingPathComponent("shelf.json") }
    var acceptsItems: Bool { moduleRunning && loaded }
    var canRetryLoad: Bool { !loaded && !loading }

    private init() {}

    func start() {
        guard !moduleRunning, PocketModule.shelf.isAvailable() else { return }
        moduleRunning = true
        registerShortcut()
        syncMouseMonitor()
        if loaded { refreshRows(); return }
        loading = true
        let url = archiveURL
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<ShelfCollection, Error> in
                do {
                    guard FileManager.default.fileExists(atPath: url.path) else { return .success(ShelfCollection()) }
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 32 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
                    return .success(try ShelfArchive.decode(Data(contentsOf: url)))
                } catch { return .failure(error) }
            }.value
            guard let self, !Task.isCancelled, moduleRunning else { return }
            switch result {
            case .success(let contents): shelf = contents
            loaded = true
            case .failure:
                message = String(localized: "Raf geçmişi okunamadı. Tekrar yüklemeyi dene; kayıtlı dosya korunuyor.")
            }
            loading = false
            loadTask = nil
            refreshRows()
        }
    }

    func retryLoad() {
        guard !loading, !loaded else { return }
        stopForModule()
        start()
    }

    func stopForModule() {
        moduleRunning = false
        loadTask?.cancel()
        loadTask = nil
        loading = false
        hotKey.unregister()
        shortcutRegistered = false
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        dragSamples = []
        cancelPreparation()
        panel.close()
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
        scopedURLs = [:]
    }

    private func registerShortcut() {
        guard moduleRunning, !recordingShortcut, let shortcut else { hotKey.unregister(); shortcutRegistered = false; return }
        shortcutRegistered = hotKey.register(shortcut)
    }

    func toggle() { panel.isVisible ? close() : show() }
    func show(focus: Bool = true) {
        guard moduleRunning else { return }
        refreshRows()
        panel.show(focus: focus)
    }
    func close() { panel.close() }

    func refreshRows() {
        rows = shelf.items.map { item in
            let url: URL?
            let symbol: String
            let detail: String
            let title: String
            let unavailable: Bool
            switch item.content {
            case .file(let file):
                url = file.resolvedURL()
                unavailable = url == nil
                title = url?.lastPathComponent ?? file.originalURL.lastPathComponent
                detail = url?.deletingLastPathComponent().path ?? String(localized: "Dosya taşınmış, değiştirilmiş veya erişilemiyor")
                symbol = unavailable ? "exclamationmark.triangle" : ((try? FileIdentity.read(url!))?.isDirectory == true ? "folder" : "doc")
                if let url, scopedURLs[item.id] == nil, url.startAccessingSecurityScopedResource() { scopedURLs[item.id] = url }
            case .text(let text):
                url = nil
                unavailable = false
                title = item.content.title
                detail = String(localized: "\(text.count) karakter")
                symbol = "text.alignleft"
            case .link(let link):
                url = link
                unavailable = false
                title = link.absoluteString
                detail = String(localized: "Web bağlantısı")
                symbol = "link"
            }
            return ShelfRow(id: item.id, title: title, detail: detail, symbol: symbol, url: url, unavailable: unavailable, pinned: item.pinned)
        }
        selection.formIntersection(Set(rows.map(\.id)))
    }

    private func save() {
        guard loaded else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(ShelfArchive(items: shelf.items))
            try data.write(to: archiveURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        } catch { message = String(localized: "Raf bu oturumda kullanılabilir; geçmiş diske kaydedilemedi: \(error.localizedDescription)") }
    }

    @discardableResult
    func add(_ contents: [ShelfContent]) -> ShelfCollection.Insertion {
        guard moduleRunning, loaded else { return ShelfCollection.Insertion() }
        let result = shelf.insert(contents, reserving: preparing)
        if !result.added.isEmpty { selection = Set(result.added.map(\.id)) }
        message = result.rejected > 0
            ? String(localized: "Bazı öğeler eklenemedi. Raf en fazla 100 öğe, metinler en fazla 256 KB olabilir.")
            : (result.duplicates > 0 ? String(localized: "Zaten rafta olan öğeler yeniden eklenmedi.") : nil)
        refreshRows()
        save()
        return result
    }

    func addFiles(_ urls: [URL]) {
        var contents: [ShelfContent] = []
        var failed = false
        var accessing: [URL] = []
        for url in urls.prefix(ShelfCollection.capacity + 1) {
            if url.startAccessingSecurityScopedResource() { accessing.append(url) }
            if let file = try? ShelfFileReference(url: url) { contents.append(.file(file)) } else { failed = true }
        }
        _ = add(contents)
        for url in accessing { url.stopAccessingSecurityScopedResource() }
        if failed { message = String(localized: "Bazı dosyalara erişilemiyor. Finder’dan yeniden eklemeyi dene.") }
    }

    func chooseFiles() {
        guard moduleRunning, loaded else { return }
        let picker = NSOpenPanel()
        picker.title = String(localized: "Rafa Dosya Ekle")
        picker.prompt = String(localized: "Rafa Ekle")
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.begin { [weak self] response in
            MainActor.assumeIsolated { if response == .OK, self?.moduleRunning == true { self?.addFiles(picker.urls) } }
        }
    }

    static var readableTypes: [NSPasteboard.PasteboardType] {
        let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff]
        return types + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        moduleRunning && loaded && shelf.remainingCapacity > preparing && pasteboard.availableType(from: Self.readableTypes) != nil
    }

    @discardableResult
    func accept(_ pasteboard: NSPasteboard, promises: Bool = false) -> Bool {
        guard moduleRunning, loaded else { return false }
        if promises, let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            return receivePromises(receivers)
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addFiles(urls)
            return true
        }
        let items = pasteboard.pasteboardItems ?? []
        var contents: [ShelfContent] = []
        for item in items.prefix(ShelfCollection.capacity + 1) {
            if let text = item.string(forType: .string) ?? item.string(forType: .URL) {
                contents.append(.fromText(text))
            }
        }
        if !contents.isEmpty { return !add(contents).added.isEmpty }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return addImage(data) }
        }
        message = String(localized: "Panoda desteklenen dosya, metin, bağlantı veya görsel yok.")
        return false
    }

    private func addImage(_ data: Data) -> Bool {
        guard data.count <= 20 * 1_024 * 1_024, shelf.remainingCapacity > preparing else {
            message = String(localized: "Görsel çok büyük veya okunamıyor. Görseli dosya olarak eklemeyi dene.")
            return false
        }
        let id = UUID()
        let folder = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let filename = String(localized: "Pano Görseli") + ".png"
        preparing += 1
        imageTasks[id] = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { try Self.storeImage(data, folder: folder, filename: filename) }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: { worker.cancel() }
            guard let self, self.imageTasks.removeValue(forKey: id) != nil, self.moduleRunning, !Task.isCancelled else {
                if case .success(let url) = result { Self.discardManaged([url], root: folder.deletingLastPathComponent()) }
                return
            }
            self.preparing = max(0, self.preparing - 1)
            switch result {
            case .success(let url): self.addDeliveredFiles([url])
            case .failure(let error):
                self.message = error is ShelfImageFailure
                    ? String(localized: "Görsel çok büyük veya okunamıyor. Görseli dosya olarak eklemeyi dene.")
                    : String(localized: "Görsel rafa kaydedilemedi: \(error.localizedDescription)")
            }
        }
        return true
    }

    private enum ShelfImageFailure: Error { case unreadable }
    private nonisolated static func storeImage(_ data: Data, folder: URL, filename: String) throws -> URL {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 25_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ShelfImageFailure.unreadable
        }
        try Task.checkCancellation()
        let url = folder.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            try Task.checkCancellation()
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func receivePromises(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        let available = shelf.remainingCapacity - preparing
        guard available > 0 else { message = String(localized: "Raf dolu. Yeni öğeler için raftan öğe kaldır."); return false }
        let id = UUID()
        do {
            let incoming = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-Shelf-" + id.uuidString, isDirectory: true)
            let storage = filesDirectory
            let transfer = try ShelfPromiseTransfer(incoming: incoming, storage: storage, maximum: available) { [weak self] delivery in
                Task { @MainActor in
                    guard let self, let pending = self.transfers.removeValue(forKey: id) else {
                        Self.discardManaged(delivery.urls, root: storage)
                        return
                    }
                    self.transferTimeouts.removeValue(forKey: id)?.cancel()
                    self.preparing = max(0, self.preparing - pending.1)
                    guard self.moduleRunning else { Self.discardManaged(delivery.urls, root: pending.0.storage); return }
                    self.addDeliveredFiles(delivery.urls)
                    if delivery.failed { self.message = String(localized: "Bazı dosyalar hazırlanamadı. Kaynak uygulamadan yeniden bırakmayı dene.") }
                }
            }
            // Reserve all free slots until AppKit reveals the actual promised count.
            preparing += available
            transfers[id] = (transfer, available)
            let count = transfer.receive(receivers)
            transfers[id] = (transfer, count)
            preparing -= available - count
            transferTimeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(90)) } catch { return }
                self?.cancelPreparation(id)
                self?.message = String(localized: "Dosya hazırlama zaman aşımına uğradı. Kaynak uygulamadan yeniden bırakmayı dene.")
            }
            return true
        } catch { message = String(localized: "Dosya aktarımı başlatılamadı: \(error.localizedDescription)")
        return false }
    }

    private func addDeliveredFiles(_ urls: [URL]) {
        let result = add(urls.compactMap { (try? ShelfFileReference(url: $0)).map(ShelfContent.file) })
        let retained = Set(result.added.compactMap { item -> URL? in if case .file(let file) = item.content { return file.originalURL }; return nil })
        Self.discardManaged(urls.filter { !retained.contains($0) }, root: filesDirectory)
    }

    func cancelPreparation() {
        for task in imageTasks.values { task.cancel() }
        preparing = max(0, preparing - imageTasks.count)
        imageTasks = [:]
        for id in Array(transfers.keys) { cancelPreparation(id) }
    }
    private func cancelPreparation(_ id: UUID) {
        guard let pending = transfers.removeValue(forKey: id) else { return }
        transferTimeouts.removeValue(forKey: id)?.cancel()
        preparing = max(0, preparing - pending.1)
        pending.0.cancel()
    }

    func removeSelection() { remove(shelf.remove(selection)) }
    func clearUnpinned() { remove(shelf.clearUnpinned()) }
    private func remove(_ removed: [ShelfItem]) {
        message = nil
        for item in removed { scopedURLs.removeValue(forKey: item.id)?.stopAccessingSecurityScopedResource() }
        let urls = removed.compactMap { item -> URL? in if case .file(let file) = item.content { return file.originalURL }; return nil }
        Self.discardManaged(urls, root: filesDirectory)
        refreshRows()
        save()
    }

    private nonisolated static func discardManaged(_ urls: [URL], root: URL) {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        for url in urls {
            let folder = url.deletingLastPathComponent().standardizedFileURL
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  folder.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == root else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    func togglePins() { message = nil; shelf.togglePins(selection); refreshRows(); save() }
    var selectedRows: [ShelfRow] { rows.filter { selection.contains($0.id) } }
    var canUseSelection: Bool { !selection.isEmpty && selectedRows.allSatisfy { !$0.unavailable } }

    func writer(for id: UUID) -> (any NSPasteboardWriting)? {
        guard let item = shelf.items.first(where: { $0.id == id }) else { return nil }
        switch item.content {
        case .file(let file): return file.resolvedURL().map { $0 as NSURL }
        case .link(let url): return url as NSURL
        case .text(let text): return text as NSString
        }
    }

    func copySelection(to pasteboard: NSPasteboard = .general) {
        refreshRows()
        guard canUseSelection else { return }
        let selected = shelf.items.filter { selection.contains($0.id) }
        let allURLs = selected.allSatisfy { if case .text = $0.content { return false }; return true }
        let objects: [any NSPasteboardWriting] = allURLs ? selected.compactMap { writer(for: $0.id) }
            : [selected.map { $0.content.plainText }.joined(separator: "\n") as NSString]
        guard objects.count == (allURLs ? selected.count : 1) else { return }
        pasteboard.clearContents()
        message = pasteboard.writeObjects(objects) ? String(localized: "Seçilen öğeler kopyalandı.") : String(localized: "Seçilen öğeler panoya yazılamadı.")
    }

    func revealSelection() {
        refreshRows()
        let urls = selectedRows.compactMap(\.url).filter(\.isFileURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    func previewSelection() {
        refreshRows()
        guard canUseSelection else { return }
        panel.preview(selectedRows.compactMap(\.url).filter(\.isFileURL))
    }
    var shareItems: [Any] {
        shelf.items.filter { selection.contains($0.id) }.compactMap { item -> Any? in
            switch item.content {
            case .file(let file): file.resolvedURL()
            case .link(let url): url
            case .text(let text): text
            }
        }
    }

    private func syncMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        dragSamples = []
        guard moduleRunning, shakeToOpen else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.observeDrag(event) }
        }
    }

    private func observeDrag(_ event: NSEvent) {
        let pasteboard = NSPasteboard(name: .drag)
        if event.type == .leftMouseDown { dragBaseline = pasteboard.changeCount; dragSamples = []; return }
        if event.type == .leftMouseUp { dragSamples = []; return }
        guard !panel.isVisible, pasteboard.changeCount != dragBaseline,
              pasteboard.availableType(from: Self.readableTypes) != nil else { return }
        let time = ProcessInfo.processInfo.systemUptime
        guard dragSamples.last.map({ time - $0.0 >= 0.03 }) ?? true else { return }
        dragSamples.append((time, NSEvent.mouseLocation.x))
        dragSamples.removeAll { time - $0.0 > 0.7 }
        var direction: CGFloat = 0
        var changes = 0
        var last = dragSamples.first?.1 ?? 0
        for sample in dragSamples.dropFirst() {
            let delta = sample.1 - last
            guard abs(delta) >= 24 else { continue }
            let next: CGFloat = delta > 0 ? 1 : -1
            if direction != 0, direction != next { changes += 1 }
            direction = next
            last = sample.1
        }
        if changes >= 3 { dragSamples = []; show(focus: false) }
    }

    #if DEBUG
    var diagnosticWindow: NSWindow? { panel.diagnosticWindow }
    var diagnosticPreviewOwned: Bool { panel.diagnosticPreviewOwned }
    var diagnosticPreviewWindow: NSWindow? { panel.diagnosticPreviewWindow }
    var diagnosticPreviewURL: URL? { panel.diagnosticPreviewURL }
    func diagnosticForgetMemory() {
        guard ModuleRuntimeAudit.requested, !moduleRunning else { return }
        loaded = false
        shelf = ShelfCollection()
        rows = []
        selection = []
    }
    var moduleDiagnosticResources: [String: Int] {
        ["shortcut": shortcutRegistered ? 1 : 0, "mouseMonitor": mouseMonitor == nil ? 0 : 1,
         "loadTask": loadTask == nil ? 0 : 1, "transfers": transfers.count, "timeouts": transferTimeouts.count,
         "images": imageTasks.count, "preview": panel.diagnosticPreviewOwned ? 1 : 0,
         "scopes": scopedURLs.count, "visiblePanel": panel.isVisible ? 1 : 0]
    }
    #endif
}

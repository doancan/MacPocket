import AppKit
import Combine
import MacPocketCore
import SwiftUI

/// Shared window list for the keyboard switcher and the Tools detail table.
@MainActor
final class WindowSwitcherModel: ObservableObject {
    @Published private(set) var windows: [SwitchableWindow] = []
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var partial = false
    @Published private(set) var otherSpacesVisible = false
    @Published private(set) var busy = false
    @Published var failure: String?
    @Published var selection: String?
    /// Table search in Tools.
    @Published var search = ""
    /// Type-to-search inside the switcher panel.
    @Published var sessionSearch = ""
    /// Live thumbnails keyed by window id; only populated while the switcher is open.
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    /// Large image of the selected window for the in-place preview.
    @Published private(set) var selectedPreview: (id: String, image: NSImage)?
    @Published var preview: NSImage?
    @Published var previewBusy = false
    @Published var previewMessage: String?
    @Published private(set) var lastRefresh: Date?

    var foregroundPID: Int32?
    /// Non-nil while a switcher session runs; it replaces the table filters.
    var sessionFilter: WindowListFilter?
    var sessionDisplayID: UInt32?
    private let catalog = WindowCatalog()
    private let previews = WindowPreviewProvider()
    private var activationObserver: AnyCancellable?
    private var thumbnailGeneration = UUID()

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in await self?.catalog.noteApplicationActivation(pid) }
            }
    }

    var excludedPaths: Set<String> {
        Set((UserDefaults.standard.string(forKey: "switcher.excludedPaths") ?? "").split(separator: "\n").map(String.init))
    }

    var order: WindowSortOrder { WindowSortOrder(rawValue: UserDefaults.standard.string(forKey: "switcher.sort") ?? "recent") ?? .recent }

    var filtered: [SwitchableWindow] {
        if let filter = sessionFilter {
            return WindowFiltering.apply(windows, search: sessionSearch, includeMinimized: filter.includeMinimized,
                                         includeHidden: filter.includeHidden, includeWindowless: filter.includeWindowless,
                                         currentApplication: filter.currentApplicationOnly ? foregroundPID : nil,
                                         excludedBundlePaths: excludedPaths, order: order,
                                         currentSpaceOnly: filter.currentSpaceOnly,
                                         displayID: filter.currentScreenOnly ? sessionDisplayID : nil)
        }
        return WindowFiltering.apply(windows, search: search, excludedBundlePaths: excludedPaths, order: order)
    }

    var selected: SwitchableWindow? { filtered.first { $0.id == selection } }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if foregroundPID == nil { foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let old = selection
        let report = await catalog.snapshot()
        windows = report.windows
        trusted = report.accessibilityGranted
        partial = report.partial
        otherSpacesVisible = report.otherSpacesVisible
        lastRefresh = Date()
        if foregroundPID == ProcessInfo.processInfo.processIdentifier || foregroundPID == nil {
            foregroundPID = windows.first?.processID
        }
        if sessionFilter == nil { selection = filtered.contains { $0.id == old } ? old : filtered.first?.id }
    }

    func focus(id: String? = nil) async {
        guard let target = id ?? selected?.id else { return }
        do { try await catalog.focus(target); failure = nil }
        catch { failure = error.localizedDescription }
    }

    func action(_ action: WindowAction, id: String? = nil) async {
        guard let target = id ?? selected?.id else { return }
        do {
            try await catalog.perform(action, on: target)
            failure = nil
            // Give the app a moment to apply the change before re-reading its windows.
            try? await Task.sleep(for: .milliseconds(action == .quitApplication ? 400 : 150))
            await refresh()
        } catch { failure = error.localizedDescription }
    }

    func cycle(backwards: Bool, by step: Int = 1) {
        let rows = filtered
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? (backwards ? 0 : -1)
        let next = ((current + (backwards ? -step : step)) % rows.count + rows.count) % rows.count
        selection = rows[next].id
    }

    // MARK: Thumbnails

    /// Captures thumbnails for the visible windows, selected first. With `live`, keeps refreshing them
    /// roughly every second until cancelled, which is what makes the cards show current window contents.
    func runThumbnails(maxPixels: CGSize, live: Bool) async {
        guard WindowPreviewProvider.permitted else { return }
        let generation = thumbnailGeneration
        repeat {
            var targets = filtered.filter { $0.windowID != nil && !$0.minimized }.prefix(48).map { $0 }
            if let index = targets.firstIndex(where: { $0.id == selection }) { targets.insert(targets.remove(at: index), at: 0) }
            await withTaskGroup(of: (String, WindowImage?).self) { group in
                var iterator = targets.makeIterator()
                // Four concurrent captures keep the first pass fast without flooding ScreenCaptureKit.
                for _ in 0..<4 {
                    guard let window = iterator.next() else { break }
                    group.addTask { [previews] in (window.id, try? await previews.image(for: window, maxPixels: maxPixels)) }
                }
                for await (id, image) in group {
                    if let image, generation == thumbnailGeneration, !Task.isCancelled {
                        thumbnails[id] = NSImage(cgImage: image.cgImage, size: .zero)
                    }
                    if let window = iterator.next(), !Task.isCancelled {
                        group.addTask { [previews] in (window.id, try? await previews.image(for: window, maxPixels: maxPixels)) }
                    }
                }
            }
            if !live || Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(1100))
        } while !Task.isCancelled && generation == thumbnailGeneration
    }

    /// Full-size image for the in-place preview of the selected window.
    func loadSelectedPreview(maxPixels: CGSize) async {
        guard WindowPreviewProvider.permitted, let window = selected, window.windowID != nil, !window.minimized else {
            selectedPreview = nil
            return
        }
        let generation = thumbnailGeneration
        if let thumbnail = thumbnails[window.id] { selectedPreview = (window.id, thumbnail) }
        guard let image = try? await previews.image(for: window, maxPixels: maxPixels),
              !Task.isCancelled, generation == thumbnailGeneration, selection == window.id else { return }
        selectedPreview = (window.id, NSImage(cgImage: image.cgImage, size: .zero))
    }

    func clearThumbnails() {
        thumbnailGeneration = UUID()
        thumbnails = [:]
        selectedPreview = nil
    }

    func capturePreview() async {
        guard !previewBusy, let selected, selected.windowID != nil else { return }
        previewBusy = true; preview = nil; previewMessage = nil
        let id = selected.id
        defer { previewBusy = false }
        do {
            let image = try await previews.image(for: selected, maxPixels: CGSize(width: 840, height: 520))
            guard selection == id else { return }
            preview = NSImage(cgImage: image.cgImage, size: .zero)
        } catch { if selection == id { previewMessage = error.localizedDescription } }
    }

    func excludeSelected() {
        guard let path = selected?.applicationURL?.path else { return }
        var paths = excludedPaths
        paths.insert(path)
        UserDefaults.standard.set(paths.sorted().joined(separator: "\n"), forKey: "switcher.excludedPaths")
        selection = nil
        objectWillChange.send()
    }
}

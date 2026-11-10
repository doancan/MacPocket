import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct SwitchableWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let processID: Int32
    public let application: String
    public let title: String
    public let applicationURL: URL?
    public var bundleIdentifier: String?
    public let minimized: Bool
    public let hidden: Bool
    public let fullScreen: Bool
    public let frontmost: Bool
    /// An AX handle exists, so window actions (close, minimize, raise) are possible.
    public let windowAccessible: Bool
    public let canClose: Bool
    public let canMinimize: Bool
    public let canFullScreen: Bool
    public let launchedAt: Date?
    public let lastFocusedAt: Date?
    /// WindowServer identifier; stable for the window's lifetime and used for thumbnails.
    public var windowID: UInt32? = nil
    /// Global frame in CoreGraphics coordinates (top-left origin).
    public var frame: CGRect? = nil
    /// Display containing the window's center.
    public var displayID: UInt32? = nil
    /// Inferred other-Space entry: a titled, off-screen WindowServer window not paired with AX.
    /// This is a visibility heuristic, not an exact Space identifier or membership guarantee.
    public var otherSpace = false
    /// Front-to-back WindowServer order among on-screen windows; nil when off screen.
    public var zOrder: Int? = nil
    public var canResize = false
    /// WindowServer Space IDs resolved against one consistent managed-display topology.
    public var spaceMembership: WindowSpaceMembership?
    public var creationObservation: WindowCreationObservation?
    public var nativeTab: WindowTabInfo?
    public var isOnAnotherSpace: Bool { spaceMembership?.isVisible.map { !$0 } ?? otherSpace }

    public init(id: String, processID: Int32, application: String, title: String, applicationURL: URL?,
                minimized: Bool, hidden: Bool, fullScreen: Bool, frontmost: Bool, windowAccessible: Bool,
                canClose: Bool, canMinimize: Bool, canFullScreen: Bool, launchedAt: Date?, lastFocusedAt: Date?,
                windowID: UInt32? = nil, frame: CGRect? = nil, displayID: UInt32? = nil,
                otherSpace: Bool = false, zOrder: Int? = nil, canResize: Bool = false,
                spaceMembership: WindowSpaceMembership? = nil, nativeTab: WindowTabInfo? = nil,
                creationObservation: WindowCreationObservation? = nil, bundleIdentifier: String? = nil) {
        self.id = id; self.processID = processID; self.application = application; self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL; self.minimized = minimized; self.hidden = hidden
        self.fullScreen = fullScreen; self.frontmost = frontmost; self.windowAccessible = windowAccessible
        self.canClose = canClose; self.canMinimize = canMinimize; self.canFullScreen = canFullScreen
        self.launchedAt = launchedAt; self.lastFocusedAt = lastFocusedAt; self.windowID = windowID
        self.frame = frame; self.displayID = displayID; self.otherSpace = otherSpace; self.zOrder = zOrder; self.canResize = canResize
        self.spaceMembership = spaceMembership
        self.nativeTab = nativeTab
        self.creationObservation = creationObservation
    }

    /// A physical window or verified native window tab, with or without direct AX window actions.
    public var isRealWindow: Bool { windowID != nil || windowAccessible || nativeTab != nil }
    public var canCapturePreview: Bool { nativeTab == nil || windowID != nil }
}

public enum WindowSortOrder: String, CaseIterable, Codable, Sendable {
    case recent, application, title, space, creation
    public var localizedTitle: String {
        switch self {
        case .recent: String(localized: "Son kullanılan")
        case .application: String(localized: "Uygulama")
        case .title: String(localized: "Başlık")
        case .space: String(localized: "Masaüstü sırası")
        case .creation: String(localized: "Oluşturulma sırası")
        }
    }
}

public enum WindowFiltering {
    public static func apply(_ windows: [SwitchableWindow], search: String = "", includeMinimized: Bool = true,
                             includeHidden: Bool = true, includeWindowless: Bool = true, currentApplication: Int32? = nil,
                             excludedBundlePaths: Set<String> = [], order: WindowSortOrder = .recent,
                             currentSpaceOnly: Bool = false, displayID: UInt32? = nil, exceptions: [SwitcherExceptionRule] = []) -> [SwitchableWindow] {
        var filter = WindowListFilter()
        filter.includeMinimized = includeMinimized; filter.includeHidden = includeHidden
        filter.includeWindowless = includeWindowless; filter.currentApplicationOnly = currentApplication != nil
        // The legacy/table API lists individual records. Grouping is an explicit session filter.
        filter.separateTabs = true
        filter.currentSpaceOnly = currentSpaceOnly; filter.currentScreenOnly = displayID != nil
        return apply(windows, filter: filter, context: .init(foregroundPID: currentApplication, displayID: displayID),
                     search: search, excludedBundlePaths: excludedBundlePaths, order: order, exceptions: exceptions)
    }

    /// Stable ties preserve the server's application/window order.
    static func sorted(_ windows: [SwitchableWindow], order: WindowSortOrder) -> [SwitchableWindow] {
        windows.enumerated().sorted { a, b in
            switch order {
            case .creation, .space, .recent:
                if order == .creation {
                    let left = a.element.creationObservation, right = b.element.creationObservation
                    if let left, let right {
                        if left.sessionID != right.sessionID { return left.sessionID.uuidString < right.sessionID.uuidString }
                        if left.sequence != right.sequence { return left.sequence < right.sequence }
                    }
                    if (left != nil) != (right != nil) { return left != nil }
                }
                if order == .space {
                    let left = a.element.spaceMembership?.firstOrdinal ?? .max
                    let right = b.element.spaceMembership?.firstOrdinal ?? .max
                    if left != right { return left < right }
                }
                let lhs = a.element.lastFocusedAt ?? .distantPast, rhs = b.element.lastFocusedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                if a.element.frontmost != b.element.frontmost { return a.element.frontmost }
                let lz = a.element.zOrder ?? .max, rz = b.element.zOrder ?? .max
                if lz != rz { return lz < rz }
            case .application:
                let comparison = a.element.application.localizedStandardCompare(b.element.application)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .title:
                let comparison = a.element.title.localizedStandardCompare(b.element.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Every whitespace-separated term must appear, diacritic- and case-insensitively ("goo chr" → Google Chrome).
    static func matches(_ query: String, _ text: String) -> Bool {
        query.split(separator: " ").allSatisfy {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

public struct WindowCatalogReport: Sendable {
    public let windows: [SwitchableWindow]
    public let accessibilityGranted: Bool
    public let partial: Bool
    /// Windows on other Spaces need WindowServer titles, which require Screen Recording access.
    public var otherSpacesVisible = false
    public var spaceMetadataAvailable = false
    public var spaceMetadataPartial = false
    public var lifecycle: WindowLifecycleSnapshot = .unavailable
    public init(windows: [SwitchableWindow], accessibilityGranted: Bool, partial: Bool, otherSpacesVisible: Bool = false,
                spaceMetadataAvailable: Bool = false, spaceMetadataPartial: Bool = false, lifecycle: WindowLifecycleSnapshot = .unavailable) {
        self.windows = windows; self.accessibilityGranted = accessibilityGranted
        self.partial = partial; self.otherSpacesVisible = otherSpacesVisible
        self.spaceMetadataAvailable = spaceMetadataAvailable; self.spaceMetadataPartial = spaceMetadataPartial
        self.lifecycle = lifecycle
    }
}

public protocol WindowCatalogServing: Sendable {
    func snapshot() async -> WindowCatalogReport
    func focus(_ id: String) async throws
    func focusDestination(_ id: String) async -> WindowFocusDestination?
    func perform(_ action: WindowAction, on id: String) async throws
    func noteApplicationActivation(_ pid: Int32) async
}

public extension WindowCatalogServing {
    func focusDestination(_ id: String) async -> WindowFocusDestination? { nil }
}

public enum WindowAction: Sendable { case close, minimize, restore, toggleFullScreen, hideApplication, quitApplication }

public enum WindowCatalogError: Error, LocalizedError {
    case expired, focusFailed, unsupported, permissionRequired
    public var errorDescription: String? {
        switch self {
        case .expired: String(localized: "Pencere ya da uygulama değişti. Listeyi yenile.")
        case .focusFailed: String(localized: "macOS işlemi tamamlayamadı. İzin veya Space durumunu kontrol et.")
        case .unsupported: String(localized: "Bu pencere bu işlemi desteklemiyor.")
        case .permissionRequired: String(localized: "Bu işlem için macOS Erişilebilirlik izni gerekiyor.")
        }
    }
}

/// One WindowServer entry from `CGWindowListCopyWindowInfo`.
struct ServerWindow: Sendable {
    let id: UInt32
    let pid: Int32
    let frame: CGRect
    let title: String?
    let onScreen: Bool
}

/// AX handles remain actor-isolated. Identity is revalidated before every mutation.
public actor WindowCatalog: WindowCatalogServing {
    public static var untitledWindowTitle: String { String(localized: "Başlıksız pencere") }
    private struct ApplicationInfo: Sendable {
        let pid: Int32
        let name: String
        let url: URL?
        let bundleIdentifier: String?
        let launchedAt: Date?
        let frontmost: Bool
        let hidden: Bool
    }
    private struct Handle {
        let application: ApplicationInfo
        let window: AXUIElement?
        let windowID: UInt32?
        var tab: WindowTabAction? = nil
        var lifecycle: WindowLifecycleSnapshot = .unavailable
        var validationWindowID: UInt32? = nil
    }
    private var handles: [String: Handle] = [:]
    private var focusHistory: [String: Date] = [:]
    private var applicationHistory: [String: Date] = [:]
    private var snapshotGeneration = UUID()
    private let spaceProvider: any WindowSpaceProviding
    private let tabAccessibility = WindowTabAccessibility()
    private let lifecycleProvider: any WindowLifecycleProviding
    private var tabCreationHistory: [String: WindowCreationObservation] = [:]
#if DEBUG
    private var lastSpecificActivation: (id: String, outcome: String)?
#endif
    public init(spaceProvider: any WindowSpaceProviding = WindowSpaceProvider.shared,
                lifecycleProvider: any WindowLifecycleProviding = WindowLifecycleProvider()) {
        self.spaceProvider = spaceProvider; self.lifecycleProvider = lifecycleProvider
    }

    public func noteApplicationActivation(_ pid: Int32) async {
        guard pid != getpid() else { return }
        let launch = await MainActor.run { () -> Date? in
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
            return CatalogWindowIdentity.processLaunchDate(pid: pid, applicationDate: app.launchDate)
        }
        guard let launch else { return }
        applicationHistory[CatalogWindowIdentity.application(pid: pid, launchedAt: launch)] = Date()
    }

    public func snapshot() async -> WindowCatalogReport {
        await snapshot(processIDs: nil, includingCurrentApplication: false, matchingApplicationURL: nil)
    }

    public func snapshot(processIDs: Set<Int32>? = nil, includingCurrentApplication: Bool = false, matchingApplicationURL: URL? = nil) async -> WindowCatalogReport {
        let generation = UUID()
        snapshotGeneration = generation
        var scanFocusHistory = focusHistory
        let lifecycleStart = await lifecycleProvider.snapshot(admitting: [])
        let (candidates, screens, observedFocus) = await MainActor.run { () -> ([ApplicationInfo], [(UInt32, CGRect)], [String: Date]) in
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let apps = NSWorkspace.shared.runningApplications.filter {
                ($0.activationPolicy == .regular || (includingCurrentApplication && $0.processIdentifier == getpid()))
                    && (includingCurrentApplication || $0.processIdentifier != getpid())
            }.map {
                ApplicationInfo(pid: $0.processIdentifier, name: $0.localizedName ?? String(localized: "Uygulama"), url: $0.bundleURL, bundleIdentifier: $0.bundleIdentifier,
                                launchedAt: CatalogWindowIdentity.processLaunchDate(pid: $0.processIdentifier, applicationDate: $0.launchDate),
                                frontmost: $0.processIdentifier == front, hidden: $0.isHidden)
            }.sorted { $0.frontmost && !$1.frontmost }
            return (apps, Self.displayFrames(), WindowFocusObservationCenter.shared.timestamps())
        }
        let apps: [ApplicationInfo]
        if let matchingApplicationURL {
            let canonical = matchingApplicationURL.standardizedFileURL.resolvingSymlinksInPath()
            apps = candidates.filter { (processIDs?.contains($0.pid) ?? true) && $0.url?.standardizedFileURL.resolvingSymlinksInPath() == canonical }
        } else { apps = candidates.filter { processIDs?.contains($0.pid) ?? true } }
        let trusted = AXIsProcessTrusted()
        let server = Self.serverWindows()
        let zOrder = Self.onScreenOrder()
        let titlesReadable = server.values.joined().contains { $0.title?.isEmpty == false }
        let deadline = Date().addingTimeInterval(8)
        var partial = false
        var values: [SwitchableWindow] = []
        var nextHandles: [String: Handle] = [:]
        var tabScans: [WindowTabScan] = []
        var tabScanProcesses: [String: WindowTabProcess] = [:]
        var invalidTabGroups = Set<String>()
        var offscreenFallbacksWithCompleteAX = Set<String>()
        func addWindowless(_ app: ApplicationInfo) {
            let id = "app-" + CatalogWindowIdentity.application(pid: app.pid, launchedAt: app.launchedAt)
            nextHandles[id] = Handle(application: app, window: nil, windowID: nil)
            values.append(.init(id: id, processID: app.pid, application: app.name,
                title: trusted ? String(localized: "Açık pencere yok") : String(localized: "Pencere erişimi bekleniyor"),
                applicationURL: app.url, minimized: false, hidden: app.hidden, fullScreen: false,
                frontmost: app.frontmost, windowAccessible: false, canClose: false, canMinimize: false,
                canFullScreen: false, launchedAt: app.launchedAt, lastFocusedAt: applicationHistory[CatalogWindowIdentity.application(pid: app.pid, launchedAt: app.launchedAt)]))
        }
        func display(for frame: CGRect?) -> UInt32? {
            WindowFiltering.displayID(for: frame, among: screens)
        }

        for app in apps {
            if Task.isCancelled || Date() >= deadline || values.count >= 300 { partial = true; break }
            let appKey = CatalogWindowIdentity.application(pid: app.pid, launchedAt: app.launchedAt)
            var serverWindows = server[app.pid] ?? []
            var produced = 0
            var completeAXList = false

            if trusted {
                let element = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(element, 0.2)
                let listedValue = Self.attribute(element, kAXWindowsAttribute) as? [AXUIElement]
                let listed = listedValue ?? []
                completeAXList = listedValue != nil
                if !completeAXList { partial = true }
                let discovery: TabWindowDiscovery<AXUIElement>?
                if let launch = app.launchedAt {
                    discovery = tabAccessibility.discoverWindows(listed: listed, process: .init(pid: app.pid, launchedAt: launch),
                        physicalWindowIDs: Set(serverWindows.map(\.id)), deadline: deadline)
                } else { discovery = nil }
                let elements = discovery?.windows ?? listed
                partial = partial || discovery?.partial == true
                if discovery?.partial == true { completeAXList = false }
                invalidTabGroups.formUnion(discovery?.invalidGroups ?? [])
                let focused = Self.elementAttribute(element, kAXFocusedWindowAttribute)
                let focusedOwner = focused.flatMap { WindowFocusOwner.window(for: $0,processID: app.pid,io: AXWindowTabIO()) }
                for window in elements.prefix(80) {
                    if Task.isCancelled || Date() >= deadline { partial = true; completeAXList = false; break }
                    AXUIElementSetMessagingTimeout(window, 0.2)
                    // Only standard windows are switch targets (drawers, sheets and palettes are not).
                    guard let role = Self.attribute(window, kAXRoleAttribute) as? String else { partial = true; completeAXList = false; continue }
                    guard role == kAXWindowRole as String else { continue }
                    let subrole = Self.attribute(window, kAXSubroleAttribute) as? String
                    if let subrole, subrole != kAXStandardWindowSubrole as String, subrole != "AXDialog" { continue }
                    let axFrame = Self.frame(of: window)
                    let windowID = Self.windowID(of: window) ?? axFrame.flatMap { frame in
                        Self.uniqueWindowID(matching: frame, candidates: serverWindows)
                    }
                    let matched = windowID.flatMap { id in serverWindows.firstIndex { $0.id == id } }
                    let serverEntry = matched.map { serverWindows.remove(at: $0) }
                    let id = CatalogWindowIdentity.window(pid: app.pid, launchedAt: app.launchedAt, windowID: windowID, elementHash: CFHash(window))
                    if nextHandles[id] != nil { continue }
                    let alias = CatalogWindowIdentity.window(pid: app.pid, launchedAt: app.launchedAt, windowID: nil, elementHash: CFHash(window))
                    let observed = observedFocus[id] ?? observedFocus[alias]
                    let front = app.frontmost && focusedOwner.map { CFEqual($0, window) } == true
                    // Snapshot fallback is only for targets whose focus event was not observed.
                    if front, observed == nil { scanFocusHistory[id] = Date() }
                    let close = Self.elementAttribute(window, kAXCloseButtonAttribute)
                    let closable = close.map { (Self.attribute($0, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true } ?? false
                    let frame = serverEntry?.frame ?? axFrame
                    let title = (Self.attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? serverEntry?.title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.untitledWindowTitle
                    nextHandles[id] = Handle(application: app, window: window, windowID: windowID)
                    values.append(.init(id: id, processID: app.pid, application: app.name, title: title,
                                        applicationURL: app.url, minimized: Self.boolean(window, kAXMinimizedAttribute), hidden: app.hidden,
                                        fullScreen: Self.boolean(window, "AXFullScreen"), frontmost: front, windowAccessible: true,
                                        canClose: closable, canMinimize: Self.settable(window, kAXMinimizedAttribute),
                                        canFullScreen: Self.settable(window, "AXFullScreen"), launchedAt: app.launchedAt,
                                        lastFocusedAt: [scanFocusHistory[id], observed].compactMap { $0 }.max(),
                                        windowID: windowID, frame: frame, displayID: display(for: frame),
                                        otherSpace: false, zOrder: windowID.flatMap { zOrder[$0] },
                                        canResize: Self.settable(window, kAXPositionAttribute) && Self.settable(window, kAXSizeAttribute)))
                    if let scan = tabAccessibility.scan(window: window, anchorID: id,
                        cached: windowID.flatMap { discovery?.cachedByWindowID[$0] } ?? [], deadline: deadline) {
                        tabScans.append(scan)
                        if let launch = app.launchedAt { tabScanProcesses[id] = .init(pid: app.pid, launchedAt: launch) }
                    }
                    produced += 1
                }
                if elements.count > 80 { partial = true; completeAXList = false }
            }

            // WindowServer-only windows: on other Spaces (AX lists the current Space only), or every window when
            // AX is not granted. Without titles (no Screen Recording) off-screen entries cannot be told apart
            // from invisible helper windows, so they are not guessed.
            if !app.hidden {
                for entry in serverWindows {
                    let titled = entry.title?.isEmpty == false
                    let otherSpace = !entry.onScreen
                    guard titled || (!trusted && entry.onScreen), !(otherSpace && !titled),
                          screens.contains(where: { $0.1.intersects(entry.frame) }) else { continue }
                    let id = "w-\(appKey)-\(entry.id)"
                    if completeAXList && !entry.onScreen { offscreenFallbacksWithCompleteAX.insert(id) }
                    nextHandles[id] = Handle(application: app, window: nil, windowID: entry.id)
                    values.append(.init(id: id, processID: app.pid, application: app.name,
                                        title: entry.title.flatMap { $0.isEmpty ? nil : $0 } ?? app.name,
                                        applicationURL: app.url, minimized: false, hidden: false, fullScreen: false,
                                        frontmost: false, windowAccessible: false, canClose: false, canMinimize: false,
                                        canFullScreen: false, launchedAt: app.launchedAt,
                                        lastFocusedAt: [scanFocusHistory[id], observedFocus[id]].compactMap { $0 }.max(),
                                        windowID: entry.id, frame: entry.frame, displayID: display(for: entry.frame),
                                        otherSpace: otherSpace && trusted, zOrder: zOrder[entry.id]))
                    produced += 1
                }
            }

            if produced == 0 {
                addWindowless(app)
            }
            await Task.yield()
        }
        // Native inactive tabs may have no AX-window entry/title, but their physical WindowServer
        // surfaces must corroborate a tab bar before it can replace normal catalog rows.
        let appPIDs = Set(apps.map(\.pid))
        let tabSurfaces = server.filter { appPIDs.contains($0.key) }.values.flatMap { $0 }
        let extraTabIDs = tabScans.isEmpty ? [] : tabSurfaces.map(\.id)
        let spaces = await spaceProvider.snapshot(windowIDs: values.compactMap(\.windowID) + extraTabIDs)
        for index in values.indices {
            if let id = values[index].windowID { values[index].spaceMembership = spaces.membership(for: id) }
        }
        // An AX-missing, ordered-out surface assigned to a CURRENT Space is not an off-Space
        // window. Closed NSWindows can retain precisely that WindowServer backing. Preserve
        // actual AX rows (including hidden/minimized), other Spaces, and unknown/partial reads.
        let removedFallbacks = Set(values.filter { offscreenFallbacksWithCompleteAX.contains($0.id) && $0.spaceMembership?.isVisible == true }.map(\.processID))
        values.removeAll { offscreenFallbacksWithCompleteAX.contains($0.id) && $0.spaceMembership?.isVisible == true }
        let represented = Set(values.map(\.processID))
        for app in apps where removedFallbacks.contains(app.pid) && !represented.contains(app.pid) { addWindowless(app) }
        let launchDates = Dictionary(uniqueKeysWithValues: apps.compactMap { app in app.launchedAt.map { (app.pid, $0) } })
        let physicalIdentities = tabSurfaces.compactMap { surface in
            launchDates[surface.pid].map { WindowLifecycleIdentity(windowID: surface.id, processID: surface.pid, launchedAt: $0) }
        }
        let lifecycle = await lifecycleProvider.snapshot(admitting: physicalIdentities)
        func survives(_ id: UInt32) -> Bool { !lifecycle.available || !lifecycle.invalidates(id, since: lifecycleStart) }
        if lifecycleStart.available && !lifecycle.available { partial = true }
        let priorCount = values.count
        values.removeAll { $0.windowID.map { !survives($0) } == true }
        if values.count != priorCount { partial = true }
        for index in values.indices {
            guard let id = values[index].windowID, let launchedAt = values[index].launchedAt else { continue }
            values[index].creationObservation = lifecycle.creation(for: .init(windowID: id, processID: values[index].processID, launchedAt: launchedAt))
        }
        let currentTabHistory = lifecycle.available ? tabCreationHistory.filter { $0.value.sessionID == lifecycle.sessionID } : [:]
        let bundles = Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0.bundleIdentifier) })
        for index in values.indices { values[index].bundleIdentifier = bundles[values[index].processID] ?? nil }
        let projection = WindowTabProjectionResolver.project(values, surfaces: tabSurfaces.filter { survives($0.id) }.map {
            .init(id: $0.id, processID: $0.pid, frame: $0.frame, spaceIDs: spaces.memberships[$0.id])
        }, bars: tabScans.map(\.bar), focusHistory: scanFocusHistory, creationHistory: currentTabHistory)
        let tabActions = tabScans.reduce(into: [String: WindowTabAction]()) { result, scan in
            result.merge(scan.actions, uniquingKeysWith: { first, _ in first })
        }
        for (id, binding) in projection.bindings {
            guard let source = nextHandles[binding.anchorID], var action = tabActions[binding.controlID] else { continue }
            action.expectedWindowID = binding.expectedWindowID
            nextHandles[id] = Handle(application: source.application,
                                     window: binding.expectedWindowID == nil ? nil : source.window,
                                     windowID: binding.expectedWindowID, tab: action, lifecycle: lifecycle, validationWindowID: source.windowID)
        }
        let projectedIDs = Set(projection.windows.map(\.id))
        nextHandles = nextHandles.filter { projectedIDs.contains($0.key) }
        for id in Array(nextHandles.keys) {
            guard var handle = nextHandles[id] else { continue }
            handle.lifecycle = lifecycle
            if handle.validationWindowID == nil { handle.validationWindowID = handle.windowID }
            nextHandles[id] = handle
        }
        values = projection.windows
        scanFocusHistory.merge(projection.observedFocus, uniquingKeysWith: max)
        // Snapshot calls can overlap at the MainActor/Space-provider awaits. Only the latest
        // uncancelled scan owns the action handles; an old report cannot revoke a new target.
        if generation == snapshotGeneration, !Task.isCancelled {
            handles = nextHandles
            if trusted {
                tabAccessibility.commit(scans: tabScans, processes: tabScanProcesses, projection: projection,
                    liveProcesses: Set(candidates.compactMap { app in app.launchedAt.map { WindowTabProcess(pid: app.pid, launchedAt: $0) } }),
                    invalidGroups: invalidTabGroups)
            } else { tabAccessibility.reset() }
            tabCreationHistory = Dictionary(uniqueKeysWithValues: projection.windows.compactMap { window in
                guard window.nativeTab != nil, let observation = window.creationObservation else { return nil }
                return (window.id, observation)
            })
            focusHistory.merge(scanFocusHistory, uniquingKeysWith: max)
            focusHistory = focusHistory.filter { nextHandles[$0.key] != nil }
            let liveApps = Set(apps.map { CatalogWindowIdentity.application(pid: $0.pid, launchedAt: $0.launchedAt) })
            applicationHistory = applicationHistory.filter { liveApps.contains($0.key) }
        }
        return .init(windows: values, accessibilityGranted: trusted, partial: partial || Task.isCancelled, otherSpacesVisible: titlesReadable,
                     spaceMetadataAvailable: spaces.available, spaceMetadataPartial: spaces.partial, lifecycle: lifecycle)
    }

#if DEBUG
    public func hasActionHandleForAudit(_ id: String) -> Bool { handles[id] != nil }
    public func actionDiagnosticsForAudit(_ id: String) async -> [String: String] {
        guard let handle = handles[id] else { return ["handle": "missing"] }
        var result = ["handle": "present", "expectedPID": String(handle.application.pid)]
        if lastSpecificActivation?.id == id { result["specificActivation"] = lastSpecificActivation?.outcome }
        if let id = handle.validationWindowID ?? handle.windowID {
            let current = await lifecycleProvider.snapshot(admitting: [])
            result["lifecycleInvalidates"] = String(current.invalidates(id, since: handle.lifecycle))
        }
        let application = handle.application
        let live = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: application.pid), !app.isTerminated else { return false }
            return CatalogWindowIdentity.matchesProcessLaunch(expected: application.launchedAt,
                actual: CatalogWindowIdentity.processLaunchDate(pid: application.pid, applicationDate: app.launchDate))
        }
        result["processIdentityValid"] = String(live)
        if let window = handle.window {
            var pid: pid_t = 0
            result["AXGetPID"] = String(AXUIElementGetPid(window, &pid).rawValue)
            result["actualPID"] = String(pid)
            result["actualWindowID"] = Self.windowID(of: window).map(String.init) ?? "nil"
        }
        return result
    }
#endif

    public func focusDestination(_ id: String) async -> WindowFocusDestination? {
        guard AXIsProcessTrusted(),!Task.isCancelled,let handle = try? await validatedHandle(id),let launch = handle.application.launchedAt else { return nil }
        let info = handle.application
        let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == info.pid }
        guard front,!Task.isCancelled else { return nil }
        let application = AXUIElementCreateApplication(info.pid)
        AXUIElementSetMessagingTimeout(application,0.03)
        guard let focused = Self.elementAttribute(application,kAXFocusedWindowAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused,0.03)
        guard let owner = WindowFocusOwner.window(for: focused,processID: info.pid,io: AXWindowTabIO()),
              let ownerID = Self.windowID(of: owner) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused,&pid) == .success,pid == info.pid,let physicalID = Self.windowID(of: focused),physicalID > 0 else { return nil }
        if let tab = handle.tab {
            guard let selected = tabAccessibility.selectedWindow(for: tab,processID: info.pid),Self.windowID(of: selected) == ownerID else { return nil }
        } else if let expected = handle.windowID {
            guard ownerID == expected else { return nil }
        } else if let window = handle.window {
            guard CFEqual(owner,window) else { return nil }
        } // A windowless app can supply its actual newly opened focused window, never a title guess.
        guard !Task.isCancelled,
              let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,0) as? [[String: Any]],
              let row = rows.first(where: { $0[kCGWindowNumber as String] as? UInt32 == physicalID && $0[kCGWindowOwnerPID as String] as? Int32 == info.pid }),
              let bounds = row[kCGWindowBounds as String] as? NSDictionary,let frame = CGRect(dictionaryRepresentation: bounds),
              frame.width > 0,frame.height > 0 else { return nil }
        guard let _ = try? await validatedHandle(id),!Task.isCancelled else { return nil }
        return .init(processID: info.pid,launchedAt: launch,windowID: physicalID,frame: frame)
    }

    public func focus(_ id: String) async throws {
        try Task.checkCancellation()
        let handle = try await validatedHandle(id)
        let info = handle.application
        guard (handle.window == nil && handle.windowID == nil && handle.tab == nil) || AXIsProcessTrusted() else { throw WindowCatalogError.permissionRequired }
        let tabAnchor = try handle.tab.map { try tabAccessibility.anchorWindow(for: $0, processID: info.pid) }
        let destinationID = tabAnchor.flatMap(Self.windowID) ?? handle.windowID
        var resolvedWindow = handle.window
        if tabAnchor == nil, resolvedWindow == nil, let destinationID, AXIsProcessTrusted() {
            resolvedWindow = Self.resolveAXWindow(windowID: destinationID, processID: info.pid)
                ?? WindowRemoteAXLookup.resolve(windowID: destinationID, processID: info.pid)
        }
        let destinationSpaces: WindowSpaceSnapshot
        if let destinationID, AXIsProcessTrusted() { destinationSpaces = await spaceProvider.snapshot(windowIDs: [destinationID]) }
        else { destinationSpaces = .init() }
        let windowless = handle.window == nil && handle.windowID == nil && handle.tab == nil
        let activated = await MainActor.run { () -> Bool? in
            guard !Task.isCancelled, let app = NSRunningApplication(processIdentifier: info.pid), !app.isTerminated,
                  CatalogWindowIdentity.matchesProcessLaunch(expected: info.launchedAt,
                    actual: CatalogWindowIdentity.processLaunchDate(pid: info.pid, applicationDate: app.launchDate)) else { return nil }
            app.unhide()
            // A windowless app gets the Dock-click behaviour (reopen), which usually opens a new window.
            if windowless, let url = app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
            return app.activate(options: [])
        }
        guard let activated else { throw WindowCatalogError.expired }
        guard activated || AXIsProcessTrusted() else { throw WindowCatalogError.focusFailed }
        try Task.checkCancellation()
        // The switcher panel never activates MacPocket, so cooperative activation alone can be ignored;
        // asking the target app to be frontmost through Accessibility always works for a trusted process.
        if AXIsProcessTrusted() {
            let application = AXUIElementCreateApplication(info.pid)
            AXUIElementSetMessagingTimeout(application, 0.2)
            if Self.boolean(application, kAXHiddenAttribute) {
                guard AXUIElementSetAttributeValue(application, kAXHiddenAttribute as CFString, kCFBooleanFalse) == .success else {
                    throw WindowCatalogError.focusFailed
                }
            }
            let result = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            guard activated || result == .success else { throw WindowCatalogError.focusFailed }
        }
        if let destinationID, AXIsProcessTrusted() {
            try Task.checkCancellation()
            let activation = WindowSpecificActivation.request(windowID: destinationID, processID: info.pid)
#if DEBUG
            lastSpecificActivation = (id, String(describing: activation))
#endif
            if destinationSpaces.membership(for: destinationID)?.isVisible == false {
                guard activation == .accepted else { throw WindowCatalogError.focusFailed }
                if let anchor = tabAnchor ?? resolvedWindow { try await raise(anchor, application: info) }
                let expected = destinationSpaces.memberships[destinationID]
                var visible = false
                for _ in 0..<32 {
                    try Task.checkCancellation()
                    if tabAnchor == nil, resolvedWindow == nil,
                       let window = Self.resolveAXWindow(windowID: destinationID, processID: info.pid) {
                        resolvedWindow = window
                        try await raise(window, application: info)
                    }
                    let current = await spaceProvider.snapshot(windowIDs: [destinationID])
                    if current.memberships[destinationID] == expected, current.membership(for: destinationID)?.isVisible == true { visible = true; break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                guard visible else { throw WindowCatalogError.focusFailed }
                _ = try await validatedHandle(id)
            }
        }
        if let tab = handle.tab {
            try tabAccessibility.press(tab, processID: info.pid)
            var selected: AXUIElement?
            for _ in 0..<12 {
                try Task.checkCancellation()
                if let window = tabAccessibility.selectedWindow(for: tab, processID: info.pid) { selected = window; break }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard let selected else { throw WindowCatalogError.focusFailed }
            try await raise(selected, application: info)
        } else if let window = resolvedWindow {
            try await raise(window, application: info)
        } else if let windowID = handle.windowID, AXIsProcessTrusted() {
            // Activating the app moves to its Space; the window then becomes visible to AX and can be raised.
            var raised = false
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(70))
                let element = AXUIElementCreateApplication(info.pid)
                AXUIElementSetMessagingTimeout(element, 0.2)
                let windows = (Self.attribute(element, kAXWindowsAttribute) as? [AXUIElement]) ?? []
                if let window = windows.first(where: { Self.windowID(of: $0) == windowID }) {
                    try await raise(window, application: info)
                    raised = true
                    break
                }
            }
            guard raised else { throw WindowCatalogError.focusFailed }
        }
        try Task.checkCancellation()
        if !windowless { try await confirmFocus(id,handle: handle,resolvedWindow: resolvedWindow,destinationID: destinationID) }
        focusHistory[id] = Date()
    }

    /// Accepted activation/AXRaise requests can precede the actual foreground transition.
    /// In particular, asynchronous unhide can restore the former app AFTER the first request.
    /// Do not publish success/MRU until the exact target is corroborated; repeat activation once
    /// for that hidden-app race, with fresh identity checks and no click inside window contents.
    private func confirmFocus(_ id: String,handle: Handle,resolvedWindow: AXUIElement?,destinationID: UInt32?) async throws {
        let info = handle.application
        for attempt in 0..<24 {
            try Task.checkCancellation()
            _ = try await validatedHandle(id)
            if await focusDestination(id) != nil { return }
            // Some legitimate AX-only windows have no WindowServer ID/geometry. They can still
            // prove focus by exact AX identity and the foreground process, without a title guess.
            if handle.windowID == nil,handle.tab == nil,let window = resolvedWindow {
                let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == info.pid }
                let app = AXUIElementCreateApplication(info.pid);AXUIElementSetMessagingTimeout(app,0.03)
                if front,let focused = Self.elementAttribute(app,kAXFocusedWindowAttribute),
                   let owner = WindowFocusOwner.window(for: focused,processID: info.pid,io: AXWindowTabIO()),CFEqual(owner,window) { return }
            }
            if attempt == 4,info.hidden {
                try Task.checkCancellation()
                _ = try await validatedHandle(id)
                let live = await MainActor.run {
                    guard !Task.isCancelled,let app = NSRunningApplication(processIdentifier: info.pid),!app.isTerminated,
                          CatalogWindowIdentity.matchesProcessLaunch(expected: info.launchedAt,actual: CatalogWindowIdentity.processLaunchDate(pid: info.pid,applicationDate: app.launchDate)) else { return false }
                    return app.activate(options: [])
                }
                try Task.checkCancellation()
                guard live || AXIsProcessTrusted() else { throw WindowCatalogError.focusFailed }
                let app = AXUIElementCreateApplication(info.pid);AXUIElementSetMessagingTimeout(app,0.03)
                _ = AXUIElementSetAttributeValue(app,kAXFrontmostAttribute as CFString,kCFBooleanTrue)
                let window = handle.tab.flatMap { tabAccessibility.selectedWindow(for: $0,processID: info.pid) } ?? resolvedWindow
                if let physicalID = window.flatMap(Self.windowID) ?? destinationID {
                    _ = WindowSpecificActivation.request(windowID: physicalID,processID: info.pid)
                }
                if let window { try await raise(window,application: info) }
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw WindowCatalogError.focusFailed
    }

    private func raise(_ window: AXUIElement, application: ApplicationInfo) async throws {
        try Task.checkCancellation()
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        try Task.checkCancellation()
        // AppKit restores a miniaturized window asynchronously. The unminimize request may
        // succeed while AXRaise still reports a transient failure during the Dock animation.
        // Retry only idempotent raising, never unsupported/stale/permission-denied actions.
        for attempt in 0..<12 {
            let live = await MainActor.run {
                guard let app = NSRunningApplication(processIdentifier: application.pid), !app.isTerminated else { return false }
                return CatalogWindowIdentity.matchesProcessLaunch(expected: application.launchedAt,
                    actual: CatalogWindowIdentity.processLaunchDate(pid: application.pid, applicationDate: app.launchDate))
            }
            guard live else { throw WindowCatalogError.expired }
            try Task.checkCancellation()
            var actualPID: pid_t = 0
            guard AXUIElementGetPid(window, &actualPID) == .success, actualPID == application.pid else { throw WindowCatalogError.expired }
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            try Task.checkCancellation()
            let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            if result == .success { return }
            guard (result == .cannotComplete || result == .failure), attempt < 11 else { throw WindowCatalogError.focusFailed }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private static func resolveAXWindow(windowID: UInt32, processID: Int32) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.05)
        let io = AXWindowTabIO()
        var candidates = [kAXFocusedWindowAttribute,kAXMainWindowAttribute].compactMap { elementAttribute(application, $0) }
        candidates += io.children(application, limit: 256) ?? []
        candidates += (attribute(application, kAXWindowsAttribute) as? [AXUIElement])?.prefix(80) ?? []
        return candidates.first { window in
            io.setTimeout(window, seconds: 0.05)
            return io.processID(window) == processID && Self.windowID(of: window) == windowID && io.role(window) == .value(kAXWindowRole as String)
        }
    }

    public func perform(_ action: WindowAction, on id: String) async throws {
        let handle = try await validatedHandle(id)
        try Task.checkCancellation()
        switch action {
        case .hideApplication, .quitApplication:
            let info = handle.application
            let result = await MainActor.run { () -> Bool in
                guard !Task.isCancelled, let app = NSRunningApplication(processIdentifier: info.pid), !app.isTerminated,
                      CatalogWindowIdentity.matchesProcessLaunch(expected: info.launchedAt,
                        actual: CatalogWindowIdentity.processLaunchDate(pid: info.pid, applicationDate: app.launchDate)) else { return false }
                // terminate() asks the app to quit normally; it may show its own save prompt.
                return action == .hideApplication ? app.hide() : app.terminate()
            }
            if !result {
                // Cooperative hiding can be refused even for a live, regular application.
                // The standard AX application attribute is an independently checked fallback.
                guard action == .hideApplication, AXIsProcessTrusted() else { throw WindowCatalogError.focusFailed }
                _ = try await validatedHandle(id)
                try Task.checkCancellation()
                let application = AXUIElementCreateApplication(info.pid)
                AXUIElementSetMessagingTimeout(application, 0.2)
                if !Self.boolean(application, kAXHiddenAttribute) {
                    guard AXUIElementSetAttributeValue(application, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success else {
                        throw WindowCatalogError.focusFailed
                    }
                }
            }
            return
        default: break
        }
        guard AXIsProcessTrusted() else { throw WindowCatalogError.permissionRequired }
        guard let window = handle.window else { throw WindowCatalogError.unsupported }
        let result: AXError
        var expectedFullscreen: Bool?
        switch action {
        case .close:
            guard let button = Self.attribute(window, kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() else { throw WindowCatalogError.unsupported }
            let close = unsafeDowncast(button, to: AXUIElement.self)
            guard (Self.attribute(close, kAXEnabledAttribute) as? NSNumber)?.boolValue != false else { throw WindowCatalogError.unsupported }
            result = AXUIElementPerformAction(close, kAXPressAction as CFString)
        case .minimize, .restore:
            guard Self.settable(window, kAXMinimizedAttribute) else { throw WindowCatalogError.unsupported }
            let value = NSNumber(value: action == .minimize)
            result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
        case .toggleFullScreen:
            guard Self.settable(window, "AXFullScreen") else { throw WindowCatalogError.unsupported }
            let desired = !Self.boolean(window, "AXFullScreen")
            expectedFullscreen = desired
            result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, NSNumber(value: desired))
        case .hideApplication, .quitApplication: return
        }
        if result != .success, (result == .cannotComplete || result == .failure), let expectedFullscreen {
            // AppKit can start its asynchronous fullscreen transition before the AX setter
            // times out. Verify the requested state; never replay a toggle during animation.
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                _ = try await validatedHandle(id)
                if let actual = Self.attribute(window, "AXFullScreen") as? NSNumber,
                   actual.boolValue == expectedFullscreen { return }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard result == .success else { throw WindowCatalogError.focusFailed }
    }

    /// Layout the selected catalog window, never whichever window happens to be frontmost.
    public func layout(_ action: WindowLayoutAction, on id: String, gap: CGFloat = 8) async throws {
        let handle = try await validatedHandle(id)
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw WindowCatalogError.permissionRequired }
        guard gap.isFinite, (0...100).contains(gap), action != .restore else { throw WindowCatalogError.unsupported }
        guard let window = handle.window, let frame = Self.frame(of: window),
              Self.settable(window, kAXPositionAttribute), Self.settable(window, kAXSizeAttribute),
              !Self.boolean(window, "AXFullScreen") else { throw WindowCatalogError.unsupported }
        let target = await MainActor.run { () -> CGRect? in
            let screens = NSScreen.screens.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
            guard let primaryHeight = NSScreen.screens.first?.frame.maxY,
                  let source = screens.max(by: { $0.frame.intersection(WindowLayoutGeometry.flip(frame, primaryHeight: primaryHeight)).area
                      < $1.frame.intersection(WindowLayoutGeometry.flip(frame, primaryHeight: primaryHeight)).area }) else { return nil }
            let current = WindowLayoutGeometry.flip(frame, primaryHeight: primaryHeight)
            let target: CGRect?
            if action == .nextDisplay || action == .previousDisplay {
                guard screens.count > 1, let index = screens.firstIndex(of: source) else { return nil }
                let next = (index + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count
                target = WindowLayoutGeometry.move(current, from: source.visibleFrame, to: screens[next].visibleFrame)
            } else {
                target = WindowLayoutGeometry.frame(for: action, in: source.visibleFrame, gap: gap, current: current)
            }
            return target.map { WindowLayoutGeometry.flip($0, primaryHeight: primaryHeight) }
        }
        guard let target else { throw WindowCatalogError.unsupported }
        _ = try await validatedHandle(id)
        try Task.checkCancellation()
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard FocusedWindow(element: window, processID: handle.application.pid).setFrame(target) else { throw WindowCatalogError.focusFailed }
    }

    private func validatedHandle(_ id: String) async throws -> Handle {
        guard let handle = handles[id] else { throw WindowCatalogError.expired }
        if let windowID = handle.validationWindowID ?? handle.windowID {
            let current = await lifecycleProvider.snapshot(admitting: [])
            guard !current.invalidates(windowID, since: handle.lifecycle) else { throw WindowCatalogError.expired }
        }
        let info = handle.application
        let valid = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: info.pid), !app.isTerminated else { return false }
            return CatalogWindowIdentity.matchesProcessLaunch(expected: info.launchedAt,
                actual: CatalogWindowIdentity.processLaunchDate(pid: info.pid, applicationDate: app.launchDate))
        }
        guard valid else { throw WindowCatalogError.expired }
        if let window = handle.window {
            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success, pid == info.pid else { throw WindowCatalogError.expired }
            if let expected = handle.windowID, let actual = Self.windowID(of: window), actual != expected { throw WindowCatalogError.expired }
        }
        return handle
    }

    // MARK: WindowServer

    /// Normal-layer windows grouped by owner. Titles are present only with Screen Recording access.
    static func serverWindows() -> [Int32: [ServerWindow]] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [Int32: [ServerWindow]] = [:]
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 80, bounds.height >= 50,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            result[pid, default: []].append(.init(id: id, pid: pid, frame: bounds, title: info[kCGWindowName as String] as? String,
                                                  onScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? false))
        }
        return result
    }

    /// Front-to-back index of on-screen windows.
    static func onScreenOrder() -> [UInt32: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [UInt32: Int] = [:]
        for (index, info) in list.enumerated() {
            if let id = info[kCGWindowNumber as String] as? UInt32 { order[id] = index }
        }
        return order
    }

    /// Displays in CoreGraphics global coordinates (top-left origin), matching CGWindow bounds and AX frames.
    @MainActor public static func displayFrames() -> [(UInt32, CGRect)] {
        guard let primary = NSScreen.screens.first?.frame else { return [] }
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let f = screen.frame
            return (number.uint32Value, CGRect(x: f.minX, y: primary.maxY - f.maxY, width: f.width, height: f.height))
        }
    }

    // MARK: AX helpers

    /// Geometry cannot identify a window when multiple entries share its bounds (for example tabs).
    /// Keep the AX handle without a capture ID rather than attach another window's image or Space.
    static func uniqueWindowID(matching frame: CGRect, candidates: [ServerWindow]) -> UInt32? {
        let matches = candidates.filter { $0.frame.isApproximately(frame) }
        return matches.count == 1 ? matches.first?.id : nil
    }

    private typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// `_AXUIElementGetWindow` maps an AX window to its WindowServer id. It is not public SDK API, so it is
    /// looked up at runtime. Catalog scans fall back to frame matching; focus events retain an AX hash alias.
    private static let axGetWindow: AXGetWindowFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: AXGetWindowFunction.self)
    }()

    static func windowID(of window: AXUIElement) -> UInt32? {
        guard let axGetWindow else { return nil }
        var id = CGWindowID(0)
        return axGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }; return value
    }
    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private static func boolean(_ element: AXUIElement, _ name: String) -> Bool { (attribute(element, name) as? NSNumber)?.boolValue ?? false }
    private static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var value = DarwinBoolean(false); return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }
    @MainActor public static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
    func isApproximately(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

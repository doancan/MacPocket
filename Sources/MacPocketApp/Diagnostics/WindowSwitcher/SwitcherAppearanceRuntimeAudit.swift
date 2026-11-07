#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor enum SwitcherAppearanceRuntimeAudit {
    @MainActor private final class Modifiers { var flags: NSEvent.ModifierFlags = .option }
    static func run(destination: URL, checks: inout [String: Bool]) async throws -> [String: Any] {
        let defaults = UserDefaults.standard
        let keys = ["titleMode", "truncation", "screen", "showStatus", "showSpaces", "showActions", "showThumbnails", "openingDelayMilliseconds",
                    "animateOpening", "animateClosing", "animateSelection", "animatePreview"].map { "switcher." + $0 } + [PocketPreferenceKey.reduceMotion]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let oldAppearance = NSApp.appearance
        defer {
            for key in keys { if let value = saved[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
            NSApp.appearance = oldAppearance
        }
        defaults.set(false, forKey: PocketPreferenceKey.reduceMotion)
        let windows = fixtureWindows()
        var variants: [[String: Any]] = []
        for style in SwitcherStyle.allCases {
            for (index, title) in SwitcherTitleMode.allCases.enumerated() {
                let capture = try AppearanceCapture()
                let model = WindowSwitcherModel(windows: windows, catalog: AppearanceCatalog(windows), previews: capture, permitsCapture: { true })
                let controller = WindowSwitcherHotkeyController(model: model, foregroundApplication: { NSRunningApplication.current })
                var shortcut = SwitcherShortcut.defaultOptionTab
                shortcut.releaseBehavior = .hold; shortcut.presentation.style = style
                shortcut.filter.separateTabs = true
                shortcut.presentation.titleMode = title; shortcut.presentation.truncation = SwitcherTitleTruncation.allCases[index % 3]
                shortcut.presentation.showSpaces = true; shortcut.presentation.showStatus = index % 2 == 0
                shortcut.presentation.showActions = false; shortcut.presentation.sizeScale = index == 3 ? 0.6 : 1
                shortcut.presentation.animateOpening = false; shortcut.presentation.animateClosing = false
                shortcut.presentation.previewSelected = false
                model.selection = windows.first?.id
                if let panel = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) {
                    try? await Task.sleep(for: .milliseconds(160))
                    let prefix = "appearance-\(style.rawValue)-\(title.rawValue)"
                    let text = WindowSwitcherRuntimeAudit.accessibilityValues(panel).joined(separator: " ")
                    checks[prefix + "FullAccessibleName"] = windows.allSatisfy { text.contains($0.application) && text.contains($0.title) }
                    checks[prefix + "StateSurvivesHiddenGlyphs"] = text.contains(String(localized: "Küçültülmüş"))
                        && text.contains(String(localized: "Masaüstü bilgisi bilinmiyor"))
                    checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(panel, to: destination.appendingPathComponent(prefix + ".png"))
                    let captures = await capture.count
                    checks[prefix + "CaptureStyle"] = style == .thumbnails ? captures > 0 : captures == 0
                    variants.append(["style": style.rawValue, "titleMode": title.rawValue, "frame": NSStringFromRect(panel.frame),
                                     "cardSize": NSStringFromSize(controller.layout.itemSize), "captureRequests": captures,
                                     "accessibility": text, "snapshot": prefix + ".png"])
                } else { checks["appearance-\(style.rawValue)-\(title.rawValue)-Panel"] = false }
                controller.stopForModule()
            }
        }
        let hiddenCapture = try AppearanceCapture(), hiddenModel = WindowSwitcherModel(windows: windows, catalog: AppearanceCatalog(windows), previews: hiddenCapture, permitsCapture: { true })
        let hiddenController = WindowSwitcherHotkeyController(model: hiddenModel)
        var hidden = SwitcherShortcut.defaultOptionTab
        hidden.presentation.style = .thumbnails; hidden.presentation.showThumbnails = false; hidden.presentation.previewSelected = false
        _ = hiddenController.beginVisualAudit(reduceTransparency: true, shortcut: hidden)
        try? await Task.sleep(for: .milliseconds(100))
        let hiddenRequests = await hiddenCapture.count
        checks["appearanceHiddenThumbnailsUseIconsWithoutCapture"] = hiddenController.style == .icons && hiddenRequests == 0
        hiddenController.stopForModule()
        let closing = await auditClosing(windows, checks: &checks)
        await auditDelay(windows, checks: &checks)
        await auditFocusCancellation(windows, checks: &checks)
        try await auditPreview(windows, checks: &checks)
        let form = await auditForm(destination, checks: &checks)
        return ["source": "owned-fixture-catalog-images-and-local-AppKit-controls", "variants": variants, "form": form, "closing": closing,
                "screenCount": NSScreen.screens.count, "physicalMultipleDisplaysVerified": false,
                "physicalHotkeysVerified": false, "screenCaptureKitVerified": false, "voiceOverVerified": false]
    }

    private static func auditClosing(_ windows: [SwitchableWindow], checks: inout [String: Bool]) async -> [String: Any] {
        let model = WindowSwitcherModel(windows: windows, catalog: AppearanceCatalog(windows), permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: model)
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.releaseBehavior = .hold; shortcut.presentation.style = .titles
        shortcut.presentation.animateOpening = false; shortcut.presentation.animateClosing = true
        model.selection = windows[0].id
        guard let panel = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) else { checks["appearanceClosingPanelAvailable"] = false; return [:] }
        try? await Task.sleep(for: .milliseconds(70))
        let subscriptions = controller.moduleDiagnosticResources["subscriptions"]
        controller.dismissForAudit()
        checks["appearanceClosingReleasesInputImmediately"] = !panel.isKeyWindow && !panel.isVisible && (PocketReduceMotion.isEnabled || controller.closingSnapshotVisibleForAudit)
        _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        try? await Task.sleep(for: .milliseconds(170))
        checks["appearanceOldClosingTaskCannotHideReopenedPanel"] = panel.isVisible && panel.alphaValue > 0.99
        checks["appearanceReopeningDoesNotDuplicateObservers"] = controller.moduleDiagnosticResources["subscriptions"] == subscriptions
        model.selection = model.filtered.first?.id
        let before = model.filtered.firstIndex { $0.id == model.selection } ?? 0
        let beforeID = model.selection ?? "nil"
        let keyBefore = panel.isKeyWindow
        await WindowSwitcherRuntimeAudit.sendKey(48, to: panel)
        checks["appearanceReopenedPanelReceivesOneTabStep"] = model.selection == model.filtered[(before + 1) % model.filtered.count].id
        let details: [String: Any] = ["before": beforeID, "after": model.selection ?? "nil", "keyBefore": keyBefore,
                                    "keyAfter": panel.isKeyWindow, "filtered": model.filtered.map(\.id), "resources": controller.moduleDiagnosticResources]
        UserDefaults.standard.set(true, forKey: PocketPreferenceKey.reduceMotion)
        controller.dismissForAudit()
        checks["appearanceReducedMotionClosesImmediately"] = !panel.isVisible
        controller.stopForModule()
        checks["appearanceStopReleasesAnimationAndFocusTasks"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        UserDefaults.standard.set(false, forKey: PocketPreferenceKey.reduceMotion)
        return details
    }
    private static func auditDelay(_ windows: [SwitchableWindow], checks: inout [String: Bool]) async {
        let catalog = AppearanceCatalog(windows), modifiers = Modifiers()
        let model = WindowSwitcherModel(windows: windows, catalog: catalog, permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: model, foregroundApplication: { NSRunningApplication.current }, modifierFlags: { modifiers.flags })
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.presentation.openingDelayMilliseconds = 900; shortcut.presentation.animateOpening = false
        controller.beginHeldAudit(shortcut: shortcut)
        try? await Task.sleep(for: .milliseconds(70))
        checks["appearanceConfiguredDelayDefersPanel"] = controller.auditPanel?.isVisible != true
        modifiers.flags = []
        controller.releaseModifiersForAudit()
        checks["appearanceQuickReleaseDoesNotWaitForPanelDelay"] = await waitUntil {
            await catalog.focused.count == 1 && controller.auditPanel?.isVisible != true
        }
        controller.stopForModule()
        modifiers.flags = .option
        let held = WindowSwitcherHotkeyController(model: WindowSwitcherModel(windows: windows, catalog: AppearanceCatalog(windows), permitsCapture: { false }),
            foregroundApplication: { NSRunningApplication.current }, modifierFlags: { modifiers.flags })
        held.beginHeldAudit(shortcut: shortcut)
        checks["appearanceHeldShortcutEventuallyShowsDelayedPanel"] = await waitUntil { held.auditPanel?.isVisible == true }
        held.stopForModule()
        checks["appearanceDelayedShowTaskIsCancelledOnStop"] = held.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        for behavior in [SwitcherReleaseBehavior.hold, .search] {
            modifiers.flags = .option
            let retainedCatalog = AppearanceCatalog(windows)
            let retainedModel = WindowSwitcherModel(windows: windows, catalog: retainedCatalog, permitsCapture: { false })
            let retained = WindowSwitcherHotkeyController(model: retainedModel, foregroundApplication: { NSRunningApplication.current }, modifierFlags: { modifiers.flags })
            shortcut.releaseBehavior = behavior
            retained.beginHeldAudit(shortcut: shortcut)
            try? await Task.sleep(for: .milliseconds(70))
            checks["appearanceDelayAppliesTo-" + behavior.rawValue] = retained.auditPanel?.isVisible != true
            modifiers.flags = []
            retained.releaseModifiersForAudit()
            checks["appearanceReleaseReveals-" + behavior.rawValue] = await waitUntil { retained.auditPanel?.isVisible == true && retainedModel.isSearching == (behavior == .search) }
            let focused = await retainedCatalog.focused
            checks["appearanceRetainedReleaseDoesNotFocus-" + behavior.rawValue] = focused.isEmpty
            retained.stopForModule()
        }
    }
    private static func auditFocusCancellation(_ windows: [SwitchableWindow], checks: inout [String: Bool]) async {
        let catalog = AppearanceCatalog(windows); await catalog.blockFocus()
        let model = WindowSwitcherModel(windows: windows, catalog: catalog, permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: model)
        var shortcut = SwitcherShortcut.defaultOptionTab; shortcut.presentation.animateClosing = false; shortcut.presentation.animateOpening = false
        model.selection = windows[0].id
        _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        controller.commitForAudit()
        checks["appearanceOldFocusIsAwaitingFixture"] = await waitUntil { await catalog.focusWaiting }
        _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        let marker = String(localized: "İşlem sürüyor…"); model.failure = marker
        await catalog.releaseFocus()
        try? await Task.sleep(for: .milliseconds(40))
        checks["appearanceCancelledFocusCannotOverwriteNewSessionError"] = model.failure == marker && controller.auditPanel?.isVisible == true
        controller.stopForModule()
    }
    private static func auditPreview(_ windows: [SwitchableWindow], checks: inout [String: Bool]) async throws {
        let capture = try AppearanceCapture()
        let model = WindowSwitcherModel(windows: windows, catalog: AppearanceCatalog(windows), previews: capture, permitsCapture: { true })
        let controller = WindowSwitcherHotkeyController(model: model)
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.presentation.style = .titles; shortcut.presentation.previewSelected = true; shortcut.presentation.animatePreview = true
        model.selection = windows[0].id
        _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        checks["appearancePreviewEntryShowsOwnedImage"] = await waitUntil { controller.previewVisibleForAudit }
        controller.stopForModule()
        checks["appearancePreviewEntryStopsWithModule"] = !controller.previewVisibleForAudit
    }
    private static func auditForm(_ destination: URL, checks: inout [String: Bool]) async -> [[String: Any]] {
        var result: [[String: Any]] = []
        for width in [520.0,760.0] {
            let window = NSWindow(contentRect: NSRect(x: 120, y: 130, width: width, height: 720), styleMask: [.titled,.closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Form {
                Section("Kart ayrıntıları") { SwitcherGlobalCardOptions() }
                Section("Panelin yeri ve gecikme") { SwitcherGlobalPlacementOptions() }
                Section("Animasyonlar") { SwitcherGlobalMotionOptions() }
            }.formStyle(.grouped).environment(\.locale, pocketLocale))
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(120))
            let nodes = ToolUIAudit.accessibilityNodes(window)
            let overflow = nodes.filter { node in
                guard let x = Double(node["x"] ?? ""), let w = Double(node["width"] ?? ""), w > 0 else { return false }
                return x < window.frame.minX - 2 || x + w > window.frame.maxX + 2
            }
            checks["appearanceForm\(Int(width))NoMeasuredHorizontalOverflow"] = overflow.isEmpty
            checks["appearanceForm\(Int(width))Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window, to: destination.appendingPathComponent("appearance-settings-\(Int(width)).png"))
            if width == 760 {
                let toggles = [("Durum simgeleri","showStatus",true), ("Masaüstü numaraları","showSpaces",false),
                    ("Fare üzerindeyken pencere düğmeleri","showActions",true), ("Küçük resimleri göster","showThumbnails",true),
                    ("Panel açılışı","animateOpening",true), ("Panel kapanışı","animateClosing",false),
                    ("Seçim animasyonu","animateSelection",true), ("Tam boy önizleme girişi","animatePreview",false)]
                for (label,key,initial) in toggles {
                    UserDefaults.standard.set(initial, forKey: "switcher." + key)
                    try? await Task.sleep(for: .milliseconds(20))
                    let pressed = press(String(localized: String.LocalizationValue(label)), in: window)
                    let changed = await waitUntil { UserDefaults.standard.object(forKey: "switcher." + key) as? Bool == !initial }
                    checks["appearanceNativeToggle-" + key] = pressed && changed
                }
                UserDefaults.standard.set(110, forKey: "switcher.openingDelayMilliseconds")
                let incremented = press(String(localized: "Açılma gecikmesi: \(110) ms"), in: window, role: .incrementor,
                                        actionName: "accessibilityPerformIncrement", fallback: .increment)
                let delayChanged = await waitUntil { UserDefaults.standard.integer(forKey: "switcher.openingDelayMilliseconds") == 120 }
                checks["appearanceNativeDelayStepper"] = incremented && delayChanged
            }
            result.append(["width": width, "accessibility": nodes, "values": WindowSwitcherRuntimeAudit.accessibilityValues(window), "controls": controlDetails(window), "overflow": overflow])
            window.close()
        }
        return result
    }
    private static func controlDetails(_ root: NSObject) -> [[String: String]] {
        var pending = [root], seen = Set<ObjectIdentifier>(), result: [[String: String]] = []
        let attribute = NSSelectorFromString("accessibilityAttributeValue:")
        while let node = pending.popLast(), seen.count < 3000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            var values: [String: String] = [:]
            for name in ["accessibilityRole", "accessibilityLabel", "accessibilityTitle", "accessibilityDescription", "accessibilityValue", "accessibilityActionNames"] {
                let selector = NSSelectorFromString(name)
                if node.responds(to: selector), let value = node.perform(selector)?.takeUnretainedValue() { values[name] = String(describing: value) }
            }
            let titleSelector = NSSelectorFromString("accessibilityTitleUIElement")
            if node.responds(to: titleSelector), let title = node.perform(titleSelector)?.takeUnretainedValue() as? NSObject {
                values["associatedTitle"] = WindowSwitcherRuntimeAudit.accessibilityValues(title).joined(separator: " ")
            }
            if node.responds(to: attribute) {
                for key in ["AXRole", "AXTitle", "AXDescription", "AXValue", "AXHelp"] {
                    if let value = node.perform(attribute, with: key)?.takeUnretainedValue() { values[key] = String(describing: value) }
                }
            }
            result.append(values)
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        return result
    }
    static func press(_ label: String, in root: NSObject, role expectedRole: NSAccessibility.Role = .checkBox,
                              actionName: String = "accessibilityPerformPress", fallback: NSAccessibility.Action = .press) -> Bool {
        var pending = [root], seen = Set<ObjectIdentifier>()
        while let node = pending.popLast(), seen.count < 3_000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            var values = ["accessibilityLabel","accessibilityTitle","accessibilityValue", "accessibilityDescription"].compactMap { name -> String? in
                let selector = NSSelectorFromString(name)
                return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
            }
            for name in ["accessibilityTitleUIElement", "accessibilityLabelUIElements"] {
                let selector = NSSelectorFromString(name)
                if node.responds(to: selector), let value = node.perform(selector)?.takeUnretainedValue() {
                    for titleNode in (value as? [NSObject] ?? (value as? NSObject).map { [$0] } ?? []) {
                        values += WindowSwitcherRuntimeAudit.accessibilityValues(titleNode)
                    }
                }
            }
            let attribute = NSSelectorFromString("accessibilityAttributeValue:")
            if node.responds(to: attribute) {
                for key in [NSAccessibility.Attribute.title, .description, .value] {
                    if let value = node.perform(attribute, with: key.rawValue)?.takeUnretainedValue() as? String { values.append(value) }
                }
            }
            let action = NSSelectorFromString(actionName)
            let roleSelector = NSSelectorFromString("accessibilityRole")
            let role = node.responds(to: roleSelector) ? node.perform(roleSelector)?.takeUnretainedValue() as? String : nil
            let checkBox = (role ?? (node.responds(to: attribute) ? node.perform(attribute, with: NSAccessibility.Attribute.role.rawValue)?.takeUnretainedValue() as? String : nil)) == expectedRole.rawValue
            let informalPress = NSSelectorFromString("accessibilityPerformAction:")
            let actionNames = NSSelectorFromString("accessibilityActionNames")
            let supported = node.responds(to: actionNames) ? node.perform(actionNames)?.takeUnretainedValue() as? [String] ?? [] : []
            if checkBox, values.contains(where: { $0.contains(label) }), node.responds(to: informalPress), supported.contains(fallback.rawValue) {
                typealias Action = @convention(c) (AnyObject, Selector, NSString) -> Void
                unsafeBitCast(node.method(for: informalPress), to: Action.self)(node, informalPress, fallback.rawValue as NSString)
                return true
            }
            if checkBox, values.contains(where: { $0.contains(label) }), node.responds(to: action) {
                typealias Press = @convention(c) (AnyObject, Selector) -> ObjCBool
                _ = unsafeBitCast(node.method(for: action), to: Press.self)(node, action)
                // Verify the resulting bound state; never retry a mutating action based on this
                // private SwiftUI wrapper's return value, which can be false after taking effect.
                return true
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        return false
    }
    private static func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(2)
        repeat { if await condition() { return true }; try? await Task.sleep(for: .milliseconds(10)) } while Date() < end
        return false
    }
    private static func fixtureWindows() -> [SwitchableWindow] {
        let application = NSRunningApplication.current.localizedName ?? "MacPocket"
        let title = String(localized: "MacPocket · Masaüstü testi") + " — /Reports/2026/Quarterly/Projects/Workspace/Window/Final.txt"
        let frame = CGRect(x: 120, y: 140, width: 600, height: 400), pid = getpid()
        var root = SwitchableWindow(id: "appearance-root", processID: pid, application: application, title: title, applicationURL: Bundle.main.bundleURL,
            minimized: false, hidden: false, fullScreen: false, frontmost: true, windowAccessible: true, canClose: true, canMinimize: true, canFullScreen: true,
            launchedAt: Date(timeIntervalSince1970: 10), lastFocusedAt: nil, windowID: 1, frame: frame)
        root.spaceMembership = .init(spaces: [.init(id: 900, ordinal: 4, displayIdentifier: "fixture", kind: .desktop, visible: false)])
        let bar = WindowTabBar(groupID: "fixture-group", anchorID: root.id, controls: [.init(id: "a", title: title, selected: true), .init(id: "b", title: title + " — 2", selected: false)])!
        let tabs = WindowTabProjectionResolver.project([root], surfaces: [.init(id: 1, processID: pid, frame: frame, spaceIDs: [900]),
            .init(id: 2, processID: pid, frame: frame, spaceIDs: [])], bars: [bar]).windows
        return tabs + [SwitchableWindow(id: "appearance-minimized", processID: pid, application: application, title: title + " — 3", applicationURL: Bundle.main.bundleURL,
            minimized: true, hidden: true, fullScreen: false, frontmost: false, windowAccessible: true, canClose: true, canMinimize: true, canFullScreen: true,
            launchedAt: Date(timeIntervalSince1970: 10), lastFocusedAt: nil, windowID: 3, frame: frame)]
    }
}

private actor AppearanceCatalog: WindowCatalogServing {
    let windows: [SwitchableWindow]
    private(set) var focused: [String] = []
    private var blocked = false, pending: CheckedContinuation<Void,Never>?
    var focusWaiting: Bool { pending != nil }
    init(_ windows: [SwitchableWindow]) { self.windows = windows }
    func snapshot() async -> WindowCatalogReport { .init(windows: windows, accessibilityGranted: true, partial: false) }
    func focus(_ id: String) async throws {
        if blocked { await withCheckedContinuation { pending = $0 }; throw WindowCatalogError.expired }
        focused.append(id)
    }
    func blockFocus() { blocked = true }
    func releaseFocus() { blocked = false; pending?.resume(); pending = nil }
    func perform(_ action: WindowAction, on id: String) async throws { throw WindowCatalogError.unsupported }
    func noteApplicationActivation(_ pid: Int32) async {}
}
private actor AppearanceCapture: WindowPreviewCapturing {
    private let image: WindowImage
    private(set) var count = 0
    init() throws {
        guard let context = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 96,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw WindowPreviewError.unavailable }
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: 24,height: 16))
        guard let cgImage = context.makeImage() else { throw WindowPreviewError.unavailable }
        image = WindowImage(cgImage: cgImage)
    }
    func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage { count += 1; return image }
}
#endif

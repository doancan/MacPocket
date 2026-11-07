#if DEBUG
import AppKit
import MacPocketCore

/// Tests AppKit's actual tab controls in our own process. This is deliberately distinct from
/// cross-process AXUIElement access, which requires the production application's TCC grant.
@MainActor
enum WindowTabsRuntimeAudit {
    private struct NativeBar {
        let group: NSObject
        let buttons: [NSObject]
        let value: WindowTabBar
    }

    static func run(destination: URL, checks: inout [String: Bool]) async -> [String: Any] {
        func makeWindow() -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 160, y: 190, width: 560, height: 360),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = String(localized: "MacPocket · Masaüstü testi") // Deliberately duplicate labels.
            window.tabbingMode = .preferred
            return window
        }
        let first = makeWindow(), second = makeWindow()
        let tabbingID = "MacPocket.OwnedTabAudit." + UUID().uuidString
        first.tabbingIdentifier = tabbingID; second.tabbingIdentifier = tabbingID
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        defer { first.close(); second.close() }
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(250))
        let firstID = UInt32(first.windowNumber), secondID = UInt32(second.windowNumber)
        let catalog = WindowCatalog()
        let report = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        guard let root = report.windows.first(where: { $0.windowID == firstID }),
              let native = tabBar(first, anchorID: root.id) else {
            checks["ownedNativeTabBarAvailable"] = false
            return ["source": "owned-AppKit-NSAccessibility", "externalAXTabFocusVerified": false]
        }
        checks["ownedNativeTabBarAvailable"] = native.value.controls.count == 2
            && native.value.controls.map(\.title) == [first.title, second.title]
        let before = await WindowSpaceProvider.shared.snapshot(windowIDs: [firstID, secondID])
        let physical = surfaces(ids: [firstID, secondID], spaces: before)
        checks["ownedNativeTabsHaveAssignedAndEmptySpaceSurfaces"] = before.memberships[firstID]?.isEmpty == false
            && before.memberships[secondID]?.isEmpty == true && physical.count == 2
        let projection = WindowTabProjectionResolver.project([root], surfaces: physical, bars: [native.value])
        checks["ownedNativeTabsProjectTwoDistinctControls"] = projection.windows.count == 2
            && Set(projection.windows.map(\.id)).count == 2
        checks["ownedNativeTabsDoNotGuessBackgroundCaptureID"] = projection.windows.map(\.windowID) == [firstID, nil]
            && projection.windows.last?.canCapturePreview == false
        checks["ownedNativeTabsGroupedByDefault"] = WindowFiltering.apply(projection.windows, filter: .init()).count == 1

        var styleEvidence: [[String: Any]] = []
        if projection.windows.count == 2 {
            for style in SwitcherStyle.allCases {
                var shortcut = SwitcherShortcut.defaultOptionTab
                shortcut.filter.separateTabs = true; shortcut.presentation.style = style; shortcut.releaseBehavior = .hold
                let model = WindowSwitcherModel(windows: projection.windows, permitsCapture: { false })
                let controller = WindowSwitcherHotkeyController(model: model)
                model.selection = projection.windows[1].id
                if let panel = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) {
                    try? await Task.sleep(for: .milliseconds(160))
                    let values = WindowSwitcherRuntimeAudit.accessibilityValues(panel)
                    let text = values.joined(separator: " ")
                    styleEvidence.append(["style": style.rawValue, "accessibilityValues": values])
                    checks["ownedNativeTabs-\(style.rawValue)-SeparateAndSelected"] = model.filtered.count == 2
                        && model.selection == projection.windows[1].id
                    checks["ownedNativeTabs-\(style.rawValue)-LocalizedOrdinal"] = projection.windows.allSatisfy {
                        $0.nativeTab.map { text.contains($0.localizedDescription) } == true
                    }
                    checks["ownedNativeTabs-\(style.rawValue)-Snapshot"] = snapshot(panel,
                        to: destination.appendingPathComponent("native-tabs-\(style.rawValue).png"))
                } else { checks["ownedNativeTabs-\(style.rawValue)-Panel"] = false }
                controller.stopForModule()
            }
        }
        let target = native.value.controls[1]
        let index = WindowTabProjectionResolver.activationIndex(controlID: target.id, title: target.title, in: native.value)
        let button = index.map { native.buttons[$0] }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        var pressed = false
        if let button, button.responds(to: selector) {
            // The getter returns BOOL; NSObject.perform would incorrectly interpret it as an object.
            pressed = unsafeBitCast(button.method(for: selector), to: Press.self)(button, selector)
        }
        let deadline = Date().addingTimeInterval(2)
        while first.tabGroup?.selectedWindow !== second, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        checks["ownedNativeAccessibilityPressSelectsExactDuplicateTitleTab"] = pressed && first.tabGroup?.selectedWindow === second
        // AppKit updates selectedWindow before WindowServer commits the tab's physical surface.
        // Verify the latter too; the action's BOOL result alone is insufficient.
        var after = WindowSpaceSnapshot()
        let membershipDeadline = Date().addingTimeInterval(2)
        repeat {
            after = await WindowSpaceProvider.shared.snapshot(windowIDs: [firstID, secondID])
            if after.memberships[firstID]?.isEmpty == true && after.memberships[secondID] == before.memberships[firstID] { break }
            try? await Task.sleep(for: .milliseconds(30))
        } while Date() < membershipDeadline
        checks["ownedNativeTabSelectionSwapsPhysicalSpaceMembership"] = after.memberships[firstID]?.isEmpty == true
            && after.memberships[secondID] == before.memberships[firstID]
        let fresh = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        if let secondRoot = fresh.windows.first(where: { $0.windowID == secondID }), let changed = tabBar(second, anchorID: secondRoot.id) {
            let changedProjection = WindowTabProjectionResolver.project([secondRoot], surfaces: surfaces(ids: [firstID, secondID], spaces: after), bars: [changed.value])
            checks["ownedNativeTabControlIdentitySurvivesSelection"] = changed.group === native.group
                && changedProjection.windows.map(\.id) == projection.windows.map(\.id)
                && changedProjection.windows.map(\.windowID) == [nil, secondID]
        } else { checks["ownedNativeTabControlIdentitySurvivesSelection"] = false }
        let cacheEvidence = await WindowTabSpaceRuntimeAudit.run(first: first, second: second, destination: destination, checks: &checks)
        return ["source": "owned-AppKit-NSAccessibility-and-production-projection",
                "spaceCache": cacheEvidence,
                "titlesAreIdentical": first.title == second.title, "physicalSurfaceIDs": [firstID, secondID],
                "styleVariants": styleEvidence,
                "beforeMemberships": [String(firstID): Array(before.memberships[firstID] ?? []), String(secondID): Array(before.memberships[secondID] ?? [])],
                "afterMemberships": [String(firstID): Array(after.memberships[firstID] ?? []), String(secondID): Array(after.memberships[secondID] ?? [])],
                "externalAXTabFocusVerified": false, "screenCaptureVerified": false]
    }

    private static func attribute(_ object: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }
    private static func tabBar(_ window: NSWindow, anchorID: String) -> NativeBar? {
        guard let group = (window.accessibilityChildren() as? [NSObject])?.first(where: {
            attribute($0, "accessibilityRole") as? String == "AXTabGroup"
        }), let children = attribute(group, "accessibilityChildren") as? [NSObject] else { return nil }
        let buttons = children.filter { attribute($0, "accessibilitySubrole") as? String == "AXTabButton" }
        let controls = buttons.map { button in
            WindowTabControl(id: String(describing: ObjectIdentifier(button)), title: attribute(button, "accessibilityTitle") as? String ?? "",
                             selected: (attribute(button, "accessibilityValue") as? NSNumber)?.boolValue == true)
        }
        guard let value = WindowTabBar(groupID: String(describing: ObjectIdentifier(group)), anchorID: anchorID, controls: controls) else { return nil }
        return .init(group: group, buttons: buttons, value: value)
    }
    private static func surfaces(ids: Set<UInt32>, spaces: WindowSpaceSnapshot) -> [WindowTabSurface] {
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? UInt32, ids.contains(id),
                  let pid = row[kCGWindowOwnerPID as String] as? Int32, pid == getpid(),
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return .init(id: id, processID: pid, frame: frame, spaceIDs: spaces.memberships[id])
        }
    }
    private static func snapshot(_ window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }
}
#endif

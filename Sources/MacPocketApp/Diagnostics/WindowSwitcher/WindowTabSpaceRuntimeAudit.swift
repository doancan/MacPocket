#if DEBUG
import AppKit
import MacPocketCore

@MainActor enum WindowTabSpaceRuntimeAudit {
    @MainActor private final class Transition { var entered = false; var exited = false }
    static func run(first: NSWindow, second: NSWindow, destination: URL, checks: inout [String: Bool]) async -> [String: Any] {
        let firstID = UInt32(first.windowNumber), secondID = UInt32(second.windowNumber), ids: Set<UInt32> = [firstID, secondID]
        let catalog = WindowCatalog(), bridge = WindowTabOwnedAuditBridge()
        let initialSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: Array(ids))
        let initialReport = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        let initial = bridge.snapshot(listedWindows: [second], windows: initialReport.windows.filter { $0.windowID.map(ids.contains) == true },
                                      surfaces: surfaces(ids, spaces: initialSpaces), spaces: initialSpaces)
        checks["ownedTabCacheInitialPhysicalGroupIsRemembered"] = initial.rememberedGroups == 1 && initial.windows.count == 2
        let initialCardIDs = initial.windows.map(\.id)
        let anchor = NSWindow(contentRect: NSRect(x: 100, y: 140, width: 480, height: 320),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        anchor.isReleasedWhenClosed = false; anchor.tabbingMode = .disallowed
        anchor.title = String(localized: "MacPocket · Masaüstü testi"); anchor.collectionBehavior = [.fullScreenPrimary]
        let transition = Transition()
        let entered = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: anchor, queue: .main) { _ in
            MainActor.assumeIsolated { transition.entered = true }
        }
        let exited = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: anchor, queue: .main) { _ in
            MainActor.assumeIsolated { transition.exited = true }
        }
        defer { NotificationCenter.default.removeObserver(entered); NotificationCenter.default.removeObserver(exited); anchor.close(); bridge.reset() }
        anchor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(180))
        anchor.toggleFullScreen(nil)
        let enterDeadline = Date().addingTimeInterval(6)
        var offSpaces = WindowSpaceSnapshot()
        repeat {
            offSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: Array(ids))
            if transition.entered && offSpaces.membership(for: secondID)?.isVisible == false { break }
            try? await Task.sleep(for: .milliseconds(40))
        } while Date() < enterDeadline
        checks["ownedTabCacheFixtureIsActuallyOnAnotherSpace"] = transition.entered && offSpaces.membership(for: secondID)?.isVisible == false
        let offReport = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        let off = bridge.snapshot(listedWindows: [], windows: offReport.windows.filter { $0.windowID.map(ids.contains) == true },
                                  surfaces: surfaces(ids, spaces: offSpaces), spaces: offSpaces)
        checks["ownedTabCacheRecoversOmittedAXRootOnAnotherSpace"] = off.recoveredWindowIDs == [secondID]
            && off.windows.count == 2 && off.windows.allSatisfy { $0.nativeTab != nil }
        checks["ownedTabCacheCardIdentitiesSurviveSpaceChange"] = off.windows.map(\.id) == initialCardIDs
        var filter = WindowListFilter(); filter.separateTabs = true; filter.spaceScope = .visible
        checks["ownedTabCacheActualOffSpaceMembershipControlsFilter"] = WindowFiltering.apply(off.windows, filter: filter).isEmpty
        filter.spaceScope = .notVisible
        checks["ownedTabCacheActualOffSpaceTabsRemainSearchable"] = WindowFiltering.apply(off.windows, filter: filter).count == 2
        let priorTitle = second.title
        second.title = String(localized: "Başlıksız sekme")
        let renamed = bridge.snapshot(listedWindows: [], windows: [], surfaces: surfaces(ids, spaces: offSpaces), spaces: offSpaces)
        checks["ownedTabCacheUsesFreshOffSpaceTitle"] = renamed.windows.contains { $0.title == second.title && $0.nativeTab?.selected == true }
            && renamed.windows.map(\.id) == initialCardIDs
        second.title = priorTitle
        if transition.entered { anchor.toggleFullScreen(nil) }
        let exitDeadline = Date().addingTimeInterval(6)
        var restoredSpaces = WindowSpaceSnapshot()
        repeat {
            restoredSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: Array(ids))
            if transition.exited && restoredSpaces.membership(for: secondID)?.isVisible == true { break }
            try? await Task.sleep(for: .milliseconds(40))
        } while Date() < exitDeadline
        checks["ownedTabCacheFixtureRestoresOriginalSpace"] = transition.exited
            && restoredSpaces.membership(for: secondID)?.spaces.map(\.id) == initialSpaces.membership(for: secondID)?.spaces.map(\.id)
        checks["ownedTabCacheFixtureRemovesTemporarySpace"] = Set(restoredSpaces.spaces.map(\.id)) == Set(initialSpaces.spaces.map(\.id))
        let restored = bridge.snapshot(listedWindows: [], windows: [], surfaces: surfaces(ids, spaces: restoredSpaces), spaces: restoredSpaces)
        checks["ownedTabCacheFreshReadAfterReturnPreservesIdentity"] = restored.windows.map(\.id) == initialCardIDs
        if let target = restored.windows.first(where: { $0.nativeTab?.selected == false }) {
            do { try bridge.press(target.id) }
            catch { checks["ownedTabCacheExactControlPressAfterSpaceRoundTrip"] = false }
            let selectDeadline = Date().addingTimeInterval(2)
            while bridge.selectedWindowID(for: target.id) != firstID, Date() < selectDeadline { try? await Task.sleep(for: .milliseconds(20)) }
            checks["ownedTabCacheExactControlPressAfterSpaceRoundTrip"] = bridge.selectedWindowID(for: target.id) == firstID
                && first.tabGroup?.selectedWindow === first
            let physicalDeadline = Date().addingTimeInterval(2)
            var selectedSpaces = WindowSpaceSnapshot()
            repeat {
                selectedSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: Array(ids))
                if selectedSpaces.memberships[firstID]?.isEmpty == false && selectedSpaces.memberships[secondID]?.isEmpty == true { break }
                try? await Task.sleep(for: .milliseconds(20))
            } while Date() < physicalDeadline
            let selected = bridge.snapshot(listedWindows: [], windows: [], surfaces: surfaces(ids, spaces: selectedSpaces), spaces: selectedSpaces)
            checks["ownedTabCacheFollowsChangedWindowRootWithoutAXList"] = selected.recoveredWindowIDs == [firstID]
                && selected.windows.map(\.id) == initialCardIDs && selected.windows.first(where: { $0.nativeTab?.selected == true })?.windowID == firstID
            let model = WindowSwitcherModel(windows: selected.windows, permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model)
            var shortcut = SwitcherShortcut.defaultOptionTab
            shortcut.filter.separateTabs = true; shortcut.presentation.style = .titles; shortcut.releaseBehavior = .hold
            model.selection = selected.windows.last?.id
            if let panel = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) {
                try? await Task.sleep(for: .milliseconds(140))
                checks["ownedTabCacheRoundTripNativeSnapshot"] = WindowSwitcherRuntimeAudit.snapshot(panel,
                    to: destination.appendingPathComponent("native-tabs-space-roundtrip.png"))
            } else { checks["ownedTabCacheRoundTripNativeSnapshot"] = false }
            controller.stopForModule()
            if let removedID = selected.windows.first(where: { $0.nativeTab?.selected == false })?.id {
                let sameTitle = second.title
                second.close()
                let replacement = NSWindow(contentRect: first.contentRect(forFrameRect: first.frame),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                replacement.isReleasedWhenClosed = false; replacement.title = sameTitle; replacement.tabbingMode = .preferred
                replacement.tabbingIdentifier = first.tabbingIdentifier
                first.addTabbedWindow(replacement, ordered: .above); first.tabGroup?.selectedWindow = first
                defer { replacement.close() }
                try? await Task.sleep(for: .milliseconds(100))
                let attempts = bridge.actionAttempts
                var expired = false
                do { try bridge.press(removedID) } catch WindowCatalogError.expired { expired = true } catch {}
                checks["ownedTabCacheRejectsRemovedControlAfterSameTitleReplacement"] = expired && bridge.actionAttempts == attempts
                    && first.tabGroup?.selectedWindow === first
            } else { checks["ownedTabCacheRejectsRemovedControlAfterSameTitleReplacement"] = false }
        } else { checks["ownedTabCacheExactControlPressAfterSpaceRoundTrip"] = false }
        bridge.reset()
        let reset = bridge.snapshot(listedWindows: [], windows: [], surfaces: surfaces(ids, spaces: restoredSpaces), spaces: restoredSpaces)
        checks["ownedTabCacheResetReleasesRecoveryReferences"] = reset.rememberedGroups == 0 && reset.windows.isEmpty
        return ["source": "shared-production-discovery-with-owned-formal-NSAccessibility-transport",
                "listedAXWindowsIntentionallyOmitted": true, "offSpaceWindowIDs": off.recoveredWindowIDs,
                "beforeMembership": initialSpaces.membership(for: secondID)?.spaces.map(\.id) ?? [],
                "offSpaceMembership": offSpaces.membership(for: secondID)?.spaces.map(\.id) ?? [],
                "externalAXTransportVerified": false, "otherSpaceFocusVerified": false,
                "didEnterFullscreen": transition.entered, "didExitFullscreen": transition.exited]
    }
    private static func surfaces(_ ids: Set<UInt32>, spaces: WindowSpaceSnapshot) -> [WindowTabSurface] {
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? UInt32, ids.contains(id),
                  let pid = row[kCGWindowOwnerPID as String] as? Int32, pid == getpid(),
                  let bounds = row[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return .init(id: id, processID: pid, frame: frame, spaceIDs: spaces.memberships[id])
        }
    }
}
#endif

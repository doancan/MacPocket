#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

/// Runs the Disk Röntgeni page end to end against a throwaway home folder: scan, select, confirm, remove.
/// Nothing outside the fixture is measured or touched. Usage: `--audit-system-data <output directory>`.
@MainActor enum SystemDataRuntimeAudit {
    static var requested: Bool { CommandLine.arguments.contains("--audit-system-data") }

    static func configureIfRequested() {
        guard requested else { return }
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        values[PocketPreferenceKey.showWindowAtLaunch] = false
        for module in PocketModule.allCases { values[module.availabilityKey] = false }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }

    static func launch() {
        guard let index = CommandLine.arguments.firstIndex(of: "--audit-system-data"), CommandLine.arguments.indices.contains(index + 1) else {
            NSApp.terminate(nil); return
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        Task { await run(output: output); NSApp.terminate(nil) }
    }

    private static func write(_ relative: String, in home: URL, megabytes: Int) throws {
        let file = home.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: megabytes * 1_000_000).write(to: file)
    }

    private static func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 { if condition() { return true }; try? await Task.sleep(for: .milliseconds(50)) }
        return false
    }

    /// A real key press, routed the way the system routes it, to the window or sheet that should answer.
    @discardableResult
    private static func press(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], in target: NSWindow?) -> Bool {
        guard let target, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                                      context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                      isARepeat: false, keyCode: keyCode) else { return false }
        if target.performKeyEquivalent(with: event) { return true }
        target.sendEvent(event)
        return true
    }

    /// A real click at the middle of an accessibility element's frame.
    private static func click(_ frame: CGRect, in window: NSWindow) {
        let local = window.convertFromScreen(frame)
        let point = NSPoint(x: local.midX, y: local.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                              pressure: type == .leftMouseDown ? 1 : 0) { window.sendEvent(event) }
        }
    }

    /// A real mouse click delivered through the window server to this process only.
    private static func realClick(_ frame: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: frame.midX, y: primaryHeight - frame.midY)   // Cocoa (bottom-left) → display (top-left)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { continue }
            event.postToPid(getpid())
        }
    }

    private static let interactiveRoles: Set<String> = ["AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXTextField",
                                                        "AXRadioButton", "AXSlider", "AXSwitch", "AXDisclosureTriangle", "AXSegmentedControl"]

    private static func snapshot(_ view: NSView?, to url: URL) {
        guard let view else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func run(output: URL) async {
        // A normal foreground app, so its windows are really drawn (an accessory app's are not, and captures come out blank).
        NSApp.setActivationPolicy(.regular)
        var checks: [String: Bool] = [:]
        var details0: [String: Any] = [:]
        let dark = CommandLine.arguments.contains("--audit-dark")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let base = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                   appropriateFor: FileManager.default.temporaryDirectory, create: true)
            let resolved = realpath(base.path, nil)
            defer { free(resolved) }
            let root = URL(fileURLWithPath: resolved.map { String(cString: $0) } ?? base.path, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let home = root.appending(path: "home", directoryHint: .isDirectory)
            try write("Library/Caches/Homebrew/downloads/pkg.tar", in: home, megabytes: 12)
            try write("Library/Developer/Xcode/DerivedData/App-abc/Build/out.bin", in: home, megabytes: 30)
            try write("Library/Logs/app.log", in: home, megabytes: 4)
            try write(".cargo/registry/cache/crate.bin", in: home, megabytes: 9)
            try write("Projects/web/package.json", in: home, megabytes: 0)
            try write("Projects/web/node_modules/dep/index.js", in: home, megabytes: 25)
            try write("Library/Containers/com.gone.app/Data/blob.bin", in: home, megabytes: 220)
            try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
            try write("system/Library/Logs/DiagnosticReports/crash.ips", in: root, megabytes: 3)

            let defaults = UserDefaults(suiteName: "SystemDataAudit-" + UUID().uuidString)!
            let store = SystemDataHistoryStore(url: root.appending(path: "history.json"))
            let environment = SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system", directoryHint: .isDirectory),
                                                    temporaryDirectory: home.appending(path: "tmp"), run: { _, _ in nil },
                                                    installedAppName: { _ in nil }, capacity: { nil })
            let model = SystemDataViewModel(defaults: defaults, store: store, environment: environment,
                                            remover: SystemDataRemover(runCommand: { _, _ in (1, "not used in audit") }),
                                            archiver: SystemDataArchiver(manifest: root.appending(path: "archives.json")),
                                            removalMode: { .deletePermanently }, summaryFile: nil)
            // ---- Two more states: a scan in progress (slow tools), and a scan that finds nothing ----
            func stateModel(home stateHome: URL, slow: Bool) -> SystemDataViewModel {
                let env = SystemDataEnvironment(home: stateHome, systemRoot: root.appending(path: "system-empty", directoryHint: .isDirectory),
                                                temporaryDirectory: stateHome.appending(path: "tmp"),
                                                run: { _, _ in if slow { try? await Task.sleep(for: .milliseconds(900)) }; return nil },
                                                installedAppName: { _ in nil }, capacity: { nil })
                return SystemDataViewModel(defaults: UserDefaults(suiteName: "SystemDataAudit-" + UUID().uuidString)!,
                                           store: SystemDataHistoryStore(url: root.appending(path: "h-\(UUID().uuidString).json")), environment: env,
                                           remover: SystemDataRemover(runCommand: { _, _ in (1, "unused") }),
                                           archiver: SystemDataArchiver(manifest: root.appending(path: "a-\(UUID().uuidString).json")),
                                           removalMode: { .deletePermanently }, summaryFile: nil)
            }
            func stateWindow(_ model: SystemDataViewModel) -> NSWindow {
                let probe = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .resizable],
                                     backing: .buffered, defer: false)
                probe.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                probe.contentView = NSHostingView(rootView: SystemDataView(model: model).frame(minWidth: 600, minHeight: 600))
                probe.center(); probe.makeKeyAndOrderFront(nil)
                return probe
            }
            let slowModel = stateModel(home: home, slow: true)
            let scanningWindow = stateWindow(slowModel)
            try? await Task.sleep(for: .milliseconds(2300))
            snapshot(scanningWindow.contentView, to: output.appending(path: "scanning.png"))
            checks["progressShownWhileScanning"] = slowModel.isScanning && slowModel.scanProgress != nil && !slowModel.items.isEmpty
            details0["progressWhileScanning"] = slowModel.scanProgress.map { "phase \($0.phaseIndex)/\(SystemDataScanProgress.phaseCount), \($0.visitedEntries) entries, \(slowModel.items.count) items so far" } ?? "none"
            slowModel.cancelScan()
            _ = await wait { !slowModel.isScanning }
            scanningWindow.close()

            let emptyHome = root.appending(path: "empty-home", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: emptyHome.appending(path: "tmp"), withIntermediateDirectories: true)
            let emptyModel = stateModel(home: emptyHome, slow: false)
            let emptyWindow = stateWindow(emptyModel)
            _ = await wait { emptyModel.report != nil && !emptyModel.isScanning }
            try? await Task.sleep(for: .milliseconds(500))
            snapshot(emptyWindow.contentView, to: output.appending(path: "empty.png"))
            checks["emptyStateWhenNothingFound"] = emptyModel.report != nil && emptyModel.items.isEmpty
            emptyWindow.close()

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 820), styleMask: [.titled, .closable, .resizable],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = NSHostingView(rootView: SystemDataView(model: model).frame(minWidth: 600, minHeight: 600))
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // SwiftUI builds its accessibility tree only for an assistive client; this is what VoiceOver switches on.
            NSApp.setValue(true, forKey: "accessibilityEnhancedUserInterface")

            checks["scanFinished"] = await wait { model.phase == .ready && model.report != nil }
            let ids = Set(model.items.map(\.id))
            checks["foundDerivedData"] = ids.contains("xcode.derivedData")
            checks["foundHomebrew"] = ids.contains("pkg.homebrew")
            checks["foundProject"] = model.items.contains { $0.group == .projects }
            checks["foundOrphanContainer"] = model.items.contains { $0.title == "com.gone.app" }
            checks["scanComplete"] = model.report?.complete == true
            model.expandedGroups = Set(SystemDataGroup.allCases)
            try? await Task.sleep(for: .milliseconds(600))
            snapshot(window.contentView, to: output.appending(path: dark ? "items-dark.png" : "items.png"))

            // `--audit-hold <seconds>`: stop here so an outside tool can read the real accessibility tree, as VoiceOver would.
            if let index = CommandLine.arguments.firstIndex(of: "--audit-hold"), CommandLine.arguments.indices.contains(index + 1),
               let seconds = Double(CommandLine.arguments[index + 1]) {
                model.toggleSafe()
                model.expandedGroups = Set(SystemDataGroup.allCases)
                try? await Task.sleep(for: .milliseconds(800))
                try? Data("\(getpid())".utf8).write(to: output.appending(path: "hold-ready"))
                try? await Task.sleep(for: .seconds(seconds))
                model.clearSelection()
            }

            // ---- Experience: layout at three widths, accessibility tree, keyboard, pointer ----
            var details: [String: Any] = [:]
            var overflowByWidth: [String: Int] = [:]
            for width in [760.0, 1000.0, 1400.0] {
                window.setContentSize(NSSize(width: width, height: 820))
                try? await Task.sleep(for: .milliseconds(600))
                window.contentView?.layoutSubtreeIfNeeded()
                snapshot(window.contentView, to: output.appending(path: "layout-\(Int(width)).png"))
                let nodes = ToolUIAudit.accessibilityNodes(window)
                let outside = nodes.filter { node in
                    guard Self.interactiveRoles.contains(node["role"] ?? ""), let x = Double(node["x"] ?? ""), let w = Double(node["width"] ?? ""), w > 0 else { return false }
                    return x < window.frame.minX - 2 || x + w > window.frame.maxX + 2
                }
                overflowByWidth["\(Int(width))"] = outside.count
            }
            details["controlsOutsideWindowByWidth"] = overflowByWidth
            checks["noControlOutsideTheWindowAtAnyWidth"] = overflowByWidth.values.allSatisfy { $0 == 0 }
            window.setContentSize(NSSize(width: 1100, height: 820))
            try? await Task.sleep(for: .milliseconds(500))

            let allNodes = ToolUIAudit.accessibilityNodes(window)
            let controls = allNodes.filter { Self.interactiveRoles.contains($0["role"] ?? "") }
            // The window's own traffic lights and the system scroll bar parts are not ours to label.
            let windowTop = window.frame.maxY
            let unlabeled = controls.filter { node in
                guard (node["name"] ?? "").isEmpty, node["width"] != nil else { return false }   // frameless nodes are phantoms, not controls
                let width = Double(node["width"] ?? "") ?? 100, height = Double(node["height"] ?? "") ?? 100, y = Double(node["y"] ?? "") ?? 0
                let isTrafficLight = width <= 16 && height <= 16 && y >= windowTop - 40
                let isScrollerPart = width <= 8 || height <= 1
                return !isTrafficLight && !isScrollerPart
            }
            details["interactiveControls"] = controls.count
            details["unlabeledControls"] = unlabeled.map { "\($0["role"] ?? "?")@\($0["x"] ?? "?"),\($0["y"] ?? "?") size \($0["width"] ?? "?")x\($0["height"] ?? "?") value=\($0["value"] ?? "-") desc=\($0["roleDescription"] ?? "-") id=\($0["identifier"] ?? "-") \($0.filter { $0.key.hasPrefix("attr") }.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))" }
            details["labeledControls"] = controls.filter { !($0["name"] ?? "").isEmpty }.map { "\($0["role"] ?? "?"):\($0["name"] ?? "")" }
            details["windowFrame"] = "\(window.frame)"
            checks["everyControlHasAnAccessibleName"] = unlabeled.isEmpty && controls.count > 10
            details0 = details

            // ⌘F lands in the search field from any tab.
            model.tab = .automation
            try? await Task.sleep(for: .milliseconds(300))
            Self.press("f", keyCode: 3, .command, in: window)
            try? await Task.sleep(for: .milliseconds(400))
            checks["commandFFocusesSearchAndSwitchesToItems"] = model.tab == .items && window.firstResponder is NSText
            window.makeFirstResponder(nil)

            // Typing Turkish letters filters; the page keeps the choice and the selection.
            // Turkish: "kayit" must find "Cargo kayıt defteri". English: the same item is "Cargo registry".
            model.filter = (Bundle.main.preferredLocalizations.first ?? "tr").hasPrefix("tr") ? "kayit" : "cargo reg"
            try? await Task.sleep(for: .milliseconds(300))
            checks["plainLettersFindTurkishNames"] = model.visibleItems.contains { $0.id == "pkg.cargo" }
            model.filter = ""

            // A click on a row's text selects it; a second click clears it. The target is the first checkbox that is on screen
            // (the list scrolls, so lower rows are below the fold); the click lands to the right of it, on the text block.
            model.expandedGroups = Set(SystemDataGroup.allCases)
            try? await Task.sleep(for: .milliseconds(600))
            let rowNodes = ToolUIAudit.accessibilityNodes(window)
            func rect(_ node: [String: String]) -> CGRect? {
                guard let x = Double(node["x"] ?? ""), let y = Double(node["y"] ?? ""), let w = Double(node["width"] ?? ""), let h = Double(node["height"] ?? "") else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
            let visibleBounds = CGRect(x: window.frame.minX, y: window.frame.minY + 120, width: window.frame.width, height: window.frame.height - 280)
            let removableTitles = Set(model.items.filter(\.isRemovable).map(\.title))
            if let box = rowNodes.first(where: { ($0["role"] ?? "") == "AXCheckBox" && removableTitles.contains($0["name"] ?? "")
                                                  && (rect($0).map { visibleBounds.contains($0) } ?? false) }),
               let boxRect = rect(box), let target = model.items.first(where: { $0.title == box["name"] }) {
                let textPoint = CGRect(x: boxRect.maxX + 120, y: boxRect.minY, width: 1, height: boxRect.height)
                details["clickTarget"] = "\(target.title) at \(textPoint)"
                Self.click(textPoint, in: window)
                try? await Task.sleep(for: .milliseconds(400))
                checks["clickingARowSelectsIt"] = model.selection.contains(target.id)
                Self.click(textPoint, in: window)
                try? await Task.sleep(for: .milliseconds(400))
                checks["clickingAgainClearsIt"] = !model.selection.contains(target.id)
                // The checkbox itself still works.
                Self.click(boxRect, in: window)
                try? await Task.sleep(for: .milliseconds(400))
                checks["checkboxStillSelects"] = model.selection.contains(target.id)
                model.clearSelection()
            } else {
                details["clickTarget"] = "no on-screen removable row found"
                checks["clickingARowSelectsIt"] = false
            }

            // ⌘R rescans.
            Self.press("r", keyCode: 15, .command, in: window)
            try? await Task.sleep(for: .milliseconds(100))
            checks["commandRStartsAScan"] = model.isScanning
            _ = await wait { model.phase == .ready }
            model.expandedGroups = Set(SystemDataGroup.allCases)
            try? await Task.sleep(for: .milliseconds(400))

            model.toggleSafe()
            let selected = model.selectedItems
            checks["selectedOnlySafe"] = !selected.isEmpty && selected.allSatisfy { $0.safety == .safe }
            model.requestRemoval()
            checks["previewShown"] = await wait { model.pendingPreview != nil }
            checks["confirmationIsInlineNotASeparateWindow"] = window.attachedSheet == nil
            try? await Task.sleep(for: .milliseconds(500))
            snapshot(window.contentView, to: output.appending(path: dark ? "confirm-dark.png" : "confirm.png"))
            let preview = model.pendingPreview
            checks["previewVerbatim"] = preview?.lines.contains { $0.operations.contains { $0.hasPrefix("rm -rf -- ") && $0.contains(home.path) } } == true

            // Permanent deletion: Return must cancel (the safe default); only ⌘⌫ deletes.
            Self.press("\r", keyCode: 36, in: window)
            try? await Task.sleep(for: .milliseconds(500))
            checks["returnCancelsAPermanentDelete"] = model.pendingPreview == nil
                && FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches/Homebrew/downloads/pkg.tar").path)
            model.requestRemoval()
            checks["previewReopens"] = await wait { model.pendingPreview != nil }
            try? await Task.sleep(for: .milliseconds(400))
            // Real keyboard events through the window server, aimed at this process only (`postToPid`), so no other app can
            // ever receive them. They need the Post Event privilege; if macOS withholds it the result stays "unavailable".
            func realKey(_ code: CGKeyCode, command: Bool = false) -> Bool {
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return false }
                if command { down.flags = .maskCommand; up.flags = .maskCommand }
                down.postToPid(getpid()); up.postToPid(getpid())
                return true
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            // 1) a real Return must cancel a permanent delete
            _ = realKey(36)
            _ = await wait { model.pendingPreview == nil }
            let realReturnWorked = model.pendingPreview == nil
            details["realReturnCancelled"] = realReturnWorked
                && FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches/Homebrew/downloads/pkg.tar").path)
            // 2) a real ⌘⌫ must delete
            model.requestRemoval()
            _ = await wait { model.pendingPreview != nil }
            try? await Task.sleep(for: .milliseconds(500))
            _ = realKey(51, command: true)
            _ = await wait { model.pendingPreview == nil && model.statusMessage != nil }
            let realDeleteWorked = !FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches/Homebrew/downloads").path)
            details["realCommandDeleteDeleted"] = realDeleteWorked
            // If the window server did not deliver the events at all, say so instead of claiming a result.
            details["realKeysDelivered"] = realReturnWorked
            if realReturnWorked { checks["realReturnKeyCancelsPermanentDelete"] = details["realReturnCancelled"] as? Bool ?? false
                                  checks["realCommandDeleteKeyDeletes"] = realDeleteWorked }
            if !realDeleteWorked, model.pendingPreview == nil { model.requestRemoval(); _ = await wait { model.pendingPreview != nil } }

            // If the window server did not deliver the real keys, finish the removal directly so later checks still run.
            if model.pendingPreview != nil { await model.confirmRemoval() }
            _ = await wait { model.pendingPreview == nil && model.statusMessage != nil }
            details0 = details
            let fm = FileManager.default
            checks["homebrewContentsGone"] = !fm.fileExists(atPath: home.appending(path: "Library/Caches/Homebrew/downloads").path)
            checks["derivedDataContentsGone"] = !fm.fileExists(atPath: home.appending(path: "Library/Developer/Xcode/DerivedData/App-abc").path)
            checks["folderKept"] = fm.fileExists(atPath: home.appending(path: "Library/Developer/Xcode/DerivedData").path)
            checks["reviewItemsUntouched"] = fm.fileExists(atPath: home.appending(path: ".cargo/registry/cache/crate.bin").path)
                && fm.fileExists(atPath: home.appending(path: "Projects/web/node_modules/dep/index.js").path)
                && fm.fileExists(atPath: home.appending(path: "Library/Containers/com.gone.app/Data/blob.bin").path)
            checks["systemFixtureReportsDeleted"] = !fm.fileExists(atPath: root.appending(path: "system/Library/Logs/DiagnosticReports/crash.ips").path)
            checks["nothingOutsideFixtureListed"] = model.items.allSatisfy { $0.paths.allSatisfy { $0.hasPrefix(root.path + "/") } }
            checks["statusShown"] = model.statusMessage != nil && model.errorMessage == nil
            checks["historyRecorded"] = await !store.load().deletions.isEmpty
            try? await Task.sleep(for: .milliseconds(400))
            snapshot(window.contentView, to: output.appending(path: dark ? "after-dark.png" : "after.png"))

            // Archive the project's node_modules instead of deleting it, then restore it.
            let nodeModules = home.appending(path: "Projects/web/node_modules")
            if let projectItem = model.items.first(where: { $0.group == .projects }) {
                // Shrink in place first: transparent compression, nothing deleted, every path keeps working.
                let dependency = nodeModules.appending(path: "dep/index.js")
                var info = stat()
                let blocksBefore: Int64 = lstat(dependency.path, &info) == 0 ? Int64(info.st_blocks) : -1
                checks["projectItemIsShrinkable"] = projectItem.isShrinkable
                await model.shrink([projectItem])
                let compressed = lstat(dependency.path, &info) == 0 && info.st_flags & UInt32(UF_COMPRESSED) != 0
                checks["shrinkCompressedInPlace"] = compressed && Int64(info.st_blocks) < blocksBefore / 2
                checks["shrinkKeptContent"] = (try? Data(contentsOf: dependency).count) == 25_000_000
                checks["shrinkReportedSaving"] = model.statusMessage != nil && model.errorMessage == nil
                checks["shrinkLeftNoCopies"] = ((try? fm.contentsOfDirectory(atPath: nodeModules.deletingLastPathComponent().path)) ?? []).allSatisfy { !$0.contains(".shrinking-") }
                checks["projectItemIsArchivable"] = projectItem.isArchivable
                await model.archive([projectItem])
                checks["archiveCreated"] = model.archives.count == 1 && fm.fileExists(atPath: model.archives[0].archivePath)
                checks["archivedFolderRemoved"] = !fm.fileExists(atPath: nodeModules.path)
                checks["sourceFilesUntouched"] = fm.fileExists(atPath: home.appending(path: "Projects/web/package.json").path)
                model.tab = .projects
                try? await Task.sleep(for: .milliseconds(500))
                snapshot(window.contentView, to: output.appending(path: dark ? "archives-dark.png" : "archives.png"))
                if let record = model.archives.first {
                    await model.restore(record)
                    checks["restoredFolder"] = fm.fileExists(atPath: nodeModules.appending(path: "dep/index.js").path)
                    checks["archiveConsumed"] = model.archives.isEmpty && !fm.fileExists(atPath: record.archivePath)
                }
            } else {
                checks["projectItemIsArchivable"] = false
            }
            window.close()
        } catch {
            checks["error: \(error.localizedDescription)"] = false
        }
        let report: [String: Any] = ["checks": checks, "details": details0, "language": Bundle.main.preferredLocalizations.first ?? "unknown", "dark": dark]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appending(path: dark ? "report-dark.json" : "report.json"), options: .atomic)
        }
    }
}
#endif

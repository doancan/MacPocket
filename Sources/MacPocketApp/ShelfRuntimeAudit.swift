#if DEBUG
import AppKit
import MacPocketCore

/// Runs only in the isolated audit bundle. Fixtures and private pasteboards never touch user files or
/// clipboard.
@MainActor
enum ShelfRuntimeAudit {
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested, let directory = ModuleRuntimeAudit.dataURL("shelf-fixtures") else { return [:] }
        let runtime = PocketModuleRuntime.shared
        let shelf = ShelfService.shared
        var checks: [String: Bool] = [:]
        runtime.setAvailable(.shelf, true)
        let deadline = Date().addingTimeInterval(5)
        while shelf.loading && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        shelf.selection = Set(shelf.rows.map(\.id))
        shelf.removeSelection()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("Örnek belgesi — example document with a long name.txt")
            let other = directory.appendingPathComponent("Second document.txt")
            try Data("MacPocket shelf fixture".utf8).write(to: file)
            try Data("Second fixture".utf8).write(to: other)
            pasteboard.writeObjects([file as NSURL, other as NSURL])
            checks["shelfAcceptsNativeFiles"] = shelf.accept(pasteboard) && shelf.rows.count == 2
            guard shelf.rows.count == 2 else { throw CocoaError(.fileReadUnknown) }
            shelf.addFiles([file])
            checks["shelfDeduplicatesFiles"] = shelf.rows.count == 2
            shelf.selection = Set(shelf.rows.map(\.id))
            shelf.copySelection(to: pasteboard)
            let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            checks["shelfCopiesMultipleNativeFiles"] = copied?.count == 2
            shelf.show()
            // NSHostingView's first table/update is asynchronous; test readiness rather than a fixed frame
            // budget.
            let initialTable = await waitForTable(shelf, rows: 2)
            checks["shelfUsesNativeMultiselectTable"] = initialTable?.allowsMultipleSelection == true
            checks["shelfFileDragWriters"] = initialTable.map { table in
                let delegate = table.dataSource
                return delegate?.tableView?(table, pasteboardWriterForRow: 0) is NSURL && delegate?.tableView?(table, pasteboardWriterForRow: 1) is NSURL
            } ?? false
            let readiness: [String: Any] = ["visible": shelf.diagnosticWindow?.isVisible == true,
                "keyWindow": shelf.diagnosticWindow?.isKeyWindow == true, "appActive": NSApp.isActive,
                "tableCreated": initialTable != nil, "tableRows": initialTable?.numberOfRows ?? -1]
            if let data = try? JSONSerialization.data(withJSONObject: readiness, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination.appendingPathExtension("shelf-readiness.json"))
            }
            shelf.selection = Set(shelf.rows.map(\.id))
            shelf.previewSelection()
            try? await Task.sleep(for: .milliseconds(600))
            checks["shelfOwnsQuickLookView"] = shelf.diagnosticPreviewOwned
            if let previewWindow = shelf.diagnosticPreviewWindow {
                button(previewWindow.contentView, title: String(localized: "Sonraki"))?.performClick(nil)
                checks["shelfPreviewNext"] = shelf.diagnosticPreviewURL?.lastPathComponent == other.lastPathComponent
                button(previewWindow.contentView, title: String(localized: "Önceki"))?.performClick(nil)
                checks["shelfPreviewPrevious"] = shelf.diagnosticPreviewURL?.lastPathComponent == file.lastPathComponent
                await sendKey(53, to: previewWindow)
                checks["shelfPreviewEscape"] = !shelf.diagnosticPreviewOwned
            }
            shelf.close()
            checks["shelfQuickLookClosesWithShelf"] = !shelf.diagnosticPreviewOwned
            shelf.show()
            pasteboard.clearContents()
            pasteboard.setString("Merhaba 👋\nSecond line", forType: .string)
            checks["shelfAcceptsUnicodeText"] = shelf.accept(pasteboard)
            pasteboard.clearContents()
            pasteboard.setString("https://example.com/a?x=1", forType: .string)
            checks["shelfAcceptsLinks"] = shelf.accept(pasteboard) && shelf.rows.last?.symbol == "link"
            let longText = String(repeating: "A long shelf text with spaces. ", count: 30)
            shelf.add([.text(longText)])
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.bitmapData?.initialize(repeating: 180, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            pasteboard.clearContents()
            pasteboard.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png)
            let imageAccepted = shelf.accept(pasteboard)
            let imageDeadline = Date().addingTimeInterval(5)
            while shelf.preparing > 0 && Date() < imageDeadline { try? await Task.sleep(for: .milliseconds(20)) }
            checks["shelfAcceptsImage"] = imageAccepted && shelf.preparing == 0 && shelf.rows.last?.url?.pathExtension == "png"
            shelf.selection = Set(shelf.rows.map(\.id))
            shelf.copySelection(to: pasteboard)
            checks["shelfCopiesMixedSelectionAsText"] = pasteboard.string(forType: .string)?.contains("Merhaba 👋") == true
            if let first = shelf.rows.first { shelf.selection = [first.id]; shelf.togglePins() }
            try? await Task.sleep(for: .milliseconds(300))
            if let window = shelf.diagnosticWindow {
                window.setContentSize(NSSize(width: 600, height: 430))
                try? await Task.sleep(for: .milliseconds(200))
                await snapshot(window, to: destination.appendingPathExtension("shelf.png"))
                checks["shelfKeyboardFocus"] = window.firstResponder is NSTableView
                let nodes = ToolUIAudit.accessibilityNodes(window)
                checks["shelfHasAccessibleControls"] = nodes.contains { $0["name"] == String(localized: "Dosya Ekle…") }
            }
            let count = shelf.rows.count
            runtime.setAvailable(.shelf, false)
            shelf.diagnosticForgetMemory()
            runtime.setAvailable(.shelf, true)
            let reloadDeadline = Date().addingTimeInterval(5)
            while shelf.loading && Date() < reloadDeadline { try? await Task.sleep(for: .milliseconds(50)) }
            checks["shelfRestoresSavedItemsAndPins"] = shelf.rows.count == count && shelf.rows.filter(\.pinned).count == 1
            shelf.show()
            try? await Task.sleep(for: .milliseconds(200))
            if let window = shelf.diagnosticWindow, let table = table(window.contentView) {
                window.makeFirstResponder(table)
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                let beforeArrow: [String: Any] = ["keyWindow": window.isKeyWindow, "appActive": NSApp.isActive,
                    "tableFocused": window.firstResponder === table, "selectedRow": table.selectedRow, "rowCount": table.numberOfRows]
                await sendKey(125, to: window)
                checks["shelfDownArrowChangesSelection"] = table.selectedRow == 1
                let keyboardReport: [String: Any] = ["beforeArrow": beforeArrow, "afterArrowRow": table.selectedRow,
                    "afterArrowKeyWindow": window.isKeyWindow, "afterArrowTableFocused": window.firstResponder === table]
                if let data = try? JSONSerialization.data(withJSONObject: keyboardReport, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: destination.appendingPathExtension("shelf-keyboard.json"))
                }
                await sendKey(51, to: window)
                checks["shelfDeleteRemovesReference"] = shelf.rows.count == count - 1
                await sendKey(53, to: window)
                checks["shelfEscapeClosesPanel"] = !window.isVisible
            }
            shelf.clearUnpinned()
            checks["shelfClearPreservesPins"] = shelf.rows.count == 1 && shelf.rows[0].pinned
            let missing = directory.appendingPathComponent("Unavailable fixture.txt")
            try Data("temporary fixture".utf8).write(to: missing)
            shelf.addFiles([missing])
            try FileManager.default.removeItem(at: missing)
            shelf.refreshRows()
            checks["shelfShowsUnavailableFile"] = shelf.selectedRows.first?.unavailable == true
            pasteboard.clearContents()
            pasteboard.setString("clipboard sentinel", forType: .string)
            shelf.copySelection(to: pasteboard)
            checks["shelfFailedCopyPreservesClipboard"] = pasteboard.string(forType: .string) == "clipboard sentinel"
            shelf.removeSelection()
            checks["shelfNeverDeletesSourceFiles"] = (try? String(contentsOf: file, encoding: .utf8)) == "MacPocket shelf fixture"
                && (try? String(contentsOf: other, encoding: .utf8)) == "Second fixture"
            shelf.show()
            try? await Task.sleep(for: .milliseconds(200))
            shelf.selection = Set(shelf.rows.map(\.id))
            shelf.removeSelection()
            let countBeforeCancellation = shelf.rows.count
            pasteboard.clearContents()
            pasteboard.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png)
            _ = shelf.accept(pasteboard)
            shelf.cancelPreparation()
            try? await Task.sleep(for: .milliseconds(200))
            checks["shelfCancelsImagePreparation"] = shelf.rows.count == countBeforeCancellation && shelf.preparing == 0 && shelf.moduleDiagnosticResources["images"] == 0
            try? await Task.sleep(for: .milliseconds(200))
            if let window = shelf.diagnosticWindow { await snapshot(window, to: destination.appendingPathExtension("shelf-empty.png")) }
            shelf.shakeToOpen = true
            checks["shelfOptionalMouseMonitorStarts"] = shelf.moduleDiagnosticResources["mouseMonitor"] == 1
            runtime.setAvailable(.shelf, false)
            checks["shelfStopsEveryResource"] = shelf.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
            shelf.shakeToOpen = false
        } catch { checks["shelfFixturesSucceeded"] = false }
        return checks
    }

    private static func table(_ view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { table($0) }.first
    }
    private static func waitForTable(_ shelf: ShelfService, rows: Int) async -> NSTableView? {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        repeat {
            if let window = shelf.diagnosticWindow, window.isVisible,
               let table = table(window.contentView), table.window === window, table.numberOfRows >= rows { return table }
            try? await Task.sleep(for: .milliseconds(20))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }
    private static func button(_ view: NSView?, title: String) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title { return button }
        return view.subviews.lazy.compactMap { button($0, title: title) }.first
    }
    private static func sendKey(_ code: UInt16, to window: NSWindow) async {
        // NSTableView's native key binding interpreter consumes function-key characters, not keyCode alone.
        let characters: String
        switch code {
        case 126: characters = "\u{F700}"
        case 125: characters = "\u{F701}"
        case 123: characters = "\u{F702}"
        case 124: characters = "\u{F703}"
        case 51: characters = "\u{7F}"
        case 53: characters = "\u{1B}"
        default: characters = ""
        }
        let flags: NSEvent.ModifierFlags = (123...126).contains(code) ? [.function, .numericPad] : []
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
            NSApp.sendEvent(event)
        }
        try? await Task.sleep(for: .milliseconds(150))
    }
    private static func snapshot(_ window: NSWindow, to url: URL) async {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        if CommandLine.arguments.contains("--audit-shelf-capture") {
            try? String(window.windowNumber).write(to: url.appendingPathExtension("window-id"), atomically: true, encoding: .utf8)
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
#endif

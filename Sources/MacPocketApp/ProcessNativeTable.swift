import AppKit
import MacPocketCore
import SwiftUI

/// AppKit provides virtualized rows and native column resizing for large process lists.
struct ProcessNativeTable: NSViewRepresentable {
    let entries: [ProcessEntry]
    @Binding var selection: Int32?
    let showUser: Bool
    let showThreads: Bool
    let sort: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = NSTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.rowHeight = 29
        table.usesAlternatingRowBackgroundColors = true
        table.backgroundColor = NSColor.textBackgroundColor
        table.gridColor = NSColor.separatorColor
        table.gridStyleMask = .solidVerticalGridLineMask
        table.allowsColumnReordering = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autosaveName = "MacPocket.ProcessTable"
        table.autosaveTableColumns = true
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        let entriesChanged = coordinator.parent.entries != entries
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        let columns: [(String, String, CGFloat)] = [
            ("name", "Süreç", 190), ("pid", "PID", 58),
        ] + (showUser ? [("user", "Kullanıcı", 90)] : []) + [
            ("state", "Durum", 85), ("cpu", "CPU %", 75), ("memory", "Bellek · RSS", 100),
        ] + (showThreads ? [("threads", "İş parç.", 60)] : [])
        let columnsChanged = Set(table.tableColumns.map { $0.identifier.rawValue }) != Set(columns.map { $0.0 })
        if columnsChanged {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for (key, title, width) in columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
                column.title = title
                column.width = width
                column.minWidth = key == "name" ? 120 : 45
                if key != "threads" {
                    column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: key == "name")
                }
                table.addTableColumn(column)
            }
        }
        if entriesChanged || columnsChanged { table.reloadData() }
        if let selection, let row = entries.firstIndex(where: { $0.pid == selection }) {
            if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        } else if table.selectedRow != -1 { table.deselectAll(nil) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ProcessNativeTable
        var updating = false
        init(_ parent: ProcessNativeTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.entries.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.entries.indices.contains(row), let key = tableColumn?.identifier.rawValue else { return nil }
            let entry = parent.entries[row]
            let id = NSUserInterfaceItemIdentifier("cell-" + key)
            let label = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? NSTextField(labelWithString: "")
            label.identifier = id
            label.font = key == "pid" || key == "threads" ? .monospacedSystemFont(ofSize: 10, weight: .regular) : .systemFont(ofSize: 11)
            label.lineBreakMode = .byTruncatingTail
            label.textColor = .secondaryLabelColor
            label.drawsBackground = false
            label.alignment = ["pid", "cpu", "memory", "threads"].contains(key) ? .right : .left
            switch key {
            case "name": label.stringValue = entry.name; label.textColor = .labelColor
            case "pid": label.stringValue = String(entry.pid)
            case "user": label.stringValue = entry.user
            case "state": label.stringValue = entry.canTerminate ? entry.state : "Korunuyor"
            case "cpu":
                label.stringValue = entry.cpuSampleAvailable ? String(format: "%.1f%%", entry.cpuPercent) : "—"
                if entry.cpuSampleAvailable && entry.cpuPercent > 1 {
                    label.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15); label.drawsBackground = true
                }
            case "memory":
                label.stringValue = entry.memorySampleAvailable ? pocketBytes(entry.residentBytes) : "—"
                if entry.residentBytes > UInt64(536_870_912) {
                    label.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.15); label.drawsBackground = true
                }
            case "threads": label.stringValue = entry.threadCount.map { String($0) } ?? "—"
            default: label.stringValue = "—"
            }
            return label
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            let row = table.selectedRow
            let pid = parent.entries.indices.contains(row) ? parent.entries[row].pid : nil
            parent.selection = pid
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            parent.sort(key, descriptor.ascending)
        }
    }
}

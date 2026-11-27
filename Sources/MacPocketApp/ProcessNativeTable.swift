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
        table.style = .inset
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel(String(localized: "Süreç listesi"))
        table.allowsColumnReordering = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
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
        let previous = coordinator.parent.entries
        let entriesChanged = previous != entries
        // Same processes in the same order (the common case between samples): refresh only the
        // visible rows instead of reloading and re-laying out the whole table.
        let sameRows = entriesChanged && previous.count == entries.count
            && zip(previous, entries).allSatisfy { $0.identity == $1.identity }
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        let columns: [(String, String, CGFloat)] = [
            ("name", String(localized: "Süreç"), 190), ("pid", "PID", 58),
        ] + (showUser ? [("user", String(localized: "Kullanıcı"), 90)] : []) + [
            ("state", String(localized: "Durum"), 85), ("cpu", String(localized: "CPU %"), 75),
            ("memory", String(localized: "Bellek · RSS"), 100),
        ] + (showThreads ? [("threads", String(localized: "İş parç."), 60)] : [])
        let columnsChanged = Set(table.tableColumns.map { $0.identifier.rawValue }) != Set(columns.map { $0.0 })
        if columnsChanged {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for (key, title, width) in columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
                column.title = title
                column.width = width
                column.minWidth = key == "name" ? 120 : 45
                // Extra width goes to the name column; number headers line up with their right-aligned
                // values.
                column.resizingMask = key == "name" ? [.autoresizingMask, .userResizingMask] : .userResizingMask
                if ["pid", "cpu", "memory", "threads"].contains(key) { column.headerCell.alignment = .right }
                column.headerToolTip = key == "cpu" ? String(localized: "Tek mantıksal çekirdeğe göre")
                    : key == "memory" ? String(localized: "Yerleşik bellek (RSS)") : nil
                if key != "threads" {
                    column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: key == "name")
                }
                table.addTableColumn(column)
            }
        }
        if columnsChanged || (entriesChanged && !sameRows) {
            table.reloadData()
        } else if sameRows {
            let visible = table.rows(in: table.visibleRect)
            if visible.length > 0 {
                table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)),
                                 columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
            }
        }
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
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? Self.makeCell(id)
            guard let label = cell.textField else { return cell }
            let numeric = ["pid", "cpu", "memory", "threads"].contains(key)
            label.font = numeric ? Self.numberFont : Self.textFont
            label.alignment = numeric ? .right : .left
            label.textColor = .secondaryLabelColor
            label.drawsBackground = false
            switch key {
            case "name": label.stringValue = entry.name
            label.textColor = .labelColor
            case "pid": label.stringValue = String(entry.pid)
            case "user": label.stringValue = entry.user
            case "state": label.stringValue = entry.canTerminate ? pocketProcessStateTitle(entry.state) : String(localized: "Korunuyor")
            case "cpu":
                label.stringValue = entry.cpuSampleAvailable ? pocketProcessCPU(entry.cpuPercent) : "—"
                if entry.cpuSampleAvailable && entry.cpuPercent > 1 {
                    label.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
                    label.drawsBackground = true
                }
            case "memory":
                label.stringValue = entry.memorySampleAvailable ? pocketBytes(entry.residentBytes) : "—"
                if entry.residentBytes > UInt64(536_870_912) {
                    label.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.15)
                    label.drawsBackground = true
                }
            case "threads": label.stringValue = entry.threadCount.map { String($0) } ?? "—"
            default: label.stringValue = "—"
            }
            return cell
        }

        private static let textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        /// Cell view with a vertically centered, truncating label.
        private static func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
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

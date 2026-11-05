import AppKit
import Carbon.HIToolbox
import TapAskCore

@MainActor
final class ProviderOrderWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private static let dragType = NSPasteboard.PasteboardType("io.github.sure-will.tap-ask.provider-order")
    private let tableView = ProviderOrderTableView()
    private var providers: [Provider]
    var onOrderChange: (([String]?) -> Void)?

    init(providers: [Provider]) {
        self.providers = providers
        let tableHeight = CGFloat(providers.count) * 36 + 2
        let window = ProviderOrderWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: tableHeight + 68),
                                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "服务商排序"
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView()
        window.contentView = content
        tableView.style = .plain
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 36
        tableView.intercellSpacing = .zero
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.setAccessibilityLabel("服务商顺序")
        tableView.toolTip = "拖动排序，或选中后按 ⌥↑ / ⌥↓"
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("provider"))
        column.width = 274
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask([], forLocal: false)
        tableView.onMove = { [weak self] offset in self?.moveSelectedRow(by: offset) }

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        let reset = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefault(_:)))
        reset.bezelStyle = .rounded
        reset.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(reset)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.heightAnchor.constraint(equalToConstant: tableHeight),
            reset.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            reset.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            reset.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(tableView)
    }

    func update(providers: [Provider]) {
        let selectedID = self.providers.indices.contains(tableView.selectedRow)
            ? self.providers[tableView.selectedRow].id : nil
        self.providers = providers
        tableView.reloadData()
        if let row = providers.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { providers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("provider-order-row")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ProviderOrderCellView
            ?? ProviderOrderCellView()
        cell.identifier = identifier
        cell.nameLabel.stringValue = providers[row].name
        cell.shortcutLabel.stringValue = row < 9 ? "⌘\(row + 1)" : ""
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(providers[row].id, forType: Self.dragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        draggedRow(from: info, row: row, operation: operation) == nil ? [] : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo,
                   row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard let source = draggedRow(from: info, row: row, operation: operation) else { return false }
        tableView.selectRowIndexes(IndexSet(integer: source), byExtendingSelection: false)
        onOrderChange?(ProviderOrder.moving(providers.map(\.id), from: source, to: row))
        return true
    }

    private func draggedRow(from info: any NSDraggingInfo, row: Int,
                            operation: NSTableView.DropOperation) -> Int? {
        guard operation == .above, (0...providers.count).contains(row),
              (info.draggingSource as? NSTableView) === tableView,
              let id = info.draggingPasteboard.string(forType: Self.dragType) else { return nil }
        return providers.firstIndex { $0.id == id }
    }

    private func moveSelectedRow(by offset: Int) {
        let source = tableView.selectedRow
        let destination = source + offset
        guard providers.indices.contains(source), providers.indices.contains(destination) else { return }
        let insertionRow = destination > source ? destination + 1 : destination
        onOrderChange?(ProviderOrder.moving(providers.map(\.id), from: source, to: insertionRow))
    }

    @objc private func restoreDefault(_ sender: Any?) { onOrderChange?(nil) }
}

@MainActor
private final class ProviderOrderTableView: NSTableView {
    var onMove: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .option {
            switch Int(event.keyCode) {
            case kVK_UpArrow: onMove?(-1); return
            case kVK_DownArrow: onMove?(1); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
}

/// Only this ordinary window handles ⌘W; the chat and login panels keep their own close rules.
@MainActor
private final class ProviderOrderWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class ProviderOrderCellView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let shortcutLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        let handle = NSImageView()
        handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")
        handle.contentTintColor = .secondaryLabelColor
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        textField = nameLabel
        for view in [handle, shortcutLabel, nameLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            handle.widthAnchor.constraint(equalToConstant: 14),
            handle.heightAnchor.constraint(equalToConstant: 14),
            shortcutLabel.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 10),
            shortcutLabel.widthAnchor.constraint(equalToConstant: 30),
            nameLabel.leadingAnchor.constraint(equalTo: shortcutLabel.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

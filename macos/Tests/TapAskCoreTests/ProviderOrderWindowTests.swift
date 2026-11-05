import AppKit
import Carbon.HIToolbox
import TapAskCore
import XCTest
@testable import TapAsk

/// Requires WindowServer, but creates no WebView and does not change app preferences.
final class ProviderOrderWindowTests: XCTestCase {
    @MainActor
    func testAllRowsFitAboveThePanelAndTheWindowCanCloseAndReopen() throws {
        _ = NSApplication.shared
        let providers = try SharedFixtures.catalog().providers
        let controller = ProviderOrderWindowController(providers: providers)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let table = try table(in: window)
        XCTAssertEqual(window.title, "服务商排序")
        XCTAssertEqual(content.frame.width, 300, accuracy: 1)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertEqual(table.numberOfRows, 6)
        XCTAssertGreaterThan(table.frame.width, 0)
        XCTAssertTrue(table.visibleRect.contains(table.rect(ofRow: 5)), "All six rows must fit without scrolling")
        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(kVK_ANSI_W, characters: "w", flags: .command)))
        XCTAssertFalse(window.isVisible)
        controller.present()
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testOptionArrowsMoveTheSelectedProviderAndRefreshNumbering() throws {
        _ = NSApplication.shared
        let providers = try SharedFixtures.catalog().providers
        let controller = ProviderOrderWindowController(providers: providers)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let table = try table(in: window)
        var savedOrders: [[String]] = []
        controller.onOrderChange = { [weak controller] ids in
            guard let ids else { return XCTFail("Moving must save an explicit order") }
            savedOrders.append(ids)
            controller?.update(providers: ProviderOrder.ordered(providers, savedIDs: ids))
        }
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        let down = try keyEvent(kVK_DownArrow, characters: "\u{F701}", flags: .option)
        let up = try keyEvent(kVK_UpArrow, characters: "\u{F700}", flags: .option)
        table.keyDown(with: down)
        XCTAssertEqual(savedOrders.last, ["chatgpt", "claude", "gemini", "deepseek", "doubao", "grok"])
        XCTAssertEqual(table.selectedRow, 5)
        let cell = try XCTUnwrap(table.delegate?.tableView?(table, viewFor: table.tableColumns[0], row: 5)
            as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "Grok")
        XCTAssertTrue(cell.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "⌘6" })
        table.keyDown(with: down)
        XCTAssertEqual(savedOrders.count, 1, "Moving past the last row must not write preferences")
        table.keyDown(with: up)
        XCTAssertEqual(savedOrders.last, providers.map(\.id))
        XCTAssertEqual(table.selectedRow, 4)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.keyDown(with: up)
        XCTAssertEqual(savedOrders.count, 2, "Moving above the first row must not write preferences")
    }

    @MainActor
    func testRestoreDefaultRequestsRemovalOfSavedOrderAndKeepsSelectionByID() throws {
        _ = NSApplication.shared
        let providers = try SharedFixtures.catalog().providers
        let controller = ProviderOrderWindowController(providers: ProviderOrder.ordered(providers, savedIDs: ["doubao"]))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let table = try table(in: window)
        var resetCount = 0
        controller.onOrderChange = { [weak controller] ids in
            XCTAssertNil(ids, "Restore default must remove the preference instead of saving today's catalog")
            resetCount += 1
            controller?.update(providers: ProviderOrder.ordered(providers, savedIDs: ids))
        }
        let button = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }
            .first { $0.title == "恢复默认" })
        button.performClick(nil)
        XCTAssertEqual(resetCount, 1)
        XCTAssertEqual(table.selectedRow, 5, "豆包 should stay selected after resetting the order")
    }

    @MainActor
    private func table(in window: NSWindow) throws -> NSTableView {
        let scrollView = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        return try XCTUnwrap(scrollView.documentView as? NSTableView)
    }

    @MainActor
    private func keyEvent(_ code: Int, characters: String, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                       windowNumber: 0, context: nil, characters: characters,
                                       charactersIgnoringModifiers: characters, isARepeat: false,
                                       keyCode: UInt16(code)))
    }
}

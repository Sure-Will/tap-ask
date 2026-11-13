import AppKit
import Carbon.HIToolbox
import TapAskCore
import XCTest
@testable import TapAsk

final class SettingsPopoverTests: XCTestCase {
    @MainActor
    func testPopoverRestoresShortcutWhenClosed() throws {
        _ = NSApplication.shared
        let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let button = NSButton(frame: NSRect(x: 20, y: 20, width: 60, height: 30))
        host.contentView?.addSubview(button)
        host.makeKeyAndOrderFront(nil)
        let shortcut = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let shortcutWindow = try XCTUnwrap(shortcut.window)
        let content = try XCTUnwrap(shortcutWindow.contentView)
        let recorder = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip != nil })
        let order = ProviderOrderWindowController(providers: try SharedFixtures.catalog().providers)
        let orderWindow = try XCTUnwrap(order.window)
        let settings = SettingsPopoverController(shortcutController: shortcut, orderController: order)
        var changes: [Bool] = []
        shortcut.onRecordingChange = { changes.append($0) }
        settings.show(.shortcut, relativeTo: button, shortcut: .defaultShortcut)
        XCTAssertTrue(settings.isShown)
        XCTAssertFalse(shortcutWindow.isVisible)
        XCTAssertFalse(orderWindow.isVisible)
        XCTAssertTrue(recorder.window?.firstResponder === recorder)
        content.layoutSubtreeIfNeeded()
        for view in content.subviews {
            XCTAssertTrue(content.bounds.contains(view.frame), "Control must fit the popover: \(view)")
            XCTAssertFalse(view.hasAmbiguousLayout)
        }
        recorder.performClick(nil)
        XCTAssertEqual(changes, [true])
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control,
            timestamp: 0, windowNumber: try XCTUnwrap(recorder.window).windowNumber, context: nil,
            characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: UInt16(kVK_ANSI_K)))
        NSApp.sendEvent(event)
        XCTAssertEqual(changes, [true, false])
        recorder.performClick(nil)
        let close = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: try XCTUnwrap(recorder.window).windowNumber, context: nil,
            characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: UInt16(kVK_ANSI_W)))
        NSApp.sendEvent(close)
        XCTAssertTrue(settings.isShown, "Reserved shortcuts must be captured during recording")
        settings.close()
        XCTAssertFalse(settings.isShown)
        XCTAssertEqual(changes, [true, false, true, false])
        XCTAssertFalse(shortcut.isOpen)
    }

    @MainActor
    func testOrderPopoverKeepsTableKeyboardInteraction() throws {
        _ = NSApplication.shared
        let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let button = NSButton(frame: NSRect(x: 20, y: 20, width: 60, height: 30))
        host.contentView?.addSubview(button)
        host.makeKeyAndOrderFront(nil)
        let providers = try SharedFixtures.catalog().providers
        let order = ProviderOrderWindowController(providers: providers)
        let orderWindow = try XCTUnwrap(order.window)
        let content = try XCTUnwrap(orderWindow.contentView)
        let scrollView = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
        let table = try XCTUnwrap(scrollView.documentView as? NSTableView)
        let shortcut = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let settings = SettingsPopoverController(shortcutController: shortcut, orderController: order)
        var changed: [String]?
        order.onOrderChange = { changed = $0 }
        settings.show(.providerOrder, relativeTo: button, shortcut: .defaultShortcut)
        XCTAssertTrue(settings.isShown)
        XCTAssertFalse(orderWindow.isVisible)
        XCTAssertTrue(table.window?.firstResponder === table)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option,
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: UInt16(kVK_DownArrow)))
        table.keyDown(with: event)
        XCTAssertEqual(changed, ["claude", "chatgpt", "gemini", "deepseek", "grok", "doubao"])
        let close = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: try XCTUnwrap(table.window).windowNumber, context: nil,
            characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: UInt16(kVK_ANSI_W)))
        NSApp.sendEvent(close)
        XCTAssertFalse(settings.isShown)
    }
}

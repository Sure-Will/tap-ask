import AppKit
import Carbon.HIToolbox
import TapAskCore
import XCTest
@testable import TapAsk

/// Requires WindowServer, but does not register a global shortcut or change preferences.
final class ShortcutSettingsWindowTests: XCTestCase {
    @MainActor
    func testApplicationDispatchCannotRunMainMenuCommandWhileRecording() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        let target = ShortcutMenuTarget()
        let main = NSMenu()
        let submenu = NSMenu()
        let item = submenu.addItem(withTitle: "Test Quit", action: #selector(ShortcutMenuTarget.performAction(_:)), keyEquivalent: "q")
        item.target = target
        let root = NSMenuItem()
        root.submenu = submenu
        main.addItem(root)
        app.mainMenu = main
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); app.mainMenu = previousMenu }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: UInt16(kVK_ANSI_Q)))
        app.sendEvent(event)
        XCTAssertEqual(target.actionCount, 0)
        XCTAssertEqual(try recorder(in: window).state, .on)
        XCTAssertFalse(try errorLabel(in: window).stringValue.isEmpty)
        window.sendEvent(try key(kVK_Escape, "\u{1b}", []))
        XCTAssertTrue(main.performKeyEquivalent(with: event), "The fixture must actually have a working menu command")
        XCTAssertEqual(target.actionCount, 1)
    }

    @MainActor
    func testRecordingChecksMenuCharactersInTheEventKeyboardLayout() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        window.sendEvent(try key(kVK_ANSI_O, "r", .command))
        XCTAssertEqual(try recorder(in: window).state, .on)
        XCTAssertFalse(try errorLabel(in: window).stringValue.isEmpty)
        window.sendEvent(try key(kVK_ANSI_R, "p", .command))
        XCTAssertEqual(try recorder(in: window).state, .off)
        var saved: GlobalShortcut?
        controller.onSave = { saved = $0 }
        try button("保存", in: window).performClick(nil)
        XCTAssertEqual(saved?.keyCode, UInt16(kVK_ANSI_R))
    }

    @MainActor
    func testNativeControlsFitAndOrdinaryCommandWCloses() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.present(shortcut: .defaultShortcut)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.title, "快捷键设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertTrue(window.titleVisibility == .visible)
        XCTAssertFalse(window.titlebarAppearsTransparent)
        for view in content.subviews {
            XCTAssertTrue(content.bounds.contains(view.frame), "Control must fit: \(view)")
            XCTAssertFalse(view.hasAmbiguousLayout)
        }
        let labels = content.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
        XCTAssertTrue(labels.contains("呼出 / 收起 TapAsk"))
        XCTAssertTrue(labels.contains { $0.contains("⌘") && $0.contains("⌥") && $0.contains("⌃") })
        XCTAssertEqual(try recorder(in: window).title, GlobalShortcut.defaultShortcut.displayString)
        for title in ["恢复默认", "取消", "保存"] { _ = try button(title, in: window) }
        XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_W, "w", .command)))
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testCaptureChangesOnlyDraftUntilSave() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        var changes: [Bool] = []
        var saves: [GlobalShortcut] = []
        controller.onRecordingChange = { changes.append($0) }
        controller.onSave = { saves.append($0) }
        controller.present(shortcut: .defaultShortcut)
        let recorder = try recorder(in: window)
        recorder.performClick(nil)
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(recorder.state, .on)
        window.sendEvent(try key(kVK_ANSI_K, "k", [.control, .shift]))
        let expected = try XCTUnwrap(GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: [.control, .shift]))
        XCTAssertEqual(recorder.title, expected.displayString)
        XCTAssertEqual(recorder.state, .off)
        XCTAssertEqual(changes, [true, false])
        XCTAssertTrue(saves.isEmpty)
        try button("保存", in: window).performClick(nil)
        XCTAssertEqual(saves, [expected])
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testInvalidReservedAndRepeatedKeysStayInRecordingWithoutRunningMenuCommands() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        var changes: [Bool] = []
        controller.onRecordingChange = { changes.append($0) }
        controller.present(shortcut: .defaultShortcut)
        let recorder = try recorder(in: window)
        recorder.performClick(nil)
        window.sendEvent(try key(kVK_ANSI_K, "k", .control, repeated: true))
        window.sendEvent(try key(kVK_Shift, "", .shift))
        XCTAssertEqual(recorder.state, .on)
        XCTAssertEqual(changes, [true])
        for (code, character, flags) in [
            (kVK_ANSI_K, "k", NSEvent.ModifierFlags()),
            (kVK_ANSI_K, "K", .shift),
            (kVK_ANSI_Q, "q", .command),
            (kVK_ANSI_W, "w", .command),
            (kVK_ANSI_1, "1", .command),
            (255, "", .control),
        ] {
            XCTAssertTrue(window.performKeyEquivalent(with: try key(code, character, flags)))
            XCTAssertEqual(recorder.state, .on)
            XCTAssertFalse(try errorLabel(in: window).stringValue.isEmpty)
            XCTAssertTrue(window.isVisible, "Reserved ⌘W must be captured without closing")
        }
        window.sendEvent(try key(kVK_Escape, "\u{1b}", []))
        XCTAssertEqual(recorder.state, .off)
        XCTAssertEqual(recorder.title, GlobalShortcut.defaultShortcut.displayString)
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(try errorLabel(in: window).stringValue, "")
    }

    @MainActor
    func testCancelAndReopenDiscardDraftAndReuseWindow() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        var saves: [GlobalShortcut] = []
        controller.onSave = { saves.append($0) }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        window.sendEvent(try key(kVK_ANSI_K, "k", .control))
        try button("取消", in: window).performClick(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(saves.isEmpty)
        controller.present(shortcut: .defaultShortcut)
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(try recorder(in: window).title, GlobalShortcut.defaultShortcut.displayString)
    }

    @MainActor
    func testRestoreDefaultRequiresSave() throws {
        _ = NSApplication.shared
        let custom = try XCTUnwrap(GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .control))
        let controller = ShortcutSettingsWindowController(shortcut: custom)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        var saves: [GlobalShortcut] = []
        controller.onSave = { saves.append($0) }
        controller.present(shortcut: custom)
        try button("恢复默认", in: window).performClick(nil)
        XCTAssertTrue(saves.isEmpty)
        XCTAssertEqual(try recorder(in: window).title, GlobalShortcut.defaultShortcut.displayString)
        try button("保存", in: window).performClick(nil)
        XCTAssertEqual(saves, [.defaultShortcut])
    }

    @MainActor
    func testSaveFailureKeepsWindowAndDraftForRetry() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let custom = try XCTUnwrap(GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .control))
        controller.onSave = { _ in throw SettingsError(message: "快捷键注册失败") }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        window.sendEvent(try key(kVK_ANSI_K, "k", .control))
        try button("保存", in: window).performClick(nil)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(try recorder(in: window).title, custom.displayString)
        XCTAssertEqual(try errorLabel(in: window).stringValue, "快捷键注册失败")
        var saved: GlobalShortcut?
        controller.onSave = { saved = $0 }
        try button("保存", in: window).performClick(nil)
        XCTAssertEqual(saved, custom)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testCloseCancelAndResignEndRecordingExactlyOnce() throws {
        _ = NSApplication.shared
        for exit in 0..<3 {
            let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
            let window = try XCTUnwrap(controller.window)
            var changes: [Bool] = []
            controller.onRecordingChange = { changes.append($0) }
            controller.present(shortcut: .defaultShortcut)
            try recorder(in: window).performClick(nil)
            switch exit {
            case 0: window.close()
            case 1: try button("取消", in: window).performClick(nil)
            default:
                controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
                XCTAssertEqual(try recorder(in: window).state, .off)
                window.close()
            }
            XCTAssertEqual(changes, [true, false])
            XCTAssertFalse(window.isVisible)
        }
    }

    @MainActor
    func testRegistrationRestoreFailureIsVisibleAndCloseCanRetry() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { controller.onRecordingChange = nil; window.close() }
        var failRestore = true
        var changes: [Bool] = []
        controller.onRecordingChange = { recording in
            changes.append(recording)
            if !recording && failRestore { throw SettingsError(message: "原快捷键恢复失败") }
        }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        window.close()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(try recorder(in: window).state, .off)
        XCTAssertEqual(try errorLabel(in: window).stringValue, "原快捷键恢复失败")
        XCTAssertEqual(changes, [true, false])
        failRestore = false
        window.close()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(changes, [true, false, false])
    }

    @MainActor
    func testRecordingStartFailureLeavesShortcutUnchangedAndShowsError() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        var changes: [Bool] = []
        controller.onRecordingChange = { recording in
            changes.append(recording)
            if recording { throw SettingsError(message: "暂时无法录制快捷键") }
        }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        XCTAssertEqual(try recorder(in: window).state, .off)
        XCTAssertEqual(try recorder(in: window).title, GlobalShortcut.defaultShortcut.displayString)
        XCTAssertEqual(try errorLabel(in: window).stringValue, "暂时无法录制快捷键")
        window.close()
        XCTAssertEqual(changes, [true])
    }

    @MainActor
    func testFailedOldShortcutRestorationStillAllowsRecordingAndSavingReplacement() throws {
        _ = NSApplication.shared
        let controller = ShortcutSettingsWindowController(shortcut: .defaultShortcut)
        let window = try XCTUnwrap(controller.window)
        defer { controller.onRecordingChange = nil; window.close() }
        var changes: [Bool] = []
        controller.onRecordingChange = { recording in
            changes.append(recording)
            if !recording { throw SettingsError(message: "原快捷键恢复失败") }
        }
        var saved: GlobalShortcut?
        controller.onSave = { saved = $0 }
        controller.present(shortcut: .defaultShortcut)
        try recorder(in: window).performClick(nil)
        window.sendEvent(try key(kVK_ANSI_K, "k", .control))
        XCTAssertEqual(try errorLabel(in: window).stringValue, "原快捷键恢复失败")
        XCTAssertTrue(window.isVisible)
        try recorder(in: window).performClick(nil)
        XCTAssertEqual(try recorder(in: window).state, .on)
        window.sendEvent(try key(kVK_ANSI_J, "j", .option))
        let replacement = try XCTUnwrap(GlobalShortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: .option))
        XCTAssertEqual(try recorder(in: window).title, replacement.displayString)
        try button("保存", in: window).performClick(nil)
        XCTAssertEqual(saved, replacement)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(changes, [true, false, false], "Saving must not try restoring the unusable old shortcut again")
    }

    @MainActor
    func testFailedRestorationStillAllowsResettingAndSavingDefault() throws {
        _ = NSApplication.shared
        let custom = try XCTUnwrap(GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .control))
        let controller = ShortcutSettingsWindowController(shortcut: custom)
        let window = try XCTUnwrap(controller.window)
        defer { controller.onRecordingChange = nil; window.close() }
        controller.onRecordingChange = { recording in
            if !recording { throw SettingsError(message: "原快捷键恢复失败") }
        }
        var saved: GlobalShortcut?
        controller.onSave = { saved = $0 }
        controller.present(shortcut: custom)
        try recorder(in: window).performClick(nil)
        try button("恢复默认", in: window).performClick(nil)
        XCTAssertNil(saved)
        XCTAssertEqual(try recorder(in: window).title, GlobalShortcut.defaultShortcut.displayString)
        try button("保存", in: window).performClick(nil)
        XCTAssertEqual(saved, .defaultShortcut)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    private func button(_ title: String, in window: NSWindow) throws -> NSButton {
        try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.title == title })
    }

    @MainActor
    private func recorder(in window: NSWindow) throws -> NSButton {
        try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip != nil })
    }

    @MainActor
    private func errorLabel(in window: NSWindow) throws -> NSTextField {
        try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSTextField }
            .first { $0.textColor == .systemRed })
    }

    @MainActor
    private func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags,
                     repeated: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                       windowNumber: 0, context: nil, characters: characters,
                                       charactersIgnoringModifiers: characters, isARepeat: repeated,
                                       keyCode: UInt16(code)))
    }
}

@MainActor
private final class ShortcutMenuTarget: NSObject {
    var actionCount = 0
    @objc func performAction(_ sender: Any?) { actionCount += 1 }
}

private struct SettingsError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

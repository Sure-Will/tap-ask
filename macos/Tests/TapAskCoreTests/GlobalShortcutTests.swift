import XCTest
import TapAskCore

final class GlobalShortcutTests: XCTestCase {
    func testDefaultAndPersistedShortcutRoundTrip() throws {
        XCTAssertEqual(GlobalShortcut.defaultShortcut.keyCode, 49)
        XCTAssertEqual(GlobalShortcut.defaultShortcut.modifiers, .option)
        let custom = try XCTUnwrap(GlobalShortcut(keyCode: 40, modifiers: [.control, .shift]))
        XCTAssertEqual(GlobalShortcut.restored(from: custom.propertyList), custom)
        XCTAssertEqual(custom.modifiers.symbols, "⌃⇧")
    }

    func testMalformedOrUnusablePreferencesRestoreDefault() {
        let values: [Any?] = [nil, "invalid", [:], ["keyCode": -1, "modifiers": 2],
            ["keyCode": 65_536, "modifiers": 2], ["keyCode": 49, "modifiers": -1],
            ["keyCode": 49, "modifiers": 16], ["keyCode": 49, "modifiers": 0],
            ["keyCode": 49, "modifiers": 4]]
        for value in values { XCTAssertEqual(GlobalShortcut.restored(from: value), .defaultShortcut) }
    }

    func testRequiresPrimaryModifierAndSupportedKeyWithoutTakingAppCommands() throws {
        for flags: ShortcutModifiers in [[], .shift] {
            XCTAssertNil(GlobalShortcut(keyCode: 40, modifiers: flags))
            XCTAssertNotNil(GlobalShortcut.validationMessage(keyCode: 40, modifiers: flags))
        }
        for key in ["a", "z", "x", "c", "v", "q", "w", "r", "1", "2", "3", "4", "5", "6", "7", "8", "9", ","] {
            XCTAssertNotNil(GlobalShortcut.menuConflictMessage(keyEquivalent: key, modifiers: .command))
            XCTAssertNil(GlobalShortcut.menuConflictMessage(keyEquivalent: key, modifiers: [.control, .option]))
        }
        XCTAssertNotNil(GlobalShortcut.menuConflictMessage(keyEquivalent: "Z", modifiers: [.command, .shift]))
        XCTAssertNotNil(GlobalShortcut.menuConflictMessage(keyEquivalent: "\u{F701}", modifiers: .option))
        XCTAssertNotNil(GlobalShortcut.menuConflictMessage(keyEquivalent: "\u{F700}", modifiers: .option))
        XCTAssertNil(GlobalShortcut(keyCode: 53, modifiers: .control), "Esc belongs to recording cancellation")
        XCTAssertNil(GlobalShortcut(keyCode: 255, modifiers: .control))
        XCTAssertNotNil(GlobalShortcut(keyCode: 49, modifiers: [.command, .shift]))
        XCTAssertEqual(try XCTUnwrap(GlobalShortcut(keyCode: 122, modifiers: .control)).specialKeyLabel, "F1")
        XCTAssertEqual(try XCTUnwrap(GlobalShortcut(keyCode: 90, modifiers: .control)).specialKeyLabel, "F20")
    }

    func testMenuConflictUsesTranslatedCharacterInsteadOfUSKeyPosition() throws {
        // Dvorak R occupies the US O position. The same position is not reserved on US keyboards.
        let physicalO = try XCTUnwrap(GlobalShortcut(keyCode: 31, modifiers: .command))
        XCTAssertNotNil(GlobalShortcut.menuConflictMessage(keyEquivalent: "r", modifiers: physicalO.modifiers))
        XCTAssertNil(GlobalShortcut.menuConflictMessage(keyEquivalent: "o", modifiers: physicalO.modifiers))
        let physicalR = try XCTUnwrap(GlobalShortcut(keyCode: 15, modifiers: .command))
        XCTAssertNil(GlobalShortcut.menuConflictMessage(keyEquivalent: "p", modifiers: physicalR.modifiers))
        XCTAssertEqual(GlobalShortcut.restored(from: physicalR.propertyList), physicalR)
    }
}

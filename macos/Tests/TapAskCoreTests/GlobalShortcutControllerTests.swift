import AppKit
import Carbon.HIToolbox
import TapAskCore
import XCTest
@testable import TapAsk

final class GlobalShortcutControllerTests: XCTestCase {
    @MainActor
    func testFailedReplacementKeepsWorkingRegistrationAndSavedPreference() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.controller.start()
        let original = try XCTUnwrap(fixture.registrations.last)
        let custom = try XCTUnwrap(GlobalShortcut(keyCode: 40, modifiers: [.control, .shift]))
        fixture.rejected = custom
        XCTAssertThrowsError(try fixture.controller.save(custom))
        XCTAssertEqual(fixture.controller.shortcut, .defaultShortcut)
        XCTAssertEqual(original.unregisterCount, 0)
        XCTAssertNil(fixture.defaults.object(forKey: GlobalShortcutController.preferenceKey))
        fixture.rejected = nil
        try fixture.controller.save(custom)
        XCTAssertEqual(original.unregisterCount, 1)
        XCTAssertEqual(fixture.controller.shortcut, custom)
        XCTAssertEqual(GlobalShortcut.restored(from: fixture.defaults.object(forKey: GlobalShortcutController.preferenceKey)), custom)
        let restored = GlobalShortcutController(defaults: fixture.defaults, register: { _ in Registration() })
        XCTAssertEqual(restored.shortcut, custom)
        let count = fixture.registrations.count
        try fixture.controller.save(custom)
        XCTAssertEqual(fixture.registrations.count, count, "Saving the active shortcut must not register it twice")
        try fixture.controller.save(.defaultShortcut)
        XCTAssertNil(fixture.defaults.object(forKey: GlobalShortcutController.preferenceKey))
    }

    @MainActor
    func testRecordingSuspendsRestoresAndCanRecoverBySavingAnotherShortcut() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.controller.start()
        let original = try XCTUnwrap(fixture.registrations.last)
        try fixture.controller.setRecording(true)
        try fixture.controller.setRecording(true)
        XCTAssertEqual(original.unregisterCount, 1)
        try fixture.controller.start()
        XCTAssertEqual(fixture.registrations.count, 1)
        fixture.rejected = .defaultShortcut
        XCTAssertThrowsError(try fixture.controller.setRecording(false))
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.shortcut, .defaultShortcut)
        let custom = try XCTUnwrap(GlobalShortcut(keyCode: 40, modifiers: .control))
        try fixture.controller.save(custom)
        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.shortcut, custom)
        try fixture.controller.setRecording(false)
        XCTAssertEqual(fixture.registrations.count, 2)
        try fixture.controller.setRecording(true)
        try fixture.controller.setRecording(false)
        XCTAssertEqual(fixture.registrations.count, 3)
        XCTAssertEqual(fixture.requested.last, custom)
        fixture.controller.stop()
        fixture.controller.stop()
        XCTAssertEqual(fixture.registrations.last?.unregisterCount, 1)
    }

    func testModifierConversionIgnoresCapsLockAndFunctionMetadata() {
        let modifiers = ShortcutModifiers(eventFlags: [.control, .option, .command, .shift, .capsLock, .function])
        XCTAssertEqual(modifiers, .supported)
        XCTAssertEqual(modifiers.eventFlags, [.control, .option, .command, .shift])
        XCTAssertEqual(modifiers.carbonFlags, UInt32(controlKey | optionKey | cmdKey | shiftKey))
    }
}

@MainActor
private final class Registration: HotKeyRegistration {
    var unregisterCount = 0
    func unregister() { unregisterCount += 1 }
}

@MainActor
private final class Fixture {
    let suite = "TapAsk.GlobalShortcutTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var registrations: [Registration] = []
    var requested: [GlobalShortcut] = []
    var rejected: GlobalShortcut?
    lazy var controller = GlobalShortcutController(defaults: defaults) { [unowned self] shortcut in
        requested.append(shortcut)
        if shortcut == rejected { throw HotKey.RegistrationError(status: -9878) }
        let registration = Registration()
        registrations.append(registration)
        return registration
    }
    init() throws { defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) }
    func cleanUp() {
        controller.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}

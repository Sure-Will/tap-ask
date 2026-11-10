import Foundation
import TapAskCore

@MainActor
protocol HotKeyRegistration: AnyObject {
    func unregister()
}

/// Owns the registration and commits preferences only after registration succeeds.
@MainActor
final class GlobalShortcutController {
    static let preferenceKey = "GlobalShortcut"
    private let defaults: UserDefaults
    private let register: (GlobalShortcut) throws -> any HotKeyRegistration
    private var registration: (any HotKeyRegistration)?
    private(set) var shortcut: GlobalShortcut
    private(set) var isRecording = false

    init(defaults: UserDefaults, register: @escaping (GlobalShortcut) throws -> any HotKeyRegistration) {
        self.defaults = defaults
        self.register = register
        shortcut = GlobalShortcut.restored(from: defaults.object(forKey: Self.preferenceKey))
    }

    func start() throws {
        guard registration == nil, !isRecording else { return }
        registration = try register(shortcut)
    }

    func setRecording(_ recording: Bool) throws {
        guard recording != isRecording else { return }
        if recording {
            registration?.unregister()
            registration = nil
            isRecording = true
        } else {
            registration = try register(shortcut)
            isRecording = false
        }
    }

    func save(_ shortcut: GlobalShortcut) throws {
        if shortcut != self.shortcut || registration == nil {
            let replacement = try register(shortcut)
            registration?.unregister()
            registration = replacement
        }
        self.shortcut = shortcut
        isRecording = false
        if shortcut == .defaultShortcut { defaults.removeObject(forKey: Self.preferenceKey) }
        else { defaults.set(shortcut.propertyList, forKey: Self.preferenceKey) }
    }

    func stop() {
        registration?.unregister()
        registration = nil
        isRecording = false
    }
}

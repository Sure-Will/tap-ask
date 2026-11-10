import Carbon.HIToolbox
import AppKit
import TapAskCore

/// One Carbon hotkey, owned for the application lifetime; no event tap or accessibility grant.
@MainActor
final class HotKey: HotKeyRegistration {
    struct RegistrationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "快捷键注册失败（\(status)），请换一组组合键或重试。" }
    }
    private static var nextID: UInt32 = 0
    private let identifier: EventHotKeyID
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onPressed: @MainActor () -> Void

    init(shortcut: GlobalShortcut, onPressed: @escaping @MainActor () -> Void) throws {
        if let message = GlobalShortcut.menuConflictMessage(keyEquivalent: shortcut.keyEquivalent, modifiers: shortcut.modifiers) {
            throw ShortcutConflictError(message: message)
        }
        self.onPressed = onPressed
        Self.nextID &+= 1
        identifier = EventHotKeyID(signature: 0x5441_534B, id: Self.nextID)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            // Carbon dispatches application hotkey events on the main thread.
            return MainActor.assumeIsolated {
                let owner = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == owner.identifier.signature, identifier.id == owner.identifier.id else {
                    return OSStatus(eventNotHandledErr)
                }
                owner.onPressed()
                return noErr
            }
        }, 1, &spec, context, &eventHandlerRef)
        guard handlerStatus == noErr else { throw RegistrationError(status: handlerStatus) }
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbonFlags, identifier,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            unregister()
            throw RegistrationError(status: status)
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
    }
}

private struct ShortcutConflictError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension ShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        self = []
        if eventFlags.contains(.control) { insert(.control) }
        if eventFlags.contains(.option) { insert(.option) }
        if eventFlags.contains(.shift) { insert(.shift) }
        if eventFlags.contains(.command) { insert(.command) }
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}

extension GlobalShortcut {
    @MainActor var displayString: String {
        modifiers.symbols + (specialKeyLabel ?? keyEquivalent.uppercased())
    }

    @MainActor var keyEquivalent: String {
        guard specialKeyLabel == nil else { return fallbackKeyEquivalent }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallbackKeyEquivalent
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                    OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                                    characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return fallbackKeyEquivalent }
        return String(utf16CodeUnits: characters, count: length).lowercased()
    }
}

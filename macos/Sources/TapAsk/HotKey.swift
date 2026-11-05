import Carbon.HIToolbox

/// One Carbon hotkey, owned for the application lifetime; no event tap or accessibility grant.
@MainActor
final class HotKey {
    struct RegistrationError: Error { let status: OSStatus }
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onPressed: @MainActor () -> Void

    init(onPressed: @escaping @MainActor () -> Void) throws {
        self.onPressed = onPressed
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            guard identifier.signature == 0x5441_534B, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches application hotkey events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().onPressed()
            }
            return noErr
        }, 1, &spec, context, &eventHandlerRef)
        guard handlerStatus == noErr else { throw RegistrationError(status: handlerStatus) }
        let identifier = EventHotKeyID(signature: 0x5441_534B, id: 1) // 'TASK'
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), identifier,
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

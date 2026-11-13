import AppKit
import Carbon.HIToolbox
import TapAskCore

@MainActor
final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate, NSTabViewDelegate {
    var onSave: ((GlobalShortcut) throws -> Void)?
    var onRecordingChange: ((Bool) throws -> Void)?
    var onClose: (() -> Void)?
    var onRequestClose: (() -> Void)?
    private(set) var isOpen = false

    private var draft: GlobalShortcut
    private var isRecording = false
    var isRecordingShortcut: Bool { isRecording }
    private var needsRegistrationRestore = false
    private var eventMonitor: ShortcutEventMonitor?
    private let recorder = NSButton()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var settingsTabs: NSTabView?
    private var generalView: SettingsGeneralView?

    init(shortcut: GlobalShortcut) {
        draft = shortcut
        let window = ShortcutSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 224),
                                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "快捷键设置"
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.captureKey = { [weak self] event in self?.capture(event) ?? false }
        window.beforeClose = { [weak self] in self?.stopRecording() ?? true }

        let content = NSView()
        window.contentView = content
        let label = NSTextField(labelWithString: "呼出 / 收起 TapAsk")
        label.font = .systemFont(ofSize: 13)
        recorder.title = shortcut.displayString
        recorder.bezelStyle = .rounded
        recorder.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        recorder.target = self
        recorder.action = #selector(toggleRecording(_:))
        recorder.setAccessibilityLabel("呼出或收起 TapAsk 的快捷键")
        recorder.toolTip = "点按后输入新的快捷键，Esc 取消录制"
        let hint = NSTextField(wrappingLabelWithString: "须包含 ⌘、⌥ 或 ⌃，可加 ⇧；Esc 取消。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityLabel("快捷键错误")
        let reset = button("恢复默认", action: #selector(restoreDefault(_:)))
        let cancel = button("取消", action: #selector(cancel(_:)))
        let save = button("保存", action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        for view in [label, recorder, hint, errorLabel, reset, cancel, save] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: recorder.centerYAnchor),
            recorder.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            recorder.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            recorder.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 16),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 142),
            recorder.heightAnchor.constraint(equalToConstant: 32),
            hint.topAnchor.constraint(equalTo: recorder.bottomAnchor, constant: 12),
            hint.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: recorder.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            errorLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: recorder.trailingAnchor),
            errorLabel.bottomAnchor.constraint(lessThanOrEqualTo: save.topAnchor, constant: -12),
            reset.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            reset.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            save.trailingAnchor.constraint(equalTo: recorder.trailingAnchor),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            save.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configureSettings(orderController: ProviderOrderWindowController,
                           updater: (any AppUpdating)?, defaults: UserDefaults) {
        guard settingsTabs == nil, let window, let shortcutView = window.contentView,
              let orderWindow = orderController.window, let orderView = orderWindow.contentView else { return }
        orderWindow.contentView = NSView()
        window.contentView = NSView()
        let general = SettingsGeneralView(updater: updater, defaults: defaults)
        let tabs = NSTabView()
        tabs.delegate = self
        for (title, view) in [("通用", general as NSView), ("快捷键", shortcutView), ("服务商排序", orderView)] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        window.contentView = tabs
        window.setContentSize(NSSize(width: 430, height: 400))
        window.title = "设置"
        settingsTabs = tabs
        generalView = general
    }

    func present(shortcut: GlobalShortcut) {
        prepare(shortcut: shortcut)
        generalView?.refresh()
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if settingsTabs == nil || settingsTabs?.selectedTabViewItem?.identifier as? String == "快捷键" {
            window?.makeFirstResponder(recorder)
        }
    }

    func prepare(shortcut: GlobalShortcut) {
        isOpen = true
        if stopRecording() {
            draft = shortcut
            errorLabel.stringValue = ""
        }
        updateRecorder()
    }

    func popoverShouldClose() -> Bool { stopRecording() }

    func focusRecorder() { recorder.window?.makeFirstResponder(recorder) }

    func popoverDidClose() {
        isOpen = false
        onClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { stopRecording() }

    func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
        stopRecording()
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        onClose?()
    }

    func windowDidResignKey(_ notification: Notification) {
        stopRecording()
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func toggleRecording(_ sender: Any?) {
        if isRecording {
            if stopRecording() { errorLabel.stringValue = "" }
            return
        }
        do {
            if !needsRegistrationRestore {
                try onRecordingChange?(true)
                needsRegistrationRestore = true
            }
            isRecording = true
            eventMonitor = ShortcutEventMonitor { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let window = self.recorder.window,
                          event.window === window || (event.window == nil && window.isKeyWindow) else { return false }
                    return self.capture(event)
                }
                return consumed ? nil : event
            }
            errorLabel.stringValue = ""
            updateRecorder()
        } catch {
            updateRecorder()
            show(error)
        }
    }

    private func capture(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.type == .flagsChanged { return true }
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat else { return true }
        if event.keyCode == UInt16(kVK_Escape) {
            if stopRecording() { errorLabel.stringValue = "" }
            return true
        }
        let modifierKeys = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
                            kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
                            kVK_CapsLock, kVK_Function]
        guard !modifierKeys.contains(Int(event.keyCode)) else { return true }
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        if let message = GlobalShortcut.validationMessage(keyCode: event.keyCode, modifiers: modifiers) {
            errorLabel.stringValue = message
            return true
        }
        guard let shortcut = GlobalShortcut(keyCode: event.keyCode, modifiers: modifiers) else { return true }
        if let message = GlobalShortcut.menuConflictMessage(
            keyEquivalent: event.charactersIgnoringModifiers ?? shortcut.keyEquivalent, modifiers: modifiers) {
            errorLabel.stringValue = message
            return true
        }
        draft = shortcut
        if stopRecording() { errorLabel.stringValue = "" }
        return true
    }

    /// A failed restoration stays pending so close/save can retry it and surface the failure.
    @discardableResult
    private func stopRecording() -> Bool {
        isRecording = false
        eventMonitor = nil
        updateRecorder()
        guard needsRegistrationRestore else { return true }
        do {
            try onRecordingChange?(false)
            needsRegistrationRestore = false
            return true
        } catch {
            show(error)
            return false
        }
    }

    private func updateRecorder() {
        recorder.title = isRecording ? "请按快捷键…" : draft.displayString
        recorder.state = isRecording ? .on : .off
    }

    private func show(_ error: Error) {
        errorLabel.stringValue = error.localizedDescription
    }

    @objc private func restoreDefault(_ sender: Any?) {
        draft = .defaultShortcut
        if stopRecording() { errorLabel.stringValue = "" }
    }

    @objc private func cancel(_ sender: Any?) {
        if let onRequestClose { onRequestClose() }
        else { window?.performClose(nil) }
    }

    @objc private func save(_ sender: Any?) {
        isRecording = false
        eventMonitor = nil
        updateRecorder()
        do {
            try onSave?(draft)
            needsRegistrationRestore = false
            if let onRequestClose { onRequestClose() }
            else { window?.performClose(nil) }
        } catch {
            show(error)
        }
    }
}

/// Local monitoring precedes NSApplication's main-menu key equivalents.
/// The token is released on every exit from recording, including owner destruction.
private final class ShortcutEventMonitor {
    private let token: Any?
    init(handler: @escaping (NSEvent) -> NSEvent?) {
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handler)
    }
    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}

@MainActor
private final class ShortcutSettingsWindow: NSWindow {
    var captureKey: ((NSEvent) -> Bool)?
    var beforeClose: (() -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if captureKey?(event) == true { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if captureKey?(event) == true { return true }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func close() {
        guard beforeClose?() ?? true else { return }
        super.close()
    }
}

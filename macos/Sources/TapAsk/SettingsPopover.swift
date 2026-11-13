import AppKit
import TapAskCore

/// Hosts the existing settings controls below the status item without presenting a settings window.
@MainActor
final class SettingsPopoverController: NSObject, NSPopoverDelegate {
    enum Section { case shortcut, providerOrder }

    private let popover = NSPopover()
    private let shortcutController: ShortcutSettingsWindowController
    private let orderController: ProviderOrderWindowController
    private let shortcutView: NSView
    private let orderView: NSView
    private var section: Section?
    private var keyMonitor: PopoverKeyMonitor?

    var isShown: Bool { popover.isShown }

    init(shortcutController: ShortcutSettingsWindowController, orderController: ProviderOrderWindowController) {
        self.shortcutController = shortcutController
        self.orderController = orderController
        let shortcutWindow = shortcutController.window!
        let orderWindow = orderController.window!
        shortcutView = shortcutWindow.contentView!
        orderView = orderWindow.contentView!
        shortcutWindow.contentView = NSView()
        orderWindow.contentView = NSView()
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        shortcutController.onRequestClose = { [weak self] in self?.popover.performClose(nil) }
    }

    func show(_ requested: Section, relativeTo anchor: NSView, shortcut: GlobalShortcut) {
        if popover.isShown {
            popover.performClose(nil)
            if popover.isShown { return }
        }
        section = requested
        let content = requested == .shortcut ? shortcutView : orderView
        if requested == .shortcut { shortcutController.prepare(shortcut: shortcut) }
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.contentSize = requested == .shortcut ? NSSize(width: 360, height: 168) : content.frame.size
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        content.window?.makeKeyAndOrderFront(nil)
        if requested == .shortcut { shortcutController.focusRecorder() }
        else { orderController.focusTable() }
        keyMonitor = PopoverKeyMonitor { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.popover.contentViewController?.view.window,
                      event.window === window, !self.shortcutController.isRecordingShortcut,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                      event.charactersIgnoringModifiers == "w" else { return false }
                self.popover.performClose(nil)
                return true
            }
            return handled ? nil : event
        }
    }

    func close() { popover.performClose(nil) }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        section != .shortcut || shortcutController.popoverShouldClose()
    }

    func popoverDidClose(_ notification: Notification) {
        keyMonitor = nil
        if section == .shortcut { shortcutController.popoverDidClose() }
        section = nil
    }
}

private final class PopoverKeyMonitor {
    private let token: Any?
    init(handler: @escaping (NSEvent) -> NSEvent?) {
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }
    deinit { if let token { NSEvent.removeMonitor(token) } }
}

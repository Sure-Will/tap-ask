import AppKit

@MainActor
final class ChatPanel: NSPanel, NSWindowDelegate {
    private static let frameKey = "PanelFrame"
    private var savedFrame: NSRect?
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = ""
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        minSize = NSSize(width: 360, height: 480)
        backgroundColor = .windowBackgroundColor
        setFrame(NSRect(x: 0, y: 0, width: 480, height: 720), display: false)
        if let text = UserDefaults.standard.string(forKey: Self.frameKey) {
            let saved = NSRectFromString(text)
            if saved.width >= minSize.width, saved.height >= minSize.height,
               [saved.origin.x, saved.origin.y, saved.width, saved.height].allSatisfy({ $0.isFinite }) {
                savedFrame = saved
                setFrame(saved, display: false)
            }
        }
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func prepareForPresentation() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        if let savedFrame, screen.frame.contains(NSPoint(x: savedFrame.midX, y: savedFrame.midY)) {
            setFrame(savedFrame, display: false)
        } else {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
        }
        saveFrame()
    }

    private func saveFrame() {
        savedFrame = frame
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey?() }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func close() { onCancel?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

import AppKit
import TapAskCore

@MainActor
final class ChatPanel: NSPanel, NSWindowDelegate {
    private static let frameKey = "PanelFrame"
    private let defaults: UserDefaults
    private var savedFrame: NSRect?
    private let dragStrip = PanelDragView()
    private let originBadge = OriginBadgeView()
    private let pageLoadOverlay = PageLoadOverlayView()
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?
    var onRetry: (() -> Void)? {
        didSet { pageLoadOverlay.onRetry = onRetry }
    }
    var origin = "" {
        didSet { originBadge.origin = origin }
    }

    override var contentView: NSView? {
        didSet { installOverlays() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = ""
        titleVisibility = .hidden
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
        if let text = defaults.string(forKey: Self.frameKey) {
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

    func updateLoadState(_ state: PageLoadState, providerName: String) {
        pageLoadOverlay.update(state, providerName: providerName)
    }

    private func installOverlays() {
        dragStrip.removeFromSuperview()
        originBadge.removeFromSuperview()
        pageLoadOverlay.removeFromSuperview()
        guard let contentView else { return }
        for overlay in [dragStrip, originBadge, pageLoadOverlay] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        NSLayoutConstraint.activate([
            dragStrip.topAnchor.constraint(equalTo: contentView.topAnchor),
            dragStrip.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dragStrip.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dragStrip.heightAnchor.constraint(equalToConstant: 8),
            originBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            originBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            originBadge.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -24),
            pageLoadOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageLoadOverlay.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pageLoadOverlay.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32),
        ])
    }

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
        defaults.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey?() }

    /// An Esc the page leaves unhandled is ignored; use ⌥Space or the status menu to hide.
    override func cancelOperation(_ sender: Any?) {}
    override func close() { onCancel?() }
}

@MainActor
final class PanelDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

@MainActor
final class OriginBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    var origin = "" {
        didSet {
            label.stringValue = origin
            isHidden = origin.isEmpty
        }
    }

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.78).cgColor
        layer?.cornerRadius = 10
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor(white: 1, alpha: 0.95)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { nil }

    // Pass through the label and its background, including when a page button is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import AppKit
import TapAskCore

@MainActor
final class ChatPanel: NSPanel, NSWindowDelegate {
    private static let frameKey = "PanelFrame"
    private static let normalMinimumSize = NSSize(width: 360, height: 480)
    private let defaults: UserDefaults
    private var savedFrame: NSRect?
    private let pageContainer = NSView()
    private let dragStrip = PanelDragView()
    private let originBadge = OriginBadgeView()
    private let navigationNotice = NavigationNoticeView()
    private var noticeBelowOrigin: NSLayoutConstraint?
    private var noticeAtTop: NSLayoutConstraint?
    private let pageLoadOverlay = PageLoadOverlayView()
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?
    var onRetry: (() -> Void)? {
        didSet { pageLoadOverlay.onRetry = onRetry }
    }
    var origin = "" {
        didSet {
            originBadge.origin = origin
            updateNoticePosition()
        }
    }

    var pageView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            installPage()
        }
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
        minSize = Self.normalMinimumSize
        backgroundColor = .windowBackgroundColor
        setFrame(NSRect(x: 0, y: 0, width: 480, height: 720), display: false)
        if let text = defaults.string(forKey: Self.frameKey) {
            let saved = NSRectFromString(text)
            if saved.width > 0, saved.height > 0,
               [saved.origin.x, saved.origin.y, saved.width, saved.height].allSatisfy({ $0.isFinite }) {
                savedFrame = saved
                setFrame(saved, display: false)
            }
        }
        delegate = self
        contentView = pageContainer
        dragStrip.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(dragStrip)
        NSLayoutConstraint.activate([
            dragStrip.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            dragStrip.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            dragStrip.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            dragStrip.heightAnchor.constraint(equalToConstant: PanelDragView.height),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func updateLoadState(_ state: PageLoadState, providerName: String) {
        pageLoadOverlay.update(state, providerName: providerName)
    }

    func showNavigationNotice(_ notice: NavigationNotice) {
        navigationNotice.show(notice)
    }

    private func updateNoticePosition() {
        noticeBelowOrigin?.isActive = false
        noticeAtTop?.isActive = false
        (origin.isEmpty ? noticeAtTop : noticeBelowOrigin)?.isActive = true
    }

    private func installPage() {
        navigationNotice.dismiss()
        noticeBelowOrigin?.isActive = false
        noticeAtTop?.isActive = false
        noticeBelowOrigin = nil
        noticeAtTop = nil
        originBadge.removeFromSuperview()
        pageLoadOverlay.removeFromSuperview()
        navigationNotice.removeFromSuperview()
        guard let pageView else { return }
        pageView.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(pageView, positioned: .below, relativeTo: dragStrip)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
        ])
        for overlay in [originBadge, pageLoadOverlay, navigationNotice] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            pageView.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        NSLayoutConstraint.activate([
            originBadge.topAnchor.constraint(equalTo: pageView.topAnchor, constant: 28),
            originBadge.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
            originBadge.widthAnchor.constraint(lessThanOrEqualTo: pageView.widthAnchor, constant: -24),
            navigationNotice.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
            navigationNotice.widthAnchor.constraint(lessThanOrEqualTo: pageView.widthAnchor, constant: -24),
            pageLoadOverlay.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
            pageLoadOverlay.centerYAnchor.constraint(equalTo: pageView.centerYAnchor),
            pageLoadOverlay.widthAnchor.constraint(lessThanOrEqualTo: pageView.widthAnchor, constant: -32),
        ])
        noticeBelowOrigin = navigationNotice.topAnchor.constraint(equalTo: originBadge.bottomAnchor, constant: 6)
        noticeAtTop = navigationNotice.topAnchor.constraint(equalTo: pageView.topAnchor, constant: 28)
        updateNoticePosition()
    }

    func prepareForPresentation() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        prepareForPresentation(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    func prepareForPresentation(screenFrame: NSRect, visibleFrame: NSRect) {
        let fittedFrame = chatPanelFrame(currentFrame: frame, savedFrame: savedFrame,
                                        screenFrame: screenFrame, visibleFrame: visibleFrame)
        // AppKit's minimum must allow the same tiny-screen exception as the geometry.
        // Restore the usual constraint on the next presentation on a larger display.
        minSize = NSSize(width: min(Self.normalMinimumSize.width, visibleFrame.width),
                         height: min(Self.normalMinimumSize.height, visibleFrame.height))
        setFrame(fittedFrame, display: false)
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
    static let height: CGFloat = 24
    static let handleSize = NSSize(width: 36, height: 4)

    var handleRect: NSRect {
        NSRect(x: bounds.midX - Self.handleSize.width / 2,
               y: bounds.midY - Self.handleSize.height / 2 + 4,
               width: Self.handleSize.width, height: Self.handleSize.height)
    }

    private var dragRect: NSRect {
        NSRect(x: bounds.midX - 30, y: bounds.midY - 10, width: 60, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func resetCursorRects() {
        addCursorRect(dragRect, cursor: .openHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil,
              dragRect.contains(convert(point, from: superview)) else { return nil }
        return self
    }

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

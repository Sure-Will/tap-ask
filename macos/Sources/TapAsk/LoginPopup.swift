import AppKit
import TapAskCore
import WebKit

/// Owns one temporary login window. WebKit, not this owner, starts its initial navigation.
@MainActor
final class LoginPopup {
    let panel: LoginPanel
    let webView: WKWebView
    private let webDelegate: WebViewDelegate
    var onClose: (() -> Void)?

    init(configuration: WKWebViewConfiguration, policy: NavigationPolicy, initialURL: URL?) {
        webDelegate = WebViewDelegate(policy: policy, isPopup: true)
        webView = webDelegate.makeWebView(configuration: configuration)
        panel = LoginPanel()
        panel.title = NavigationPolicy.origin(initialURL)
        panel.contentView = webView
        panel.onCancel = { [weak self] in self?.onClose?() }
        webDelegate.onClose = { [weak self] in self?.onClose?() }
        webDelegate.onCommit = { [weak self] url in
            self?.panel.title = NavigationPolicy.origin(url)
        }
    }

    func show(relativeTo parent: NSWindow) {
        if panel.parent == nil {
            // Center horizontally and align the top edges, above the main window's center.
            panel.setFrameOrigin(NSPoint(x: parent.frame.midX - panel.frame.width / 2,
                                         y: parent.frame.maxY - panel.frame.height))
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
    }

    func hide() { panel.orderOut(nil) }

    func dispose() {
        onClose = nil
        webDelegate.onClose = nil
        webDelegate.onCommit = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        panel.parent?.removeChildWindow(panel)
        panel.onCancel = nil
        panel.onBecomeKey = nil
        panel.contentView = nil
        panel.close()
    }
}

@MainActor
final class LoginPanel: NSPanel, NSWindowDelegate {
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        titleVisibility = .visible
        titlebarAppearsTransparent = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        minSize = NSSize(width: 360, height: 480)
        setFrame(NSRect(x: 0, y: 0, width: 480, height: 640), display: false)
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey?() }
    /// The close button or the page's window.close() ends the popup; Esc does not.
    override func cancelOperation(_ sender: Any?) {}

    override func close() {
        if let onCancel { onCancel() }
        else { super.close() } // Disposal clears the callback before closing the actual window.
    }
}

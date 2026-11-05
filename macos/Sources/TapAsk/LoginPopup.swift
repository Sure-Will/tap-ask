import AppKit
import TapAskCore
import WebKit

/// Owns one temporary login window. WebKit, not this owner, starts its initial navigation.
@MainActor
final class LoginPopup {
    let panel: LoginPanel
    let webView: WKWebView
    private let webDelegate: WebViewDelegate
    private let policy: NavigationPolicy
    private let initialURL: URL?
    private let pageLoadOverlay = PageLoadOverlayView()
    private let navigationNotice = NavigationNoticeView()
    private var placement = LoginPopupPlacement()
    var onClose: (() -> Void)?

    init(configuration: WKWebViewConfiguration, policy: NavigationPolicy, initialURL: URL?) {
        self.policy = policy
        self.initialURL = initialURL
        webDelegate = WebViewDelegate(policy: policy, isPopup: true)
        webView = webDelegate.makeWebView(configuration: configuration)
        panel = LoginPanel()
        panel.title = NavigationPolicy.origin(initialURL)
        panel.contentView = webView
        pageLoadOverlay.translatesAutoresizingMaskIntoConstraints = false
        webView.addSubview(pageLoadOverlay, positioned: .above, relativeTo: nil)
        navigationNotice.translatesAutoresizingMaskIntoConstraints = false
        webView.addSubview(navigationNotice, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            pageLoadOverlay.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            pageLoadOverlay.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            pageLoadOverlay.widthAnchor.constraint(lessThanOrEqualTo: webView.widthAnchor, constant: -32),
            navigationNotice.topAnchor.constraint(equalTo: webView.topAnchor, constant: 10),
            navigationNotice.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            navigationNotice.widthAnchor.constraint(lessThanOrEqualTo: webView.widthAnchor, constant: -24),
        ])
        pageLoadOverlay.onRetry = { [weak self] in self?.reload() }
        webDelegate.onLoadStateChange = { [weak self] state in self?.updateLoadState(state) }
        webDelegate.onNavigationNotice = { [weak self] notice in self?.navigationNotice.show(notice) }
        panel.onCancel = { [weak self] in self?.onClose?() }
        panel.onUserAdjustFrame = { [weak self] in self?.placement.userDidAdjustFrame() }
        webDelegate.onClose = { [weak self] in self?.onClose?() }
        webDelegate.onCommit = { [weak self] url in
            self?.panel.title = NavigationPolicy.origin(url)
        }
    }

    func show(relativeTo parent: NSWindow) {
        let center = NSPoint(x: parent.frame.midX, y: parent.frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main,
           let frame = placement.frameForPresentation(parentFrame: parent.frame, desiredSize: LoginPanel.initialSize,
                                                       screenFrame: screen.frame, visibleFrame: screen.visibleFrame) {
            // Very small displays must also be allowed below AppKit's usual minimum.
            panel.minSize = NSSize(width: min(360, frame.width), height: min(480, frame.height))
            panel.setFrame(frame, display: false)
        }
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        focusWebView()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !NSApp.isHidden, !self.panel.isKeyWindow else { return }
            self.focusWebView()
        }
    }

    private func focusWebView() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
    }

    func hide() { panel.orderOut(nil) }

    /// Never reload the last request: it may be a POST or a one-time OAuth callback.
    func reload() {
        guard let url = loginPopupRetryURL(initialURL: initialURL, policy: policy) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        webView.load(request)
    }

    private func updateLoadState(_ state: PageLoadState) {
        pageLoadOverlay.update(state, loadingMessage: "正在打开登录页…", failureMessage: "登录页打不开",
                               canRetry: loginPopupRetryURL(initialURL: initialURL, policy: policy) != nil)
    }

    func dispose() {
        onClose = nil
        webDelegate.onClose = nil
        webDelegate.onCommit = nil
        webDelegate.onLoadStateChange = nil
        webDelegate.onNavigationNotice = nil
        pageLoadOverlay.onRetry = nil
        updateLoadState(.idle)
        pageLoadOverlay.removeFromSuperview()
        navigationNotice.dismiss()
        navigationNotice.removeFromSuperview()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        panel.parent?.removeChildWindow(panel)
        panel.onCancel = nil
        panel.onBecomeKey = nil
        panel.onUserAdjustFrame = nil
        panel.contentView = nil
        panel.close()
    }
}

@MainActor
final class LoginPanel: NSPanel, NSWindowDelegate {
    static let initialSize = NSSize(width: 480, height: 640)
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?
    var onUserAdjustFrame: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.initialSize),
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
        setFrame(NSRect(origin: .zero, size: Self.initialSize), display: false)
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey?() }
    // Unlike didMove/didResize, these mark interactive changes rather than our
    // setFrame calls or the child following its parent to another display.
    func windowWillMove(_ notification: Notification) { onUserAdjustFrame?() }
    func windowWillStartLiveResize(_ notification: Notification) { onUserAdjustFrame?() }
    /// The close button or the page's window.close() ends the popup; Esc does not.
    override func cancelOperation(_ sender: Any?) {}

    override func close() {
        if let onCancel { onCancel() }
        else { super.close() } // Disposal clears the callback before closing the actual window.
    }
}

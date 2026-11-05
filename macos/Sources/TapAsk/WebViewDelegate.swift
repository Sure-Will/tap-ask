import AppKit
import TapAskCore
import WebKit

@MainActor
final class WebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    // Safari UA from the user's patched Quick-Chat build (2026-11-04).
    private static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private let policy: NavigationPolicy
    private let isPopup: Bool
    var onCommit: ((URL?) -> Void)?
    var onCreatePopup: ((WKWebViewConfiguration, URL?) -> WKWebView?)?
    var onClose: (() -> Void)?

    init(policy: NavigationPolicy, isPopup: Bool = false) {
        self.policy = policy
        self.isPopup = isPopup
    }

    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.safariUserAgent
        webView.underPageBackgroundColor = .windowBackgroundColor
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return webView
    }

    private func decision(for action: WKNavigationAction) -> NavigationPolicy.Decision {
        policy.action(url: action.request.url,
                      topLevel: action.targetFrame == nil || action.targetFrame?.isMainFrame == true,
                      clickedLink: action.navigationType == .linkActivated,
                      method: action.request.httpMethod,
                      wantsDownload: action.shouldPerformDownload,
                      sourceURL: action.sourceFrame.request.url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let result = decision(for: navigationAction)
        let newWindow = navigationAction.targetFrame == nil
        if newWindow || navigationAction.targetFrame?.isMainFrame == true {
            log(navigationAction.request.url, phase: "action", result: result)
        }
        switch result {
        case .allow:
            if newWindow && isPopup {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else {
                // Main-window popups must reach createWebViewWith without replacing their opener.
                decisionHandler(.allow)
            }
        case .browser:
            decisionHandler(.cancel)
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        case .download:
            decisionHandler(.cancel)
            log(navigationAction.request.url, phase: "download-cancelled", result: result)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
        let result = policy.response(url: navigationResponse.response.url,
                                     mainFrame: navigationResponse.isForMainFrame,
                                     canDisplay: navigationResponse.canShowMIMEType,
                                     attachment: disposition?.hasPrefix("attachment") == true)
        if navigationResponse.isForMainFrame {
            log(navigationResponse.response.url, phase: "response", result: result)
        }
        if result == .download { log(navigationResponse.response.url, phase: "download-cancelled", result: result) }
        decisionHandler(result == .allow ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let allowed = policy.isPanelURL(webView.url)
        log(webView.url, phase: "redirect", result: allowed ? .allow : .cancel)
        if !allowed { webView.stopLoading() }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // The visible document keeps its origin until the next document actually commits.
        onCommit?(webView.url)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Apply the same clicked-GET/source rules even if WebKit reaches this callback directly.
        let result = decision(for: navigationAction)
        log(navigationAction.request.url, phase: "new-window", result: result)
        switch result {
        case .allow:
            if isPopup {
                // Nested popups reuse the existing login window; never create a third window.
                webView.load(navigationAction.request)
            } else {
                // WebKit loads the returned view and preserves its relationship with window.opener.
                return onCreatePopup?(configuration, navigationAction.request.url)
            }
        case .browser:
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        case .download, .cancel: break
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        if isPopup { onClose?() }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        guard let window = webView.window else { completionHandler(nil); return }
        let open = NSOpenPanel()
        open.canChooseFiles = true
        open.canChooseDirectories = parameters.allowsDirectories
        open.allowsMultipleSelection = parameters.allowsMultipleSelection
        open.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? open.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log(webView.url, phase: "process-terminated-reload", result: .allow)
        if webView.url != nil { webView.reload() }
        else { webView.load(URLRequest(url: policy.provider.home)) }
    }

    private func log(_ url: URL?, phase: String, result: NavigationPolicy.Decision) {
        let host = url?.host?.lowercased() ?? "<none>"
        let scope = isPopup ? "popup" : "main"
        AppLog.navigation.info("phase=\(scope, privacy: .public)-\(phase, privacy: .public) host=\(host, privacy: .public) policy=\(result.rawValue, privacy: .public)")
    }
}

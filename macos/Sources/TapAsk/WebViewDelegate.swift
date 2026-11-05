import AppKit
import TapAskCore
import WebKit

@MainActor
final class WebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    // Desktop Safari UA: providers serve their full web app and permit Google sign-in.
    private static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private let policy: NavigationPolicy
    private let isPopup: Bool
    private var loadState: PageLoadState = .idle
    var onLoadStateChange: ((PageLoadState) -> Void)?
    var onNavigationNotice: ((NavigationNotice) -> Void)?
    var onCommit: ((URL?) -> Void)?
    var onProcessTermination: ((WebContentTerminationAction) -> Void)?
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
        let noticeEvent: NavigationNoticeEvent = navigationAction.shouldPerformDownload
            || NavigationPolicy.isGeneratedFile(navigationAction.request.url) ? .download : .action
        let noticeMainFrame = navigationAction.targetFrame?.isMainFrame ?? navigationAction.sourceFrame.isMainFrame
        if newWindow || navigationAction.targetFrame?.isMainFrame == true {
            log(navigationAction.request.url, phase: "action", result: result)
        }
        switch result {
        case .allow:
            if newWindow && isPopup {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else {
                // Route main-window requests in createWebViewWith, preserving login openers.
                decisionHandler(.allow)
            }
        case .browser:
            decisionHandler(.cancel)
            if let url = navigationAction.request.url, NSWorkspace.shared.open(url) {
                reportNotice(noticeEvent, mainFrame: noticeMainFrame, result: result, url: url)
            }
        case .download:
            decisionHandler(.cancel)
            log(navigationAction.request.url, phase: "download-cancelled", result: result)
        case .cancel:
            decisionHandler(.cancel)
            reportNotice(noticeEvent, mainFrame: noticeMainFrame, result: result, url: navigationAction.request.url)
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
        let noticeEvent: NavigationNoticeEvent = !navigationResponse.canShowMIMEType
            || disposition?.hasPrefix("attachment") == true ? .download : .response
        reportNotice(noticeEvent, mainFrame: navigationResponse.isForMainFrame,
                     result: result, url: navigationResponse.response.url)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let allowed = policy.isPanelURL(webView.url)
        log(webView.url, phase: "redirect", result: allowed ? .allow : .cancel)
        // This WKNavigationDelegate callback describes the main-frame provisional navigation.
        reportNotice(.redirect, mainFrame: true, result: allowed ? .allow : .cancel, url: webView.url)
        if !allowed { webView.stopLoading() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateLoadState(.start)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateLoadState(.commit)
        // The visible document keeps its origin until the next document actually commits.
        onCommit?(webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        handleLoadFailure(error as NSError, in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error as NSError, in: webView)
    }

    private func updateLoadState(_ event: PageLoadEvent) {
        let next = nextPageLoadState(from: loadState, on: event)
        guard next != loadState else { return }
        loadState = next
        onLoadStateChange?(next)
    }

    private func handleLoadFailure(_ error: NSError, in webView: WKWebView) {
        let url = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap { URL(string: $0) }
            ?? webView.url
        let host = url?.host?.lowercased() ?? "<none>"
        let result: NavigationPolicy.Decision = policy.isPanelURL(url) ? .allow : .cancel
        let scope = isPopup ? "popup" : "main"
        AppLog.navigation.error("provider=\(self.policy.provider.id, privacy: .public) phase=\(scope, privacy: .public)-fail host=\(host, privacy: .public) policy=\(result.rawValue, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
        updateLoadState(.fail(domain: error.domain, code: error.code))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Apply the same clicked-GET/source rules even if WebKit reaches this callback directly.
        let result = decision(for: navigationAction)
        let opensInMainView = !isPopup && result == .allow && policy.isProviderURL(navigationAction.request.url)
        log(navigationAction.request.url, phase: opensInMainView ? "new-window-inline" : "new-window", result: result)
        switch result {
        case .allow:
            if isPopup {
                // Nested popups reuse the existing login window; never create a third window.
                webView.load(navigationAction.request)
            } else if opensInMainView {
                webView.load(navigationAction.request)
            } else {
                // WebKit loads the returned view and preserves its relationship with window.opener.
                return onCreatePopup?(configuration, navigationAction.request.url)
            }
        case .browser:
            if let url = navigationAction.request.url, NSWorkspace.shared.open(url) {
                reportNewWindowNotice(navigationAction, result: result)
            }
        case .cancel:
            reportNewWindowNotice(navigationAction, result: result)
        case .download: break
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
        let action = webContentTerminationAction(isMainWindow: !isPopup,
            isDisplayed: webView.window?.isVisible == true && !NSApp.isHidden)
        updateLoadState(.processTerminated)
        log(webView.url, phase: action == .reloadNow ? "process-terminated-reload" : "process-terminated-deferred",
            result: .allow)
        if isPopup {
            if webView.url != nil { webView.reload() }
            else { webView.load(URLRequest(url: policy.provider.home)) }
        } else {
            onProcessTermination?(action)
        }
    }

    private func log(_ url: URL?, phase: String, result: NavigationPolicy.Decision) {
        let host = url?.host?.lowercased() ?? "<none>"
        let scope = isPopup ? "popup" : "main"
        AppLog.navigation.info("provider=\(self.policy.provider.id, privacy: .public) phase=\(scope, privacy: .public)-\(phase, privacy: .public) host=\(host, privacy: .public) policy=\(result.rawValue, privacy: .public)")
    }

    private func reportNewWindowNotice(_ action: WKNavigationAction, result: NavigationPolicy.Decision) {
        let event: NavigationNoticeEvent = action.shouldPerformDownload
            || NavigationPolicy.isGeneratedFile(action.request.url) ? .download : .newWindow
        reportNotice(event, mainFrame: action.sourceFrame.isMainFrame, result: result, url: action.request.url)
    }

    private func reportNotice(_ event: NavigationNoticeEvent, mainFrame: Bool,
                              result: NavigationPolicy.Decision, url: URL?) {
        guard let notice = navigationNotice(for: event, mainFrame: mainFrame, decision: result,
                                            host: url?.host, providerName: policy.provider.name) else { return }
        onNavigationNotice?(notice)
    }
}

import AppKit
import XCTest
import WebKit
@testable import TapAsk

/// Real WebKit callbacks use no window, persistent login data, or network load.
final class NavigationDelegateTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testProgrammaticExternalNavigationIsCancelledByRealDelegate() async throws {
        let delegate = WebViewDelegate(policy: try SharedFixtures.chatGPTPolicy())
        let harness = NavigationHarness()
        let finished = expectation(description: "WebKit action cancelled")
        let webView = makeWebView(harness)
        harness.action = { action, handler in
            delegate.webView(webView, decidePolicyFor: action) { policy in
                XCTAssertEqual(policy, .cancel)
                handler(.cancel)
                finished.fulfill()
            }
        }
        webView.load(URLRequest(url: URL(string: "https://example.invalid/login")!))
        await fulfillment(of: [finished], timeout: 10)
        webView.stopLoading()
        withExtendedLifetime(harness) {}
    }

    @MainActor
    func testFinalExternalResponseIsCancelledByRealDelegate() async throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        let delegate = WebViewDelegate(policy: policy)
        let harness = NavigationHarness()
        let finished = expectation(description: "WebKit final response cancelled")
        let webView = makeWebView(harness)
        // The custom scheme supplies local bytes with an HTTPS response URL, so
        // cancellation must come from main-frame host trust, not the scheme check.
        // Bypass only the fixture action; any unexpected navigation stays offline.
        harness.action = { action, handler in
            XCTAssertEqual(action.request.url?.scheme, "fixture")
            handler(action.request.url?.scheme == "fixture" ? .allow : .cancel)
        }
        harness.response = { response, handler in
            XCTAssertEqual(response.response.url?.scheme, "https")
            XCTAssertEqual(response.response.url?.host, "example.invalid")
            XCTAssertFalse(policy.isPanelURL(response.response.url))
            XCTAssertTrue(response.isForMainFrame)
            XCTAssertTrue(response.canShowMIMEType)
            XCTAssertNil((response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition"))
            XCTAssertEqual(policy.response(url: response.response.url, mainFrame: false,
                                           canDisplay: true, attachment: false), .allow)
            delegate.webView(webView, decidePolicyFor: response) { result in
                XCTAssertEqual(result, .cancel)
                handler(.cancel)
                finished.fulfill()
            }
        }
        webView.load(URLRequest(url: URL(string: "fixture://example.invalid/login")!))
        await fulfillment(of: [finished], timeout: 10)
        webView.stopLoading()
        withExtendedLifetime(harness) {}
    }

    @MainActor
    func testWindowOpenToAllowedHostDoesNotNavigateMainWebView() async throws {
        let delegate = WebViewDelegate(policy: try SharedFixtures.chatGPTPolicy())
        let popupDelegate = WebViewDelegate(policy: try SharedFixtures.chatGPTPolicy(), isPopup: true)
        let harness = NavigationHarness()
        let popupHarness = NavigationHarness()
        let popupRequested = expectation(description: "Real window.open callback reached")
        let popupNavigation = expectation(description: "Popup receives its allowed navigation")
        let mainNavigation = expectation(description: "Main WebView must not navigate to the popup host")
        mainNavigation.isInverted = true
        let webView = makeWebView(harness, allowsAutomaticWindows: true, productionDelegate: delegate)
        var popupWebView: WKWebView?
        var mainNavigationHosts: [String] = []
        harness.action = { action, handler in
            if action.targetFrame?.isMainFrame == true,
               action.request.url?.host == "accounts.google.com" {
                mainNavigationHosts.append("accounts.google.com")
                mainNavigation.fulfill()
                handler(.cancel) // Observe the old implementation's load without making a network request.
            } else if action.targetFrame == nil {
                delegate.webView(webView, decidePolicyFor: action) { policy in
                    XCTAssertEqual(policy, .allow)
                    handler(policy)
                }
            } else {
                allowInMemoryHTMLOrPopup(action, handler: handler)
            }
        }
        harness.response = { response, handler in
            allowInMemoryHTMLResponse(response, handler: handler)
        }
        delegate.onCreatePopup = { configuration, url in
            XCTAssertEqual(url?.host, "accounts.google.com")
            let popup = popupDelegate.makeWebView(configuration: configuration)
            XCTAssertTrue(popup.navigationDelegate === popupDelegate)
            XCTAssertTrue(popup.uiDelegate === popupDelegate)
            XCTAssertTrue(popup.configuration.websiteDataStore === configuration.websiteDataStore)
            XCTAssertFalse(popup.customUserAgent?.isEmpty ?? true)
            XCTAssertEqual(popup.customUserAgent, webView.customUserAgent)
            popup.navigationDelegate = popupHarness
            popupWebView = popup
            return popup
        }
        popupHarness.action = { action, handler in
            guard let popup = popupWebView else {
                XCTFail("Popup must be retained before navigation")
                handler(.cancel)
                return
            }
            XCTAssertTrue(action.targetFrame?.isMainFrame == true)
            XCTAssertEqual(action.request.url?.host, "accounts.google.com")
            popupDelegate.webView(popup, decidePolicyFor: action) { policy in
                XCTAssertEqual(policy, .allow)
                handler(.cancel) // Even an allowed popup request must never reach the network.
                popupNavigation.fulfill()
            }
        }
        harness.createWebView = { configuration, action, features in
            assertTrustedPopupSource(action)
            XCTAssertEqual(action.request.url?.host, "accounts.google.com")
            XCTAssertNil(action.targetFrame)
            let created = delegate.webView(webView, createWebViewWith: configuration,
                                           for: action, windowFeatures: features)
            XCTAssertNotNil(created)
            XCTAssertTrue(created === popupWebView)
            XCTAssertFalse(created === webView)
            popupRequested.fulfill()
            return created
        }
        defer {
            stop(webView)
            if let popupWebView { stop(popupWebView) }
            delegate.onCreatePopup = nil
        }
        loadWindowOpen(to: "https://accounts.google.com/fixture-login", in: webView)
        await fulfillment(of: [popupRequested, popupNavigation, mainNavigation], timeout: 3)
        XCTAssertTrue(mainNavigationHosts.isEmpty, "window.open must leave its opener in the main WebView")
        withExtendedLifetime((harness, popupHarness, popupDelegate)) {}
    }

    @MainActor
    func testWindowOpenToDisallowedHostReturnsNil() async throws {
        let delegate = WebViewDelegate(policy: try SharedFixtures.chatGPTPolicy())
        let harness = NavigationHarness()
        let popupRequested = expectation(description: "Disallowed window.open reaches the UI delegate")
        let webView = makeWebView(harness, allowsAutomaticWindows: true)
        var popupCreationCount = 0
        harness.action = { action, handler in
            allowInMemoryHTMLOrPopup(action, handler: handler)
        }
        harness.response = { response, handler in
            allowInMemoryHTMLResponse(response, handler: handler)
        }
        delegate.onCreatePopup = { _, _ in
            popupCreationCount += 1
            XCTFail("Disallowed window.open must not invoke the popup factory")
            return nil
        }
        harness.createWebView = { configuration, action, features in
            assertTrustedPopupSource(action)
            XCTAssertEqual(action.request.url?.host, "example.invalid")
            XCTAssertNil(action.targetFrame)
            let created = delegate.webView(webView, createWebViewWith: configuration,
                                           for: action, windowFeatures: features)
            XCTAssertNil(created)
            popupRequested.fulfill()
            return created
        }
        defer {
            stop(webView)
            delegate.onCreatePopup = nil
        }
        loadWindowOpen(to: "https://example.invalid/fixture-login", in: webView)
        await fulfillment(of: [popupRequested], timeout: 3)
        XCTAssertEqual(popupCreationCount, 0)
        withExtendedLifetime(harness) {}
    }

    @MainActor
    func testPopupMainPageNavigationToDisallowedHostIsCancelled() async throws {
        let delegate = WebViewDelegate(policy: try SharedFixtures.chatGPTPolicy())
        let popupDelegate = WebViewDelegate(policy: try SharedFixtures.chatGPTPolicy(), isPopup: true)
        let harness = NavigationHarness()
        let popupHarness = NavigationHarness()
        let popupRequested = expectation(description: "Allowed popup is created")
        let initialNavigation = expectation(description: "Popup receives its initial allowed request")
        let externalNavigation = expectation(description: "Popup's disallowed main-page request is cancelled")
        let webView = makeWebView(harness, allowsAutomaticWindows: true)
        var popupWebView: WKWebView?
        harness.action = { action, handler in
            allowInMemoryHTMLOrPopup(action, handler: handler)
        }
        harness.response = { response, handler in
            allowInMemoryHTMLResponse(response, handler: handler)
        }
        delegate.onCreatePopup = { configuration, _ in
            let popup = popupDelegate.makeWebView(configuration: configuration)
            popup.navigationDelegate = popupHarness
            popupWebView = popup
            return popup
        }
        harness.createWebView = { configuration, action, features in
            assertTrustedPopupSource(action)
            let created = delegate.webView(webView, createWebViewWith: configuration,
                                           for: action, windowFeatures: features)
            XCTAssertNotNil(created)
            popupRequested.fulfill()
            return created
        }
        popupHarness.action = { action, handler in
            guard let popup = popupWebView else {
                XCTFail("Popup must be retained before navigation")
                handler(.cancel)
                return
            }
            XCTAssertTrue(action.targetFrame?.isMainFrame == true)
            popupDelegate.webView(popup, decidePolicyFor: action) { policy in
                switch action.request.url?.host {
                case "accounts.google.com":
                    XCTAssertEqual(policy, .allow)
                    handler(.cancel)
                    initialNavigation.fulfill()
                    Task { @MainActor in
                        popup.load(URLRequest(url: URL(string: "https://example.invalid/login")!))
                    }
                case "example.invalid":
                    XCTAssertEqual(policy, .cancel)
                    handler(.cancel)
                    externalNavigation.fulfill()
                default:
                    XCTFail("Unexpected popup request: \(action.request.url?.host ?? "<none>")")
                    handler(.cancel)
                }
            }
        }
        defer {
            stop(webView)
            if let popupWebView { stop(popupWebView) }
            delegate.onCreatePopup = nil
        }
        loadWindowOpen(to: "https://accounts.google.com/fixture-login", in: webView)
        await fulfillment(of: [popupRequested, initialNavigation, externalNavigation], timeout: 3)
        withExtendedLifetime((harness, popupHarness, popupDelegate)) {}
    }

    @MainActor
    private func makeWebView(_ delegate: NavigationHarness, allowsAutomaticWindows: Bool = false,
                             productionDelegate: WebViewDelegate? = nil) -> WKWebView {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = allowsAutomaticWindows
        config.setURLSchemeHandler(ExternalHTTPSResponseFixture(), forURLScheme: "fixture")
        let webView = productionDelegate?.makeWebView(configuration: config)
            ?? WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        return webView
    }
}

@MainActor
private func allowInMemoryHTMLOrPopup(_ action: WKNavigationAction,
                                     handler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    // The base URL identifies loadHTMLString's local document. New-window actions
    // reach the UI delegate; the returned popup has its own cancelling proxy.
    let isLocalDocument = action.request.url?.absoluteString == "https://chatgpt.com/"
    handler(isLocalDocument || action.targetFrame == nil ? .allow : .cancel)
}

@MainActor
private func allowInMemoryHTMLResponse(_ response: WKNavigationResponse,
                                      handler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
    handler(response.response.url?.absoluteString == "https://chatgpt.com/" ? .allow : .cancel)
}

@MainActor
private func assertTrustedPopupSource(_ action: WKNavigationAction,
                                      file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(action.sourceFrame.request.url?.host, "chatgpt.com", file: file, line: line)
    XCTAssertEqual(action.sourceFrame.securityOrigin.protocol, "https", file: file, line: line)
    XCTAssertEqual(action.sourceFrame.securityOrigin.host, "chatgpt.com", file: file, line: line)
}

@MainActor
private func loadWindowOpen(to url: String, in webView: WKWebView) {
    // In-memory HTML has a trusted HTTPS origin and no remote resources.
    webView.loadHTMLString("""
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'">
        </head><body><script>
        window.open('\(url)', '_blank');
        </script></body></html>
        """, baseURL: URL(string: "https://chatgpt.com/")!)
}

@MainActor
private func stop(_ webView: WKWebView) {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
}

@MainActor
private final class NavigationHarness: NSObject, WKNavigationDelegate, WKUIDelegate {
    var action: ((WKNavigationAction, @escaping @MainActor (WKNavigationActionPolicy) -> Void) -> Void)?
    var response: ((WKNavigationResponse, @escaping @MainActor (WKNavigationResponsePolicy) -> Void) -> Void)?
    var createWebView: ((WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures) -> WKWebView?)?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if let action { action(navigationAction, decisionHandler) } else { decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if let response { response(navigationResponse, decisionHandler) } else { decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        createWebView?(configuration, navigationAction, windowFeatures)
    }
}

@MainActor
private final class ExternalHTTPSResponseFixture: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let data = Data("<html><body>Untrusted fixture</body></html>".utf8)
        urlSchemeTask.didReceive(URLResponse(url: URL(string: "https://example.invalid/login")!, mimeType: "text/html",
                                            expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

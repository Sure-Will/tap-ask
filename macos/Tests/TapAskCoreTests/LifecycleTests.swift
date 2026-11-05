import AppKit
import TapAskCore
import WebKit
import XCTest
@testable import TapAsk

/// Requires WindowServer/WebKit. Fixtures use only in-memory HTML and isolated stores/defaults.
final class LifecycleTests: XCTestCase {
    @MainActor
    func testCompletionButtonReleasesLoginPopupAndItsWebView() throws {
        try assertPopupReleased { _, popup in popup.completionButton.performClick(nil) }
    }

    @MainActor
    func testCloseButtonReleasesLoginPopupAndDetachesChildWindow() throws {
        try assertPopupReleased { _, popup in popup.panel.performClose(nil) }
    }

    @MainActor
    func testWebKitCloseCallbackReleasesLoginPopupAndDetachesChildWindow() throws {
        try assertPopupReleased { _, popup in
            // Exercise window.close()'s production delegate callback without injecting script.
            let delegate = try XCTUnwrap(popup.webView.uiDelegate as? WebViewDelegate)
            delegate.webViewDidClose(popup.webView)
        }
    }

    @MainActor
    func testReplacingLoginPopupReleasesPreviousPopupAndDetachesChildWindow() throws {
        let policy = NavigationPolicy(provider: try localCatalog().providers[0], identityHosts: [])
        try assertPopupReleased(expectReplacement: true) { owner, _ in
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let replacement = owner.openLoginPopup(configuration: configuration, policy: policy,
                                                   initialURL: URL(string: "about:blank"))
            loadLocalPage(replacement, provider: policy.provider)
        }
    }

    @MainActor
    func testRemovingVisibleAndCachedSessionsReleasesSessionWebViewAndDelegate() throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = try localCatalog()
        let owner = AppDelegate()
        owner.configurePanel(defaults: defaults)
        defer { owner.panel.orderOut(nil) }
        weak var cachedSession: ProviderSession?
        weak var cachedWebView: WKWebView?
        weak var cachedDelegate: WebViewDelegate?
        weak var visibleSession: ProviderSession?
        weak var visibleWebView: WKWebView?
        weak var visibleDelegate: WebViewDelegate?

        autoreleasepool {
            let background = ProviderSession(provider: catalog.providers[0], identityHosts: catalog.identityHosts,
                                             defaults: defaults, websiteDataStore: .nonPersistent())
            let visible = ProviderSession(provider: catalog.providers[1], identityHosts: catalog.identityHosts,
                                          defaults: defaults, websiteDataStore: .nonPersistent())
            cachedSession = background
            cachedWebView = background.webView
            cachedDelegate = background.webDelegate
            visibleSession = visible
            visibleWebView = visible.webView
            visibleDelegate = visible.webDelegate
            for session in [background, visible] {
                owner.displaySession(session)
                loadLocalPage(session.webView, provider: session.policy.provider)
            }
        }
        XCTAssertNotNil(cachedSession, "The production cache must own the background session before removal")
        XCTAssertNotNil(visibleSession)
        XCTAssertTrue(owner.panel.contentView === visibleWebView)
        autoreleasepool { owner.removeAllSessions() }
        advanceMainRunLoop(until: {
            cachedSession == nil && cachedWebView == nil && cachedDelegate == nil
                && visibleSession == nil && visibleWebView == nil && visibleDelegate == nil
        })
        XCTAssertNil(cachedSession)
        XCTAssertNil(cachedWebView)
        XCTAssertNil(cachedDelegate)
        XCTAssertNil(visibleSession)
        XCTAssertNil(visibleWebView)
        XCTAssertNil(visibleDelegate)
        XCTAssertNil(owner.panel.contentView)
        withExtendedLifetime(owner) {}
    }

    @MainActor
    func testLoadingOverlayReleasesDuringDelayAndCannotReappear() async throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let content = NSView()
        var panel: ChatPanel?
        weak var overlay: PageLoadOverlayView?
        try autoreleasepool {
            let created = ChatPanel(defaults: defaults)
            panel = created
            created.contentView = content
            overlay = try XCTUnwrap(content.subviews.compactMap { $0 as? PageLoadOverlayView }.first)
            created.updateLoadState(.loading, providerName: "Local fixture")
        }
        // Yield the main actor so the Task really enters its 400 ms wait. A nested
        // synchronous run loop alone need not service another main-actor job.
        let taskStarted = expectation(description: "Loading task had a main-actor turn")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { taskStarted.fulfill() }
        await fulfillment(of: [taskStarted], timeout: 0.3)
        XCTAssertEqual(overlay?.isHidden, true)
        autoreleasepool {
            panel?.contentView = nil // Production overlay removal in ChatPanel.installOverlays().
            panel = nil
        }
        XCTAssertNil(overlay, "The pending loading Task must not retain the removed overlay across its delay")
        XCTAssertTrue(content.subviews.isEmpty)
        let delayExpired = expectation(description: "Original loading delay expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { delayExpired.fulfill() }
        await fulfillment(of: [delayExpired], timeout: 1)
        XCTAssertNil(overlay)
        XCTAssertTrue(content.subviews.isEmpty, "A delayed task must not reattach/show the old prompt")
        withExtendedLifetime(content) {}
    }

    @MainActor
    func testClosingLoginPopupReleasesItAndItsOverlayDuringLoadingDelay() async throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = NavigationPolicy(provider: try localCatalog().providers[0], identityHosts: [])
        let owner = AppDelegate()
        owner.configurePanel(defaults: defaults)
        defer { owner.panel.orderOut(nil) }
        weak var popup: LoginPopup?
        weak var overlay: PageLoadOverlayView?
        weak var notice: NavigationNoticeView?
        weak var window: LoginPanel?
        try autoreleasepool {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let page = owner.openLoginPopup(configuration: configuration, policy: policy, initialURL: nil)
            popup = try XCTUnwrap(owner.loginPopup)
            window = popup?.panel
            overlay = try XCTUnwrap(page.subviews.compactMap { $0 as? PageLoadOverlayView }.first)
            notice = try XCTUnwrap(page.subviews.compactMap { $0 as? NavigationNoticeView }.first)
            let delegate = try XCTUnwrap(page.navigationDelegate as? WebViewDelegate)
            delegate.webView(page, didStartProvisionalNavigation: nil)
            delegate.onNavigationNotice?(try XCTUnwrap(navigationNotice(for: .action, mainFrame: true,
                decision: .cancel, host: "example.invalid", providerName: policy.provider.name)))
        }
        let taskStarted = expectation(description: "Popup loading task entered its delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { taskStarted.fulfill() }
        await fulfillment(of: [taskStarted], timeout: 0.3)
        XCTAssertEqual(overlay?.isHidden, true)
        XCTAssertEqual(notice?.isHidden, false)
        autoreleasepool { owner.closeLoginPopup(restoreFocus: false) }
        XCTAssertNil(popup, "Overlay callbacks must not retain the popup")
        XCTAssertNil(overlay, "The loading task must not retain the popup overlay during its delay")
        XCTAssertNil(notice, "The six-second dismissal must not retain the popup notice")
        XCTAssertNil(window, "Notice callbacks must not retain the login window")
        let delayExpired = expectation(description: "Popup loading delay expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { delayExpired.fulfill() }
        await fulfillment(of: [delayExpired], timeout: 1)
        XCTAssertNil(popup)
        XCTAssertNil(overlay)
        XCTAssertNil(owner.loginPopup)
        withExtendedLifetime(owner) {}
    }

    @MainActor
    func testNavigationNoticeReleasesWithMainWindowDuringDismissalDelay() async throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let content = NSView()
        var panel: ChatPanel?
        weak var window: ChatPanel?
        weak var notice: NavigationNoticeView?
        try autoreleasepool {
            let created = ChatPanel(defaults: defaults)
            panel = created
            window = created
            created.contentView = content
            notice = try XCTUnwrap(content.subviews.compactMap { $0 as? NavigationNoticeView }.first)
            created.showNavigationNotice(try XCTUnwrap(navigationNotice(for: .action, mainFrame: true,
                decision: .browser, host: "example.invalid", providerName: "ChatGPT")))
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(notice?.isHidden, false)
        autoreleasepool {
            panel?.contentView = nil
            panel = nil
        }
        advanceMainRunLoop(until: { window == nil && notice == nil })
        XCTAssertNil(window)
        XCTAssertNil(notice, "The dismissal task must hold the view weakly across the six-second wait")
        XCTAssertTrue(content.subviews.isEmpty)
        withExtendedLifetime(content) {}
    }

    @MainActor
    func testMenusDoNotKeepActionTargetAlive() throws {
        let providers = try localCatalog().providers
        let mainMenu = NSMenu()
        var statusMenu: NSMenu?
        weak var target: LifecycleMenuTarget?
        autoreleasepool {
            let owner = LifecycleMenuTarget()
            target = owner
            let action = #selector(LifecycleMenuTarget.performAction(_:))
            for item in makeProviderMenuItems(providers: providers, currentProviderID: providers[0].id,
                                              target: owner, action: action) {
                mainMenu.addItem(item)
            }
            let items = makeProviderMenuItems(providers: providers, currentProviderID: providers[0].id,
                                              target: owner, action: action)
            statusMenu = makeStatusMenu(isPanelVisible: true, providerItems: items, target: owner,
                                        toggleAction: action, orderAction: action, reloadAction: action)
            XCTAssertTrue(mainMenu.items.first?.target === owner)
            XCTAssertTrue(statusMenu?.items.first?.target === owner)
        }
        advanceMainRunLoop(until: { target == nil })
        XCTAssertNil(target)
        let status = try XCTUnwrap(statusMenu)
        let targetItems = (mainMenu.items + status.items).filter {
            $0.action == #selector(LifecycleMenuTarget.performAction(_:))
        }
        XCTAssertEqual(targetItems.count, providers.count * 2 + 3)
        for item in targetItems { XCTAssertNil(item.target) }
        withExtendedLifetime((mainMenu, status)) {}
    }

    @MainActor
    private func assertPopupReleased(expectReplacement: Bool = false,
                                     close: (AppDelegate, LoginPopup) throws -> Void,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = NavigationPolicy(provider: try localCatalog().providers[0], identityHosts: [])
        let owner = AppDelegate()
        owner.configurePanel(defaults: defaults)
        let parent = try XCTUnwrap(owner.panel)
        autoreleasepool {
            let session = ProviderSession(provider: policy.provider, identityHosts: [], defaults: defaults,
                                          websiteDataStore: .nonPersistent())
            owner.displaySession(session)
            loadLocalPage(session.webView, provider: policy.provider)
        }
        defer {
            owner.closeLoginPopup(restoreFocus: false)
            owner.removeAllSessions()
            parent.orderOut(nil)
        }
        weak var popup: LoginPopup?
        weak var window: LoginPanel?
        weak var webView: WKWebView?
        weak var delegate: WebViewDelegate?
        weak var overlay: PageLoadOverlayView?
        try autoreleasepool {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let page = owner.openLoginPopup(configuration: configuration, policy: policy,
                                            initialURL: URL(string: "about:blank"))
            let ownedPopup = try XCTUnwrap(owner.loginPopup)
            popup = ownedPopup
            window = ownedPopup.panel
            webView = page
            delegate = try XCTUnwrap(page.navigationDelegate as? WebViewDelegate)
            overlay = try XCTUnwrap(page.subviews.compactMap { $0 as? PageLoadOverlayView }.first)
            loadLocalPage(page, provider: policy.provider)
            ownedPopup.show(relativeTo: parent)
            XCTAssertTrue(parent.childWindows?.contains { $0 === ownedPopup.panel } == true, file: file, line: line)
            try close(owner, ownedPopup)
            XCTAssertFalse(parent.childWindows?.contains { $0 === ownedPopup.panel } == true, file: file, line: line)
            XCTAssertNil(ownedPopup.panel.parent, file: file, line: line)
            XCTAssertNil(ownedPopup.panel.contentView, file: file, line: line)
            XCTAssertNil(page.navigationDelegate, file: file, line: line)
            XCTAssertNil(page.uiDelegate, file: file, line: line)
            XCTAssertNil(delegate?.onLoadStateChange, file: file, line: line)
            XCTAssertNil(ownedPopup.onComplete, file: file, line: line)
            XCTAssertNil(ownedPopup.completionButton.target, file: file, line: line)
            XCTAssertNil(ownedPopup.completionButton.action, file: file, line: line)
            XCTAssertNil(overlay?.onRetry, file: file, line: line)
            XCTAssertNil(overlay?.superview, file: file, line: line)
        }
        advanceMainRunLoop(until: { popup == nil && window == nil && webView == nil && delegate == nil && overlay == nil })
        XCTAssertNil(popup, file: file, line: line)
        XCTAssertNil(window, file: file, line: line)
        XCTAssertNil(webView, file: file, line: line)
        XCTAssertNil(delegate, file: file, line: line)
        XCTAssertNil(overlay, file: file, line: line)
        if expectReplacement { XCTAssertNotNil(owner.loginPopup, file: file, line: line) }
        else { XCTAssertNil(owner.loginPopup, file: file, line: line) }
        withExtendedLifetime((owner, parent)) {}
    }

    private func localCatalog() throws -> ProviderCatalog {
        // Even a content-process termination can only retry about:blank, never a real provider.
        try JSONDecoder().decode(ProviderCatalog.self, from: Data("""
            {"identityHosts": [], "providers": [
              {"id": "local-one", "name": "Local One", "home": "about:blank", "hosts": ["one.invalid"]},
              {"id": "local-two", "name": "Local Two", "home": "about:blank", "hosts": ["two.invalid"]}
            ]}
            """.utf8))
    }

    @MainActor
    private func loadLocalPage(_ webView: WKWebView, provider: Provider) {
        // The allowed base URL identifies in-memory HTML; there are no remote resources or scripts.
        webView.loadHTMLString("<html><body>Lifecycle fixture</body></html>",
                               baseURL: URL(string: "https://\(provider.hosts[0])/"))
    }

    @MainActor
    private func advanceMainRunLoop(until condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            autoreleasepool {
                _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
    }
}

@MainActor
private final class LifecycleMenuTarget: NSObject {
    @objc func performAction(_ sender: Any?) {}
}

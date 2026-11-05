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
        let owner = AppDelegate(defaults: defaults, websiteDataStore: .nonPersistent())
        owner.configurePanel()
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
    func testReleaseOtherPagesReleasesTwoSessionsKeepsCurrentPopupAndAllowsRecreation() throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = try localCatalog()
        let store = WKWebsiteDataStore.nonPersistent()
        let owner = AppDelegate(catalog: catalog, defaults: defaults, websiteDataStore: store)
        owner.configurePanel()
        defer {
            owner.closeLoginPopup(restoreFocus: false)
            owner.removeAllSessions()
            owner.panel.orderOut(nil)
        }
        let releaseItem = NSMenuItem(title: "释放其他服务商页面",
                                     action: #selector(AppDelegate.releaseOtherProviderPages(_:)), keyEquivalent: "")
        XCTAssertFalse(owner.validateMenuItem(releaseItem))
        weak var first: ProviderSession?
        weak var second: ProviderSession?
        weak var current: ProviderSession?
        weak var firstPage: WKWebView?
        weak var secondPage: WKWebView?
        weak var currentPage: WKWebView?
        weak var firstDelegate: WebViewDelegate?
        weak var secondDelegate: WebViewDelegate?
        autoreleasepool {
            for (index, provider) in catalog.providers.enumerated() {
                let session = owner.makeSession(for: provider)
                owner.displaySession(session)
                loadLocalPage(session.webView, provider: provider)
                defaults.set("https://\(provider.hosts[0])/conversation/last", forKey: "LastPage.\(provider.id)")
                switch index {
                case 0:
                    first = session
                    firstPage = session.webView
                    firstDelegate = session.webDelegate
                case 1:
                    second = session
                    secondPage = session.webView
                    secondDelegate = session.webDelegate
                default:
                    current = session
                    currentPage = session.webView
                }
                XCTAssertEqual(owner.validateMenuItem(releaseItem), index > 0)
            }
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        _ = owner.openLoginPopup(configuration: configuration, policy: try XCTUnwrap(current).policy,
                                 initialURL: URL(string: "about:blank"))
        weak var popup: LoginPopup?
        weak var popupPage: WKWebView?
        autoreleasepool {
            popup = owner.loginPopup
            popupPage = owner.loginPopup?.webView
        }
        try autoreleasepool {
            let released = [try XCTUnwrap(first), try XCTUnwrap(second)]
            owner.releaseOtherProviderPages(nil)
            for session in released {
                XCTAssertNil(session.onLoadStateChange)
                XCTAssertNil(session.onCommit)
                XCTAssertNil(session.webDelegate.onLoadStateChange)
                XCTAssertNil(session.webDelegate.onCommit)
                XCTAssertNil(session.webDelegate.onProcessTermination)
                XCTAssertNil(session.webDelegate.onNavigationNotice)
                XCTAssertNil(session.webDelegate.onCreatePopup)
                XCTAssertNil(session.webDelegate.onClose)
                XCTAssertNil(session.webView.navigationDelegate)
                XCTAssertNil(session.webView.uiDelegate)
            }
        }
        advanceMainRunLoop(until: {
            first == nil && second == nil && firstPage == nil && secondPage == nil
                && firstDelegate == nil && secondDelegate == nil
        })
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertNil(firstPage)
        XCTAssertNil(secondPage)
        XCTAssertNil(firstDelegate)
        XCTAssertNil(secondDelegate)
        XCTAssertNotNil(current)
        XCTAssertNotNil(currentPage)
        XCTAssertTrue(owner.currentSession === current)
        XCTAssertTrue(owner.panel.contentView === currentPage)
        XCTAssertTrue(currentPage?.navigationDelegate === current?.webDelegate)
        XCTAssertEqual(Array(owner.sessions.keys), [catalog.providers[2].id])
        XCTAssertNotNil(popup)
        XCTAssertNotNil(popupPage)
        XCTAssertTrue(owner.loginPopup === popup)
        XCTAssertNotNil(popupPage?.navigationDelegate)
        XCTAssertFalse(owner.validateMenuItem(releaseItem))
        for provider in catalog.providers {
            XCTAssertEqual(defaults.string(forKey: "LastPage.\(provider.id)"),
                           "https://\(provider.hosts[0])/conversation/last")
        }

        owner.switchProvider(to: catalog.providers[0])
        let recreated = try XCTUnwrap(owner.sessions[catalog.providers[0].id])
        XCTAssertTrue(owner.currentSession === recreated)
        XCTAssertTrue(owner.panel.contentView === recreated.webView)
        XCTAssertTrue(recreated.webView.configuration.websiteDataStore === store)
        XCTAssertTrue(recreated.webView.navigationDelegate === recreated.webDelegate)
        XCTAssertEqual(owner.sessions.count, 2)
        XCTAssertTrue(owner.validateMenuItem(releaseItem))
        XCTAssertNil(first, "The released session must not be resurrected")
    }

    @MainActor
    func testBackgroundTerminationWaitsForDisplayThenRestoresLastPageWithHomeFallback() async throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = try localCatalog(firstHome: "https://one.invalid/")
        let owner = AppDelegate(catalog: catalog, defaults: defaults, websiteDataStore: .nonPersistent())
        owner.configurePanel()
        defer {
            owner.removeAllSessions()
            owner.panel.orderOut(nil)
        }
        let background = owner.makeSession(for: catalog.providers[0])
        let current = owner.makeSession(for: catalog.providers[1])
        let lastPage = "https://one.invalid/conversation/last"
        defaults.set(lastPage, forKey: "LastPage.local-one")
        owner.displaySession(background)
        background.webDelegate.webView(background.webView, didCommit: nil)
        owner.displaySession(current)
        current.webDelegate.webView(current.webView, didCommit: nil)
        let overlay = try XCTUnwrap(current.webView.subviews.compactMap { $0 as? PageLoadOverlayView }.first)
        let observer = LifecycleNavigationObserver()
        background.webView.navigationDelegate = observer
        let premature = expectation(description: "Background termination must not load")
        premature.isInverted = true
        let restored = expectation(description: "Displaying the terminated session restores LastPage")
        let fallback = expectation(description: "Restore failure loads home once")
        let duplicate = expectation(description: "No duplicate reload or repeated fallback")
        duplicate.isInverted = true
        var displayAllowed = false
        var requests: [URLRequest] = []
        observer.onRequest = { request in
            requests.append(request)
            if !displayAllowed { premature.fulfill() }
            background.webDelegate.webView(background.webView, didStartProvisionalNavigation: nil)
            switch requests.count {
            case 1: restored.fulfill()
            case 2: fallback.fulfill()
            default: duplicate.fulfill()
            }
        }
        XCTAssertNil(background.webView.url, "Simulate termination before WebKit retains a usable URL")
        background.webDelegate.webViewWebContentProcessDidTerminate(background.webView)
        XCTAssertTrue(background.needsReloadOnDisplay)
        XCTAssertEqual(background.loadState, .loading)
        XCTAssertFalse(background.webView.isLoading)
        await fulfillment(of: [premature], timeout: 0.5)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(overlay.isHidden, "A background crash must not change the current page's overlay")
        XCTAssertEqual(current.loadState, .loaded)

        displayAllowed = true
        owner.switchProvider(to: catalog.providers[0])
        XCTAssertFalse(background.needsReloadOnDisplay)
        await fulfillment(of: [restored], timeout: 3)
        XCTAssertEqual(requests.compactMap(\.url), [URL(string: lastPage)!])
        XCTAssertEqual(requests.first?.timeoutInterval, 20)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(overlay.superview === background.webView)
        XCTAssertFalse(overlay.isHidden, "The newly displayed page must show its normal loading overlay")
        owner.switchProvider(to: catalog.providers[1])
        owner.switchProvider(to: catalog.providers[0])
        XCTAssertEqual(requests.count, 1)

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        background.webDelegate.webView(background.webView, didFailProvisionalNavigation: nil, withError: error)
        await fulfillment(of: [fallback], timeout: 3)
        XCTAssertEqual(requests.compactMap(\.url), [URL(string: lastPage)!, catalog.providers[0].home])
        background.webDelegate.webView(background.webView, didFailProvisionalNavigation: nil, withError: error)
        XCTAssertEqual(background.loadState, .failed(PageLoadFailure(domain: error.domain, code: error.code)))
        await fulfillment(of: [duplicate], timeout: 0.2)
        XCTAssertEqual(defaults.string(forKey: "LastPage.local-one"), lastPage)
        withExtendedLifetime(observer) {}
    }

    @MainActor
    func testHiddenCurrentSessionRecoversWhenMainWindowIsReopened() async throws {
        _ = NSApplication.shared
        let suite = "TapAsk.LifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = try localCatalog()
        let owner = AppDelegate(catalog: catalog, defaults: defaults, websiteDataStore: .nonPersistent())
        owner.configurePanel()
        defer {
            owner.removeAllSessions()
            owner.panel.orderOut(nil)
        }
        let session = owner.makeSession(for: catalog.providers[0])
        owner.displaySession(session)
        let observer = LifecycleNavigationObserver()
        session.webView.navigationDelegate = observer
        let restored = expectation(description: "Reopening a hidden window recovers its terminated page")
        observer.onRequest = { request in
            XCTAssertEqual(request.url, catalog.providers[0].home)
            restored.fulfill()
        }
        XCTAssertFalse(owner.panel.isVisible)
        session.webDelegate.webViewWebContentProcessDidTerminate(session.webView)
        XCTAssertTrue(session.needsReloadOnDisplay)
        XCTAssertFalse(session.webView.isLoading)
        XCTAssertFalse(owner.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertFalse(session.needsReloadOnDisplay)
        await fulfillment(of: [restored], timeout: 3)
        withExtendedLifetime(observer) {}
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
        let owner = AppDelegate(defaults: defaults, websiteDataStore: .nonPersistent())
        owner.configurePanel()
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
                                        toggleAction: action, orderAction: action, reloadAction: action,
                                        releaseOthersAction: action)
            XCTAssertTrue(mainMenu.items.first?.target === owner)
            XCTAssertTrue(statusMenu?.items.first?.target === owner)
        }
        advanceMainRunLoop(until: { target == nil })
        XCTAssertNil(target)
        let status = try XCTUnwrap(statusMenu)
        let targetItems = (mainMenu.items + status.items).filter {
            $0.action == #selector(LifecycleMenuTarget.performAction(_:))
        }
        XCTAssertEqual(targetItems.count, providers.count * 2 + 4)
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
        let owner = AppDelegate(defaults: defaults, websiteDataStore: .nonPersistent())
        owner.configurePanel()
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

    private func localCatalog(firstHome: String = "about:blank") throws -> ProviderCatalog {
        // Recovery tests intercept requests; ordinary fixtures can only retry about:blank.
        try JSONDecoder().decode(ProviderCatalog.self, from: Data("""
            {"identityHosts": [], "providers": [
              {"id": "local-one", "name": "Local One", "home": "\(firstHome)", "hosts": ["one.invalid"]},
              {"id": "local-two", "name": "Local Two", "home": "about:blank", "hosts": ["two.invalid"]},
              {"id": "local-three", "name": "Local Three", "home": "about:blank", "hosts": ["three.invalid"]}
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

@MainActor
private final class LifecycleNavigationObserver: NSObject, WKNavigationDelegate {
    var onRequest: ((URLRequest) -> Void)?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.cancel) // Inspect recovery without contacting any host.
        onRequest?(navigationAction.request)
    }
}

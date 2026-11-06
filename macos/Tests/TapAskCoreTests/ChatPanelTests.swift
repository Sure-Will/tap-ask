import AppKit
import TapAskCore
import WebKit
import XCTest
@testable import TapAsk

/// Requires WindowServer. No page is loaded and no JavaScript is injected.
final class ChatPanelTests: XCTestCase {
    @MainActor
    func testLoginPopupToolbarFitsWithoutIncreasingWindowHeight() throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let popup = LoginPopup(configuration: configuration, policy: try SharedFixtures.chatGPTPolicy(),
                               initialURL: URL(string: "https://accounts.google.com/login"))
        defer { popup.dispose() }
        XCTAssertEqual(popup.panel.frame.size, LoginPanel.initialSize)
        let content = try XCTUnwrap(popup.panel.contentView)
        let toolbar = try XCTUnwrap(popup.completionButton.superview)
        for size in [LoginPanel.initialSize, NSSize(width: 360, height: 480)] {
            popup.panel.setFrame(NSRect(origin: .zero, size: size), display: false)
            content.layoutSubtreeIfNeeded()
            XCTAssertEqual(popup.panel.frame.size, size)
            XCTAssertEqual(toolbar.frame.height, 36, accuracy: 0.5)
            XCTAssertEqual(toolbar.frame.minY, content.bounds.minY, accuracy: 0.5)
            XCTAssertEqual(popup.webView.frame.minY, toolbar.frame.maxY, accuracy: 0.5)
            XCTAssertEqual(popup.webView.frame.maxY, content.bounds.maxY, accuracy: 0.5)
            XCTAssertEqual(popup.webView.frame.width, content.bounds.width, accuracy: 0.5)
            XCTAssertTrue(toolbar.bounds.contains(popup.completionButton.frame))
            XCTAssertGreaterThanOrEqual(popup.completionButton.frame.width,
                                       popup.completionButton.intrinsicContentSize.width)
            XCTAssertLessThanOrEqual(popup.hostLabel.frame.maxX, popup.completionButton.frame.minX - 12)
            XCTAssertEqual(popup.completionButton.keyEquivalent, "", "Return must remain available to the login form")
        }
    }

    @MainActor
    func testLoginPopupHostLabelFollowsCommittedNavigation() throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let popup = LoginPopup(configuration: configuration, policy: try SharedFixtures.chatGPTPolicy(),
                               initialURL: URL(string: "https://accounts.google.com/login?state=fixture"))
        defer { popup.dispose() }
        XCTAssertEqual(popup.hostLabel.stringValue, "accounts.google.com")
        let delegate = try XCTUnwrap(popup.webView.navigationDelegate as? WebViewDelegate)
        delegate.onCommit?(URL(string: "https://chatgpt.com/callback?code=fixture"))
        XCTAssertEqual(popup.hostLabel.stringValue, "chatgpt.com")
        XCTAssertEqual(popup.hostLabel.toolTip, "chatgpt.com")
        delegate.onCommit?(nil)
        XCTAssertEqual(popup.hostLabel.stringValue, "")
        XCTAssertNil(popup.hostLabel.toolTip)
    }

    @MainActor
    func testLoginPopupIsPlacedInsideParentScreenAndFocusIsRetriedNextTurn() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else {
            throw XCTSkip("Requires a WindowServer screen for native placement and key-window focus")
        }
        let parent = NSWindow(contentRect: NSRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY,
                                                  width: 480, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let popup = LoginPopup(configuration: configuration, policy: try SharedFixtures.chatGPTPolicy(), initialURL: nil)
        defer { popup.dispose() }
        let parentFrame = parent.frame

        popup.show(relativeTo: parent)
        XCTAssertTrue(screen.visibleFrame.contains(popup.panel.frame))
        XCTAssertEqual(parent.frame, parentFrame, "Presenting the popup must not reposition its parent")
        XCTAssertTrue(popup.panel.firstResponder === popup.webView)
        // Reproduce losing key status during activation before the queued repair.
        popup.panel.resignKey()
        popup.panel.makeFirstResponder(nil)
        XCTAssertFalse(popup.panel.isKeyWindow)
        XCTAssertFalse(popup.panel.firstResponder === popup.webView)
        let nextTurn = expectation(description: "Popup focus repair has run")
        DispatchQueue.main.async { nextTurn.fulfill() }
        await fulfillment(of: [nextTurn], timeout: 1)
        XCTAssertTrue(popup.panel.firstResponder === popup.webView)

        // The repair is one-shot, not a loop that can steal later focus.
        popup.panel.makeFirstResponder(nil)
        let laterTurn = expectation(description: "No second focus repair")
        DispatchQueue.main.async { laterTurn.fulfill() }
        await fulfillment(of: [laterTurn], timeout: 1)
        XCTAssertFalse(popup.panel.firstResponder === popup.webView)
    }

    @MainActor
    func testLoginPopupFocusRetryCannotReshowHiddenOrDisposedWindow() async throws {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        for closePopup in [false, true] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let popup = LoginPopup(configuration: configuration, policy: try SharedFixtures.chatGPTPolicy(), initialURL: nil)
            popup.show(relativeTo: parent)
            if closePopup { popup.dispose() }
            else { popup.hide() }
            let nextTurn = expectation(description: "Hidden popup skips focus repair")
            DispatchQueue.main.async { nextTurn.fulfill() }
            await fulfillment(of: [nextTurn], timeout: 1)
            XCTAssertFalse(popup.panel.isVisible)
            if closePopup {
                XCTAssertNil(popup.panel.contentView)
                XCTAssertNil(popup.panel.onUserAdjustFrame)
            } else {
                popup.dispose()
            }
        }
    }

    @MainActor
    func testLoginPanelDistinguishesUserAdjustmentFromProgrammaticFrameChanges() {
        _ = NSApplication.shared
        let parent = LoginPanel()
        let popup = LoginPanel()
        defer {
            parent.removeChildWindow(popup)
            popup.close()
            parent.close()
        }
        var userAdjustments = 0
        popup.onUserAdjustFrame = { userAdjustments += 1 }
        parent.addChildWindow(popup, ordered: .above)
        popup.orderFront(nil)
        popup.setFrame(NSRect(x: 200, y: 200, width: 400, height: 500), display: false)
        parent.setFrameOrigin(NSPoint(x: 300, y: 300))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: popup)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: popup)
        XCTAssertEqual(userAdjustments, 0)
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: popup)
        XCTAssertEqual(userAdjustments, 1)
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: popup)
        XCTAssertEqual(userAdjustments, 2)
    }

    @MainActor
    func testLoginPopupFailureUsesSharedOverlayAndOnlyOffersSafeRetry() throws {
        _ = NSApplication.shared
        let policy = try SharedFixtures.chatGPTPolicy()
        let cases: [(URL?, Bool)] = [(URL(string: "https://accounts.google.com/login"), true),
                                    (nil, false), (URL(string: "https://example.invalid/login"), false)]
        for (initialURL, canRetry) in cases {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let popup = LoginPopup(configuration: configuration, policy: policy, initialURL: initialURL)
            defer { popup.dispose() }
            let delegate = try XCTUnwrap(popup.webView.navigationDelegate as? WebViewDelegate)
            let overlay = try XCTUnwrap(popup.webView.subviews.first { $0 is PageLoadOverlayView })
            let stack = try XCTUnwrap(overlay.subviews.first as? NSStackView)
            let labels = stack.views.compactMap { $0 as? NSTextField }
            let retry = try XCTUnwrap(stack.views.compactMap { $0 as? NSButton }.first)
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            delegate.webView(popup.webView, didStartProvisionalNavigation: nil)
            delegate.webView(popup.webView, didFailProvisionalNavigation: nil, withError: error)
            XCTAssertFalse(overlay.isHidden)
            XCTAssertTrue(labels.contains { $0.stringValue == "登录页打不开" })
            let reason = "没有网络连接" + (canRetry ? "" : "，请关闭后重新登录")
            XCTAssertTrue(labels.contains { $0.stringValue == reason })
            XCTAssertEqual(retry.isHidden, !canRetry)
            for size in [NSSize(width: 480, height: 640), NSSize(width: 360, height: 480)] {
                popup.panel.setContentSize(size)
                popup.webView.layoutSubtreeIfNeeded()
                XCTAssertTrue(popup.webView.bounds.contains(overlay.frame), "The prompt must fit the login window")
            }

            delegate.webView(popup.webView, didStartProvisionalNavigation: nil)
            delegate.webView(popup.webView, didCommit: nil)
            delegate.webView(popup.webView, didStartProvisionalNavigation: nil)
            delegate.webView(popup.webView, didFailProvisionalNavigation: nil, withError: error)
            delegate.webView(popup.webView, didFail: nil, withError: error)
            XCTAssertTrue(overlay.isHidden, "Failures after commit must leave the login document visible")
        }
    }

    @MainActor
    func testLoginPopupShowsDelayedLoadingPromptAndHidesItOnCommit() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let popup = LoginPopup(configuration: configuration, policy: try SharedFixtures.chatGPTPolicy(),
                               initialURL: URL(string: "https://accounts.google.com/login"))
        defer { popup.dispose() }
        let delegate = try XCTUnwrap(popup.webView.navigationDelegate as? WebViewDelegate)
        let overlay = try XCTUnwrap(popup.webView.subviews.first { $0 is PageLoadOverlayView })
        delegate.webView(popup.webView, didStartProvisionalNavigation: nil)
        XCTAssertTrue(overlay.isHidden)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(overlay.isHidden)
        let stack = try XCTUnwrap(overlay.subviews.first as? NSStackView)
        XCTAssertTrue(stack.views.compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == "正在打开登录页…" })
        XCTAssertFalse(try XCTUnwrap(stack.views.compactMap { $0 as? NSProgressIndicator }.first).isHidden)
        XCTAssertTrue(try XCTUnwrap(stack.views.compactMap { $0 as? NSButton }.first).isHidden)
        delegate.webView(popup.webView, didCommit: nil)
        XCTAssertTrue(overlay.isHidden)
    }

    @MainActor
    func testDragOverlayPaintsOnlyTheWhiteHandleOnTransparentPixels() throws {
        let strip = PanelDragView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        do {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            NSColor.clear.setFill()
            strip.bounds.fill(using: .copy)
            strip.draw(strip.bounds)
        }
        let corner = try XCTUnwrap(bitmap.colorAt(x: 2, y: 2))
        let center = try XCTUnwrap(bitmap.colorAt(x: 60, y: 12)?.usingColorSpace(.sRGB))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.001)
        XCTAssertGreaterThan(center.alphaComponent, 0.8)
        XCTAssertGreaterThan(center.redComponent, 0.9)
        XCTAssertGreaterThan(center.greenComponent, 0.9)
        XCTAssertGreaterThan(center.blueComponent, 0.9)
        XCTAssertFalse(strip.isOpaque)
    }

    @MainActor
    func testTransparentDragOverlayKeepsWebViewFullSizeAndPassesSurroundingClicksThrough() throws {
        _ = NSApplication.shared
        let suite = "TapAsk.ChatPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = ChatPanel(defaults: defaults)
        defer { panel.orderOut(nil) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        panel.pageView = webView
        panel.orderFront(nil)
        panel.showNavigationNotice(try XCTUnwrap(navigationNotice(for: .action, mainFrame: true,
            decision: .cancel, host: "example.invalid", providerName: "ChatGPT")))
        let notice = try XCTUnwrap(webView.subviews.compactMap { $0 as? NavigationNoticeView }.first)
        let badge = try XCTUnwrap(webView.subviews.compactMap { $0 as? OriginBadgeView }.first)

        for size in [NSSize(width: 480, height: 720), NSSize(width: 360, height: 720),
                     NSSize(width: 480, height: 480), NSSize(width: 360, height: 480)] {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
            for origin in ["", "https://accounts.google.com"] {
                panel.origin = origin
                let frameView = try XCTUnwrap(panel.contentView?.superview)
                frameView.layoutSubtreeIfNeeded()
                let content = try XCTUnwrap(panel.contentView)
                let dragStrip = try XCTUnwrap(content.subviews.compactMap { $0 as? PanelDragView }.first)
                XCTAssertTrue(webView.superview === content)
                XCTAssertEqual(webView.frame, content.bounds)
                XCTAssertEqual(dragStrip.frame.maxY, content.bounds.maxY, accuracy: 0.5)
                XCTAssertEqual(dragStrip.frame.height, 24, accuracy: 0.5)
                XCTAssertEqual(dragStrip.handleRect.size, NSSize(width: 36, height: 4))
                XCTAssertEqual(dragStrip.handleRect.midX, dragStrip.bounds.midX, accuracy: 0.5)
                XCTAssertEqual(dragStrip.handleRect.midY, dragStrip.bounds.midY, accuracy: 0.5)
                XCTAssertFalse(dragStrip.isOpaque)
                XCTAssertFalse(notice.isHidden)
                XCTAssertTrue(webView.bounds.contains(notice.frame))
                XCTAssertEqual(notice.frame.midX, webView.bounds.midX, accuracy: 0.5)
                let noticeTop = webView.isFlipped ? notice.frame.minY : webView.bounds.maxY - notice.frame.maxY
                let badgeTop = webView.isFlipped ? badge.frame.minY : webView.bounds.maxY - badge.frame.maxY
                let badgeBottom = webView.isFlipped ? badge.frame.maxY : webView.bounds.maxY - badge.frame.minY
                if !origin.isEmpty { XCTAssertEqual(badgeTop, 28, accuracy: 0.5) }
                XCTAssertEqual(noticeTop, origin.isEmpty ? 28 : badgeBottom + 6, accuracy: 0.5)
                // Probe away from the handle's intentional drag target.
                let noticePoint = frameView.convert(NSPoint(x: notice.bounds.minX + 4, y: notice.bounds.midY), from: notice)
                let noticeHit = frameView.hitTest(noticePoint)
                XCTAssertTrue(noticeHit === webView || noticeHit?.isDescendant(of: webView) == true)
                XCTAssertFalse(noticeHit === notice || noticeHit?.isDescendant(of: notice) == true)
                // Only the small rectangle around the handle captures clicks.
                // The outermost point remains the native window's resize edge.
                XCTAssertFalse(frameView.hitTest(point(atDepth: 1, in: frameView)) is PanelDragView)
                for depth: CGFloat in [23, 28, 44] {
                    let hit = frameView.hitTest(point(atDepth: depth, in: frameView))
                    XCTAssertTrue(hit === webView || hit?.isDescendant(of: webView) == true,
                                  "Top \(depth)pt hit \(String(describing: hit)); must reach WKWebView")
                    XCTAssertFalse(hit is PanelDragView)
                    XCTAssertFalse(hit is OriginBadgeView)
                    XCTAssertFalse(hit is NavigationNoticeView)
                }
                for depth: CGFloat in [4, 12, 20] {
                    let drag = frameView.hitTest(point(atDepth: depth, in: frameView))
                    XCTAssertTrue(drag === dragStrip)
                    XCTAssertEqual(drag?.mouseDownCanMoveWindow, true)
                }
                for offset: CGFloat in [-31, -29, 29, 31] {
                    var point = point(atDepth: 12, in: frameView)
                    point.x += offset
                    let hit = frameView.hitTest(point)
                    if abs(offset) < 30 { XCTAssertTrue(hit === dragStrip) }
                    else { XCTAssertTrue(hit === webView || hit?.isDescendant(of: webView) == true) }
                }
                for x: CGFloat in [24, frameView.bounds.width - 24] {
                    var point = point(atDepth: 12, in: frameView)
                    point.x = x
                    let hit = frameView.hitTest(point)
                    XCTAssertTrue(hit === webView || hit?.isDescendant(of: webView) == true)
                    XCTAssertFalse(hit is PanelDragView)
                }
            }
        }
    }

    @MainActor
    func testProviderContentReplacementMovesOverlaysAndOriginPassesThroughClicks() throws {
        _ = NSApplication.shared
        let suite = "TapAsk.ChatPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = ChatPanel(defaults: defaults)
        defer { panel.orderOut(nil) }
        let previous = NSView()
        let current = NSView()
        panel.pageView = previous
        panel.showNavigationNotice(try XCTUnwrap(navigationNotice(for: .action, mainFrame: true,
            decision: .browser, host: "example.invalid", providerName: "ChatGPT")))
        panel.origin = "https://accounts.google.com"
        panel.updateLoadState(.failed(PageLoadFailure(domain: "NSURLErrorDomain", code: -1001)),
                              providerName: "ChatGPT")
        panel.pageView = current
        let badge = try XCTUnwrap(current.subviews.first { $0 is OriginBadgeView } as? OriginBadgeView)
        let loadOverlay = try XCTUnwrap(current.subviews.first { $0 is PageLoadOverlayView })
        current.layoutSubtreeIfNeeded()
        XCTAssertTrue(previous.subviews.isEmpty)
        XCTAssertNil(previous.superview)
        let content = try XCTUnwrap(panel.contentView)
        XCTAssertTrue(current.superview === content)
        XCTAssertEqual(content.subviews.filter { $0 is PanelDragView }.count, 1)
        XCTAssertFalse(current.subviews.contains { $0 is PanelDragView })
        XCTAssertEqual(current.subviews.filter { $0 is PageLoadOverlayView }.count, 1)
        let notice = try XCTUnwrap(current.subviews.compactMap { $0 as? NavigationNoticeView }.first)
        XCTAssertTrue(notice.isHidden, "A provider switch must clear the previous page's notice")
        XCTAssertFalse(loadOverlay.isHidden)
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(badge.origin, panel.origin)
        XCTAssertNil(badge.hitTest(NSPoint(x: badge.frame.midX, y: badge.frame.midY)))
        panel.origin = ""
        XCTAssertTrue(badge.isHidden)

        panel.setFrame(NSRect(x: 80, y: 90, width: 400, height: 600), display: false)
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        XCTAssertEqual(defaults.string(forKey: "PanelFrame"), NSStringFromRect(panel.frame))
        panel.pageView = nil
        XCTAssertNil(panel.pageView)
        XCTAssertTrue(panel.contentView === content)
        XCTAssertNil(current.superview)
        XCTAssertTrue(current.subviews.isEmpty)
        XCTAssertEqual(content.subviews.count, 1)
        XCTAssertTrue(content.subviews.first is PanelDragView)
    }

    @MainActor
    func testFailureRetryReceivesClicksAndLoadedOverlayPassesThroughTopAndCenter() throws {
        _ = NSApplication.shared
        let suite = "TapAsk.ChatPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = ChatPanel(defaults: defaults)
        defer { panel.orderOut(nil) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        panel.pageView = webView
        panel.orderFront(nil)
        let frameView = try XCTUnwrap(webView.superview)
        let overlay = try XCTUnwrap(webView.subviews.first { $0 is PageLoadOverlayView })
        var retries = 0
        panel.onRetry = { retries += 1 }

        for size in [NSSize(width: 480, height: 720), NSSize(width: 360, height: 480)] {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
            panel.updateLoadState(.failed(PageLoadFailure(domain: "NSURLErrorDomain", code: -1001)),
                                  providerName: "ChatGPT")
            frameView.layoutSubtreeIfNeeded()
            XCTAssertFalse(overlay.isHidden)
            let stack = try XCTUnwrap(overlay.subviews.first as? NSStackView)
            let retry = try XCTUnwrap(stack.views.compactMap { $0 as? NSButton }.first)
            let retryPoint = frameView.convert(NSPoint(x: retry.bounds.midX, y: retry.bounds.midY), from: retry)
            let hit = frameView.hitTest(retryPoint)
            XCTAssertTrue(hit === retry || hit?.isDescendant(of: retry) == true,
                          "Retry hit \(String(describing: hit))")
            let previousRetries = retries
            retry.performClick(nil)
            XCTAssertEqual(retries, previousRetries + 1)

            panel.updateLoadState(.loaded, providerName: "ChatGPT")
            frameView.layoutSubtreeIfNeeded()
            XCTAssertTrue(overlay.isHidden)
            XCTAssertNil(overlay.hitTest(NSPoint(x: overlay.frame.midX, y: overlay.frame.midY)))
            for point in [point(atDepth: 25, in: frameView),
                          NSPoint(x: frameView.bounds.midX, y: frameView.bounds.midY)] {
                let hit = frameView.hitTest(point)
                XCTAssertTrue(hit === webView || hit?.isDescendant(of: webView) == true)
                XCTAssertFalse(hit === overlay || hit?.isDescendant(of: overlay) == true)
            }
        }
    }

    @MainActor
    func testLoadingPromptIsDelayedAndCancelledOnCommitOrProviderChange() async throws {
        let overlay = PageLoadOverlayView()
        overlay.update(.loading, providerName: "ChatGPT")
        XCTAssertTrue(overlay.isHidden)
        overlay.update(.loaded, providerName: "ChatGPT")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(overlay.isHidden, "A quick commit must cancel the pending loading prompt")

        overlay.update(.loading, providerName: "ChatGPT")
        overlay.update(.idle, providerName: "DeepSeek")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(overlay.isHidden, "The previous provider must not show its pending prompt")

        overlay.update(.loading, providerName: "DeepSeek")
        XCTAssertTrue(overlay.isHidden)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(overlay.isHidden)
        let stack = try XCTUnwrap(overlay.subviews.first as? NSStackView)
        XCTAssertTrue(stack.views.compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == "正在打开 DeepSeek…" })
        overlay.update(.loaded, providerName: "DeepSeek")
        XCTAssertTrue(overlay.isHidden)
    }

    @MainActor
    func testLoginPopupNavigationNoticeFitsAndPassesClicksThrough() throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let popup = LoginPopup(configuration: configuration, policy: try SharedFixtures.chatGPTPolicy(), initialURL: nil)
        defer { popup.dispose() }
        let delegate = try XCTUnwrap(popup.webView.navigationDelegate as? WebViewDelegate)
        let notice = try XCTUnwrap(popup.webView.subviews.compactMap { $0 as? NavigationNoticeView }.first)
        let message = try XCTUnwrap(navigationNotice(for: .response, mainFrame: true, decision: .cancel,
            host: "a-long-login-hostname.example.invalid", providerName: "ChatGPT"))
        delegate.onNavigationNotice?(message)
        for size in [NSSize(width: 480, height: 640), NSSize(width: 360, height: 640),
                     NSSize(width: 480, height: 480), NSSize(width: 360, height: 480)] {
            popup.panel.setContentSize(size)
            popup.webView.layoutSubtreeIfNeeded()
            XCTAssertFalse(notice.isHidden)
            XCTAssertTrue(popup.webView.bounds.contains(notice.frame))
            XCTAssertEqual(notice.frame.midX, popup.webView.bounds.midX, accuracy: 0.5)
            let top = popup.webView.isFlipped ? notice.frame.minY : popup.webView.bounds.maxY - notice.frame.maxY
            XCTAssertEqual(top, 10, accuracy: 0.5)
            let label = try XCTUnwrap(notice.subviews.first as? NSTextField)
            XCTAssertEqual(label.stringValue, message.message)
            XCTAssertGreaterThan(label.frame.height, 14, "The full message must wrap at narrow window widths")
            XCTAssertNil(notice.hitTest(NSPoint(x: notice.frame.midX, y: notice.frame.midY)))
            let frameView = try XCTUnwrap(popup.webView.superview)
            let point = frameView.convert(NSPoint(x: notice.bounds.midX, y: notice.bounds.midY), from: notice)
            let hit = frameView.hitTest(point)
            XCTAssertTrue(hit === popup.webView || hit?.isDescendant(of: popup.webView) == true)
            XCTAssertFalse(hit === notice || hit?.isDescendant(of: notice) == true)
        }
    }

    @MainActor
    func testNavigationNoticeReplacementGetsSixSecondsAndDuplicateDoesNotExtendIt() async throws {
        let view = NavigationNoticeView()
        let blocked = try XCTUnwrap(navigationNotice(for: .action, mainFrame: true, decision: .cancel,
                                                    host: "example.invalid", providerName: "ChatGPT"))
        let browser = try XCTUnwrap(navigationNotice(for: .action, mainFrame: true, decision: .browser,
                                                    host: "example.invalid", providerName: "ChatGPT"))
        view.show(blocked)
        XCTAssertFalse(view.isHidden)
        try await Task.sleep(for: .seconds(1))
        view.show(browser)
        try await Task.sleep(for: .milliseconds(5200))
        XCTAssertFalse(view.isHidden, "The first notice's timer must not dismiss its replacement")
        XCTAssertEqual((view.subviews.first as? NSTextField)?.stringValue, browser.message)
        view.show(browser)
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(view.isHidden, "A duplicate must not restart the six-second dismissal")
    }

    @MainActor
    private func point(atDepth depth: CGFloat, in view: NSView) -> NSPoint {
        NSPoint(x: view.bounds.midX,
                y: view.isFlipped ? view.bounds.minY + depth : view.bounds.maxY - depth)
    }
}

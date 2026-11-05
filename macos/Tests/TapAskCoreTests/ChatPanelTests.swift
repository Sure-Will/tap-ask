import AppKit
import TapAskCore
import WebKit
import XCTest
@testable import TapAsk

/// Requires WindowServer. No page is loaded and no JavaScript is injected.
final class ChatPanelTests: XCTestCase {
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
    func testTopClicksReachWebViewExceptEightPointDragStrip() throws {
        _ = NSApplication.shared
        let suite = "TapAsk.ChatPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = ChatPanel(defaults: defaults)
        defer { panel.orderOut(nil) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        panel.contentView = webView
        panel.orderFront(nil)

        for size in [NSSize(width: 480, height: 720), NSSize(width: 360, height: 720),
                     NSSize(width: 480, height: 480), NSSize(width: 360, height: 480)] {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
            for origin in ["", "https://accounts.google.com"] {
                panel.origin = origin
                let frameView = try XCTUnwrap(panel.contentView?.superview)
                frameView.layoutSubtreeIfNeeded()
                XCTAssertEqual(webView.frame, frameView.bounds)
                // Nine points is inside the top ten, immediately below the drag strip.
                for depth: CGFloat in [9, 20, 28] {
                    let hit = frameView.hitTest(point(atDepth: depth, in: frameView))
                    XCTAssertTrue(hit === webView || hit?.isDescendant(of: webView) == true,
                                  "Top \(depth)pt hit \(String(describing: hit)); must reach WKWebView")
                    XCTAssertFalse(hit is PanelDragView)
                    XCTAssertFalse(hit is OriginBadgeView)
                }
                let drag = frameView.hitTest(point(atDepth: 4, in: frameView))
                XCTAssertTrue(drag is PanelDragView)
                XCTAssertEqual(drag?.mouseDownCanMoveWindow, true)
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
        panel.contentView = previous
        panel.origin = "https://accounts.google.com"
        panel.updateLoadState(.failed(PageLoadFailure(domain: "NSURLErrorDomain", code: -1001)),
                              providerName: "ChatGPT")
        panel.contentView = current
        let badge = try XCTUnwrap(current.subviews.first { $0 is OriginBadgeView } as? OriginBadgeView)
        let loadOverlay = try XCTUnwrap(current.subviews.first { $0 is PageLoadOverlayView })
        current.layoutSubtreeIfNeeded()
        XCTAssertTrue(previous.subviews.isEmpty)
        XCTAssertEqual(current.subviews.filter { $0 is PanelDragView }.count, 1)
        XCTAssertEqual(current.subviews.filter { $0 is PageLoadOverlayView }.count, 1)
        XCTAssertFalse(loadOverlay.isHidden)
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(badge.origin, panel.origin)
        XCTAssertNil(badge.hitTest(NSPoint(x: badge.frame.midX, y: badge.frame.midY)))
        panel.origin = ""
        XCTAssertTrue(badge.isHidden)

        panel.setFrame(NSRect(x: 80, y: 90, width: 400, height: 600), display: false)
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        XCTAssertEqual(defaults.string(forKey: "PanelFrame"), NSStringFromRect(panel.frame))
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
        panel.contentView = webView
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
            for point in [point(atDepth: 9, in: frameView),
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
    private func point(atDepth depth: CGFloat, in view: NSView) -> NSPoint {
        NSPoint(x: view.bounds.midX,
                y: view.isFlipped ? view.bounds.minY + depth : view.bounds.maxY - depth)
    }
}

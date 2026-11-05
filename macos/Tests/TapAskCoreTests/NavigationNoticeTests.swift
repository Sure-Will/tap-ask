import Foundation
import TapAskCore
import XCTest

final class NavigationNoticeTests: XCTestCase {
    private let navigationEvents: [NavigationNoticeEvent] = [.action, .response, .redirect, .newWindow]

    func testEveryBlockedMainFramePathShowsHostAndProvider() throws {
        for event in navigationEvents {
            let notice = try XCTUnwrap(notice(event, .cancel))
            XCTAssertEqual(notice.kind, .blocked)
            XCTAssertEqual(notice.host, "example.invalid")
            XCTAssertEqual(notice.message, "已拦截 example.invalid：TapAsk 只在浮窗里打开 ChatGPT 和常见登录页")
        }
        XCTAssertEqual(notice(.redirect, .cancel, provider: "豆包")?.message,
                       "已拦截 example.invalid：TapAsk 只在浮窗里打开 豆包 和常见登录页")
    }

    func testClickedLinksAndNewWindowsHandedToBrowserShowHost() throws {
        for event: NavigationNoticeEvent in [.action, .newWindow] {
            let notice = try XCTUnwrap(notice(event, .browser))
            XCTAssertEqual(notice.kind, .browser)
            XCTAssertEqual(notice.message, "已在浏览器中打开 example.invalid")
        }
        for event: NavigationNoticeEvent in [.response, .redirect] {
            XCTAssertNil(notice(event, .browser), "Responses and redirects never open a browser")
        }
    }

    func testSubframesNeverShowNotices() {
        for event in navigationEvents {
            for decision: NavigationPolicy.Decision in [.allow, .cancel, .browser, .download] {
                XCTAssertNil(notice(event, decision, mainFrame: false))
            }
        }
    }

    func testFailuresAndNormalPopupCloseNeverShowNotices() {
        let events: [NavigationNoticeEvent] = [
            .failure(domain: "NSURLErrorDomain", code: -999),
            .failure(domain: "WebKitErrorDomain", code: 102),
            .failure(domain: "WebKitErrorDomain", code: 204),
            .failure(domain: "NSURLErrorDomain", code: -1001),
            .popupClosed,
        ]
        for event in events {
            for decision: NavigationPolicy.Decision in [.allow, .cancel, .browser, .download] {
                XCTAssertNil(notice(event, decision))
            }
        }
    }

    func testDownloadsStaySilentEvenWhenPolicyRejectsTheirSourceOrScheme() {
        for event in navigationEvents { XCTAssertNil(notice(event, .download)) }
        for decision: NavigationPolicy.Decision in [.allow, .cancel, .browser, .download] {
            XCTAssertNil(notice(.download, decision))
        }
    }

    func testAllowedNavigationAndProviderNewWindowInMainViewStaySilent() {
        for event in navigationEvents { XCTAssertNil(notice(event, .allow)) }
        XCTAssertNil(notice(.newWindow, .allow, host: "chatgpt.com"))
    }

    func testOnlyHostnameCanReachMessageOrDeduplicationKey() throws {
        let url = try XCTUnwrap(URL(string: "https://user:password@EXAMPLE.invalid:8443/oauth/callback?code=secret#token"))
        for decision: NavigationPolicy.Decision in [.cancel, .browser] {
            let result = try XCTUnwrap(notice(.action, decision, host: url.host))
            XCTAssertEqual(result.host, "example.invalid")
            for privatePart in ["https", "user", "password", "8443", "/oauth", "callback", "code", "secret", "token", "?", "#"] {
                XCTAssertFalse(result.message.contains(privatePart), privatePart)
            }
        }
        for host in [nil, "", url.absoluteString, "example.invalid/path", "example.invalid?code=secret",
                     "example.invalid#token", "user@example.invalid", "example.invalid\nsecret"] {
            XCTAssertNil(notice(.action, .cancel, host: host))
        }
    }

    func testDuplicateHostAndKindSuppressedUntilTenSecondsFromLastDisplay() throws {
        let action = try XCTUnwrap(notice(.action, .cancel, host: "EXAMPLE.invalid"))
        let redirect = try XCTUnwrap(notice(.redirect, .cancel))
        var state = nextNavigationNoticeState(from: NavigationNoticeState(), showing: action, at: 100)
        XCTAssertEqual(state.notice, action)
        for time in [100.0, 106, 109.999] {
            state = nextNavigationNoticeState(from: state, showing: redirect, at: time)
            XCTAssertNil(state.notice)
        }
        state = nextNavigationNoticeState(from: state, showing: redirect, at: 110)
        XCTAssertEqual(state.notice, redirect, "Suppression must not extend the ten-second interval")
        state = nextNavigationNoticeState(from: state, showing: action, at: 119.999)
        XCTAssertNil(state.notice)
    }

    func testOtherHostsAndKindsDoNotResetEarlierHostSuppression() throws {
        let blocked = try XCTUnwrap(notice(.action, .cancel))
        let browser = try XCTUnwrap(notice(.action, .browser))
        let otherHost = try XCTUnwrap(notice(.response, .cancel, host: "other.invalid"))
        var state = nextNavigationNoticeState(from: NavigationNoticeState(), showing: blocked, at: 0)
        state = nextNavigationNoticeState(from: state, showing: otherHost, at: 1)
        XCTAssertEqual(state.notice, otherHost)
        state = nextNavigationNoticeState(from: state, showing: browser, at: 2)
        XCTAssertEqual(state.notice, browser)
        state = nextNavigationNoticeState(from: state, showing: blocked, at: 3)
        XCTAssertNil(state.notice)
    }

    func testEachWindowHasIndependentHistoryAndProviderChangesDoNotBypassIt() throws {
        let blocked = try XCTUnwrap(notice(.action, .cancel))
        let main = nextNavigationNoticeState(from: NavigationNoticeState(), showing: blocked, at: 0)
        let popup = nextNavigationNoticeState(from: NavigationNoticeState(), showing: blocked, at: 1)
        XCTAssertEqual(main.notice, blocked)
        XCTAssertEqual(popup.notice, blocked)
        let otherProvider = try XCTUnwrap(notice(.newWindow, .cancel, provider: "Claude"))
        XCTAssertNil(nextNavigationNoticeState(from: main, showing: otherProvider, at: 2).notice)
    }

    private func notice(_ event: NavigationNoticeEvent, _ decision: NavigationPolicy.Decision,
                        mainFrame: Bool = true, host: String? = "example.invalid",
                        provider: String = "ChatGPT") -> NavigationNotice? {
        navigationNotice(for: event, mainFrame: mainFrame, decision: decision, host: host, providerName: provider)
    }
}

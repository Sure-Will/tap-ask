import Foundation
import TapAskCore
import XCTest

final class PageReloadTests: XCTestCase {
    func testCommandRTargetsTheKeyLoginPopup() {
        XCTAssertEqual(pageReloadTarget(isAppActive: true, isLoginPopupKeyWindow: true), .loginPopup)
    }

    func testCommandRTargetsTheProviderWhenTheMainWindowIsKey() {
        XCTAssertEqual(pageReloadTarget(isAppActive: true, isLoginPopupKeyWindow: false), .provider)
    }

    func testInactiveAppTargetsTheProviderEvenIfThePopupWasKey() {
        for popupIsKey in [false, true] {
            XCTAssertEqual(pageReloadTarget(isAppActive: false, isLoginPopupKeyWindow: popupIsKey), .provider)
        }
    }

    func testPopupRetryReturnsTheOriginalAllowedURL() throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        for host in ["accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "chatgpt.com"] {
            let initialURL = try XCTUnwrap(URL(string: "https://\(host)/authorize?state=fixture&client_id=test"))
            XCTAssertEqual(loginPopupRetryURL(initialURL: initialURL, policy: policy), initialURL)
            let request = try XCTUnwrap(loginPopupRetryRequest(initialURL: initialURL, policy: policy))
            XCTAssertEqual(request.url, initialURL)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.httpBodyStream)
        }
    }

    func testPopupRetryHasNoFallbackForMissingOrUntrustedInitialURL() throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        XCTAssertNil(loginPopupRetryURL(initialURL: nil, policy: policy))
        XCTAssertNil(loginPopupRetryRequest(initialURL: nil, policy: policy))
        for address in ["about:blank", "http://accounts.google.com/login", "https://example.invalid/login",
                        "https://accounts.google.com.example.invalid/login", "https://claude.ai/login",
                        "https://user:password@accounts.google.com/login", "https://accounts.google.com:8443/login"] {
            let initialURL = try XCTUnwrap(URL(string: address))
            XCTAssertNil(loginPopupRetryURL(initialURL: initialURL, policy: policy), address)
            XCTAssertNil(loginPopupRetryRequest(initialURL: initialURL, policy: policy), address)
        }
    }

    func testPopupRetryRechecksTheCurrentPolicy() throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        let initialURL = try XCTUnwrap(URL(string: "https://accounts.google.com/login"))
        XCTAssertEqual(loginPopupRetryURL(initialURL: initialURL, policy: policy), initialURL)
        let restrictedPolicy = NavigationPolicy(provider: policy.provider, identityHosts: [])
        XCTAssertNil(loginPopupRetryURL(initialURL: initialURL, policy: restrictedPolicy))
        XCTAssertNil(loginPopupRetryRequest(initialURL: initialURL, policy: restrictedPolicy))
    }
}

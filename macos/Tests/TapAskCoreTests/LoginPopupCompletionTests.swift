import Foundation
import TapAskCore
import XCTest

final class LoginPopupCompletionTests: XCTestCase {
    func testCompletionReloadsTheOpeningProviderWhenItIsDisplayed() {
        XCTAssertEqual(loginPopupCompletionReload(openingProviderID: "chatgpt", displayedProviderID: "chatgpt"),
                       .now(providerID: "chatgpt"))
    }

    func testCompletionDefersTheOpeningProviderAfterSwitching() {
        XCTAssertEqual(loginPopupCompletionReload(openingProviderID: "chatgpt", displayedProviderID: "claude"),
                       .onNextDisplay(providerID: "chatgpt"))
    }

    func testCompletionDefersWhenNoProviderIsDisplayed() {
        XCTAssertEqual(loginPopupCompletionReload(openingProviderID: "chatgpt", displayedProviderID: nil),
                       .onNextDisplay(providerID: "chatgpt"))
    }

    func testHostLabelContainsOnlyTheLowercaseHost() throws {
        let url = try XCTUnwrap(URL(string: "https://user:password@ACCOUNTS.Google.com:443/signin?code=private#token"))
        XCTAssertEqual(loginPopupHostLabel(for: url), "accounts.google.com")
        let providerURL = try XCTUnwrap(URL(string: "https://chatgpt.com/callback?host=other.invalid"))
        XCTAssertEqual(loginPopupHostLabel(for: providerURL), "chatgpt.com")
    }

    func testHostlessPagesHaveAnEmptyLabel() throws {
        XCTAssertEqual(loginPopupHostLabel(for: nil), "")
        for address in ["about:blank", "data:text/html,fixture", "/relative/path"] {
            XCTAssertEqual(loginPopupHostLabel(for: try XCTUnwrap(URL(string: address))), "")
        }
    }
}

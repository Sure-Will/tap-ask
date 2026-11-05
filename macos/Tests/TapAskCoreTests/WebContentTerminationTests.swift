import TapAskCore
import XCTest

final class WebContentTerminationTests: XCTestCase {
    func testLoginPopupReloadsEvenWhenHidden() {
        for isDisplayed in [false, true] {
            XCTAssertEqual(webContentTerminationAction(isMainWindow: false, isDisplayed: isDisplayed), .reloadNow)
        }
    }

    func testDisplayedProviderReloadsImmediately() {
        XCTAssertEqual(webContentTerminationAction(isMainWindow: true, isDisplayed: true), .reloadNow)
    }

    func testBackgroundProviderDefersUntilShown() {
        XCTAssertEqual(webContentTerminationAction(isMainWindow: true, isDisplayed: false), .deferUntilShown)
    }
}

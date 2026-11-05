import XCTest
import TapAskCore

final class PanelToggleTests: XCTestCase {
    func testHiddenPanelIsShown() {
        XCTAssertEqual(PanelToggle.action(isVisible: false), .show)
    }

    /// Visible but unfocused (another app is key) must hide on the first press.
    func testVisiblePanelIsHiddenOnFirstPress() {
        XCTAssertEqual(PanelToggle.action(isVisible: true), .hide)
    }
}

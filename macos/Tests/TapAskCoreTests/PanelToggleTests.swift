import XCTest
import TapAskCore

final class PanelToggleTests: XCTestCase {
    func testHiddenPanelIsShownWhenInactive() {
        XCTAssertEqual(PanelToggle.action(isVisible: false, isKeyAndActive: false), .show)
    }

    func testHiddenPanelIsShownEvenWithStaleActiveFlag() {
        XCTAssertEqual(PanelToggle.action(isVisible: false, isKeyAndActive: true), .show)
    }

    func testVisibleInactivePanelIsFocused() {
        XCTAssertEqual(PanelToggle.action(isVisible: true, isKeyAndActive: false), .focus)
    }

    func testVisibleActivePanelIsHidden() {
        XCTAssertEqual(PanelToggle.action(isVisible: true, isKeyAndActive: true), .hide)
    }
}

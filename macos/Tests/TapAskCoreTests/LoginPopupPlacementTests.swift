import CoreGraphics
import TapAskCore
import XCTest

final class LoginPopupPlacementTests: XCTestCase {
    private let popupSize = CGSize(width: 480, height: 640)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testPrefersRightSideWithTwelvePointGapAndAlignedTop() {
        let parent = CGRect(x: 100, y: 100, width: 480, height: 720)
        XCTAssertEqual(loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: screen),
                       CGRect(x: 592, y: 180, width: 480, height: 640))
    }

    func testUsesLeftSideWhenRightDoesNotFit() {
        let parent = CGRect(x: 800, y: 100, width: 480, height: 720)
        XCTAssertEqual(loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: screen),
                       CGRect(x: 308, y: 180, width: 480, height: 640))
    }

    func testOverlaysParentWhenNeitherSideFits() {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let parent = CGRect(x: 400, y: 100, width: 400, height: 720)
        XCTAssertEqual(loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible),
                       CGRect(x: 360, y: 180, width: 480, height: 640))
    }

    func testPushesPopupUpWhenParentIsNearScreenBottom() {
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let parent = CGRect(x: 100, y: 40, width: 480, height: 480)
        XCTAssertEqual(loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible),
                       CGRect(x: 592, y: 40, width: 480, height: 640))
    }

    func testPushesPopupBelowTheMenuBar() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let parent = CGRect(x: 100, y: 300, width: 480, height: 720)
        XCTAssertEqual(loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible),
                       CGRect(x: 592, y: 236, width: 480, height: 640))
    }

    func testSmallScreenShrinksPopupWithEightPointMargins() {
        let visible = CGRect(x: 0, y: 0, width: 420, height: 600)
        let parent = CGRect(x: 10, y: 0, width: 400, height: 600)
        let frame = loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: 8, y: 8, width: 404, height: 584))
        XCTAssertTrue(visible.contains(frame))
    }

    func testShortScreenPreservesDesiredWidth() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 600)
        let parent = CGRect(x: 100, y: 0, width: 480, height: 600)
        XCTAssertEqual(loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible),
                       CGRect(x: 592, y: 8, width: 480, height: 584))
    }

    func testMinimumSizeTakesPrecedenceOverMargins() {
        let visible = CGRect(x: 0, y: 0, width: 370, height: 490)
        let frame = loginPopupFrame(parentFrame: visible, desiredSize: popupSize, visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: 5, y: 5, width: 360, height: 480))
    }

    func testScreenSmallerThanMinimumIsTheFinalSizeLimit() {
        let visible = CGRect(x: -320, y: 900, width: 320, height: 400)
        XCTAssertEqual(loginPopupFrame(parentFrame: visible, desiredSize: popupSize, visibleFrame: visible), visible)
    }

    func testScreensToTheLeftAndAboveUseGlobalCoordinates() {
        for origin in [CGPoint(x: -1440, y: 40), CGPoint(x: 120, y: 900)] {
            let visible = CGRect(origin: origin, size: screen.size)
            let parent = CGRect(x: origin.x + 100, y: origin.y + 100, width: 480, height: 720)
            let frame = loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible)
            XCTAssertEqual(frame, CGRect(x: origin.x + 592, y: origin.y + 180, width: 480, height: 640))
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testOverlayIsClampedHorizontallyWhenParentStraddlesDisplays() {
        for x: CGFloat in [-400, 200] {
            let visible = CGRect(x: 0, y: 0, width: 800, height: 900)
            let parent = CGRect(x: x, y: 100, width: 1000, height: 720)
            let frame = loginPopupFrame(parentFrame: parent, desiredSize: popupSize, visibleFrame: visible)
            XCTAssertTrue(visible.contains(frame))
            XCTAssertEqual(frame.minX, x < 0 ? 0 : 320)
        }
    }

    func testFirstPresentationPlacesPopupAndSameScreenPreservesIt() throws {
        var placement = LoginPopupPlacement()
        let parent = CGRect(x: 100, y: 100, width: 480, height: 720)
        let first = try XCTUnwrap(placement.frameForPresentation(parentFrame: parent, desiredSize: popupSize,
                                                                screenFrame: screen, visibleFrame: screen))
        XCTAssertEqual(first, CGRect(x: 592, y: 180, width: 480, height: 640))
        XCTAssertNil(placement.frameForPresentation(parentFrame: parent.offsetBy(dx: 50, dy: -100),
                                                    desiredSize: popupSize, screenFrame: screen, visibleFrame: screen))
    }

    func testPresentationOnAnotherScreenRepositionsAndRestoresDesiredSize() throws {
        var placement = LoginPopupPlacement()
        let smallScreen = CGRect(x: -420, y: 0, width: 420, height: 600)
        let small = try XCTUnwrap(placement.frameForPresentation(parentFrame: smallScreen, desiredSize: popupSize,
                                                                screenFrame: smallScreen, visibleFrame: smallScreen))
        XCTAssertEqual(small.size, CGSize(width: 404, height: 584))
        let parent = CGRect(x: 100, y: 100, width: 480, height: 720)
        XCTAssertEqual(placement.frameForPresentation(parentFrame: parent, desiredSize: popupSize,
                                                      screenFrame: screen, visibleFrame: screen),
                       CGRect(x: 592, y: 180, width: 480, height: 640))
    }

    func testUserAdjustmentDisablesPlacementForTheRestOfThePopupLifetime() {
        var placement = LoginPopupPlacement()
        XCTAssertNotNil(placement.frameForPresentation(parentFrame: screen, desiredSize: popupSize,
                                                       screenFrame: screen, visibleFrame: screen))
        placement.userDidAdjustFrame()
        let otherScreen = screen.offsetBy(dx: -1440, dy: 900)
        for target in [screen, otherScreen, screen] {
            XCTAssertNil(placement.frameForPresentation(parentFrame: target, desiredSize: popupSize,
                                                        screenFrame: target, visibleFrame: target))
        }
        var nextPopup = LoginPopupPlacement()
        XCTAssertNotNil(nextPopup.frameForPresentation(parentFrame: otherScreen, desiredSize: popupSize,
                                                       screenFrame: otherScreen, visibleFrame: otherScreen))
    }
}

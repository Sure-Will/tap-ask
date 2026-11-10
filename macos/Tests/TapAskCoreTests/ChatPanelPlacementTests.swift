import CoreGraphics
import TapAskCore
import XCTest

final class ChatPanelPlacementTests: XCTestCase {
    private let current = CGRect(x: 0, y: 0, width: 480, height: 720)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 40, width: 1440, height: 836)

    func testPreservesSavedFrameThatFitsOnTheTargetScreen() {
        let saved = CGRect(x: 200, y: 80, width: 600, height: 760)
        XCTAssertEqual(chatPanelFrame(currentFrame: current, savedFrame: saved,
                                     screenFrame: screen, visibleFrame: visible), saved)
    }

    func testFirstPresentationCentersInsideTheVisibleFrame() {
        XCTAssertEqual(chatPanelFrame(currentFrame: current, savedFrame: nil,
                                     screenFrame: screen, visibleFrame: visible),
                       CGRect(x: 480, y: 98, width: 480, height: 720))
    }

    func testCrossingDisplaysCentersAndPreservesFittingSize() {
        let saved = CGRect(x: 150, y: 70, width: 600, height: 700)
        let otherScreen = screen.offsetBy(dx: -1440, dy: 900)
        let otherVisible = visible.offsetBy(dx: -1440, dy: 900)
        XCTAssertEqual(chatPanelFrame(currentFrame: saved, savedFrame: saved,
                                     screenFrame: otherScreen, visibleFrame: otherVisible),
                       CGRect(x: -1020, y: 1008, width: 600, height: 700))
    }

    func testCrossingToSmallerDisplayShrinksBeforeCentering() {
        let saved = CGRect(x: 200, y: 100, width: 1200, height: 800)
        let smallScreen = CGRect(x: -1000, y: 0, width: 1000, height: 700)
        let smallVisible = CGRect(x: -1000, y: 40, width: 1000, height: 636)
        XCTAssertEqual(chatPanelFrame(currentFrame: saved, savedFrame: saved,
                                     screenFrame: smallScreen, visibleFrame: smallVisible), smallVisible)
    }

    func testSameScreenOversizedFrameShrinksIntoVisibleArea() {
        let saved = CGRect(x: -100, y: -100, width: 1600, height: 1000)
        XCTAssertEqual(chatPanelFrame(currentFrame: saved, savedFrame: saved,
                                     screenFrame: screen, visibleFrame: visible), visible)
    }

    func testPartiallyOffscreenFramesAreMovedInsideWithoutResizing() {
        for saved in [CGRect(x: -100, y: 100, width: 480, height: 720),
                      CGRect(x: 1100, y: 100, width: 480, height: 720),
                      CGRect(x: 100, y: -100, width: 480, height: 720),
                      CGRect(x: 100, y: 300, width: 480, height: 720)] {
            let frame = chatPanelFrame(currentFrame: saved, savedFrame: saved,
                                       screenFrame: screen, visibleFrame: visible)
            XCTAssertEqual(frame.size, saved.size)
            XCTAssertTrue(visible.contains(frame), "Frame \(frame) must fit inside \(visible)")
            XCTAssertEqual(frame.minX, min(max(saved.minX, visible.minX), visible.maxX - saved.width))
            XCTAssertEqual(frame.minY, min(max(saved.minY, visible.minY), visible.maxY - saved.height))
        }
    }

    func testSubminimumScreenIsTheFinalSizeLimit() {
        let tinyScreen = CGRect(x: -320, y: 900, width: 320, height: 400)
        let tinyVisible = CGRect(x: -320, y: 920, width: 320, height: 356)
        XCTAssertEqual(chatPanelFrame(currentFrame: current, savedFrame: current,
                                     screenFrame: tinyScreen, visibleFrame: tinyVisible), tinyVisible)
    }

    func testPreviouslyReducedFrameRegainsNormalMinimumOnLargerScreen() {
        let reduced = CGRect(x: 200, y: 200, width: 320, height: 356)
        XCTAssertEqual(chatPanelFrame(currentFrame: reduced, savedFrame: reduced,
                                     screenFrame: screen, visibleFrame: visible),
                       CGRect(x: 200, y: 200, width: 360, height: 480))
    }

    func testHeightLimitDoesNotShrinkFittingWidth() {
        let shortVisible = CGRect(x: 0, y: 40, width: 1440, height: 600)
        XCTAssertEqual(chatPanelFrame(currentFrame: current, savedFrame: nil,
                                     screenFrame: screen, visibleFrame: shortVisible),
                       CGRect(x: 480, y: 40, width: 480, height: 600))
    }

    func testRepeatedPresentationIsStableAfterFitting() {
        let saved = CGRect(x: -100, y: -100, width: 1600, height: 1000)
        let first = chatPanelFrame(currentFrame: saved, savedFrame: saved,
                                   screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(chatPanelFrame(currentFrame: first, savedFrame: first,
                                     screenFrame: screen, visibleFrame: visible), first)
    }
}

import CoreGraphics
import XCTest
import TapAskCore

final class BrandMarkTests: XCTestCase {
    func testEveryPartFitsInsideViewBoxWithMargins() {
        for path in [BrandMark.screenPath, BrandMark.gapPath, BrandMark.windowPath,
                     BrandMark.starPath, BrandMark.inputPath, BrandMark.path()] {
            let bounds = path.boundingBoxOfPath
            XCTAssertGreaterThan(bounds.minX, BrandMark.viewBox.minX)
            XCTAssertGreaterThan(bounds.minY, BrandMark.viewBox.minY)
            XCTAssertLessThan(bounds.maxX, BrandMark.viewBox.maxX)
            XCTAssertLessThan(bounds.maxY, BrandMark.viewBox.maxY)
        }
    }

    func testEvenOddSilhouetteHasGapAndWindowCutouts() {
        let path = BrandMark.path()
        XCTAssertTrue(path.contains(CGPoint(x: 3, y: 9), using: .evenOdd), "Solid screen")
        XCTAssertFalse(path.contains(CGPoint(x: 7.2, y: 9), using: .evenOdd), "Gap around window")
        XCTAssertTrue(path.contains(CGPoint(x: 11, y: 10.1), using: .evenOdd), "Solid window between cutouts")
        XCTAssertFalse(path.contains(CGPoint(x: 11, y: 7.8), using: .evenOdd), "Star cutout")
        XCTAssertFalse(path.contains(CGPoint(x: 11, y: 11.35), using: .evenOdd), "Input cutout")
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: 9), using: .evenOdd), "Outer margin")
    }

    func testAppIconHasSolidStarAndKeepsInputCutout() {
        let path = BrandMark.path(cutOutStar: false)
        XCTAssertTrue(path.contains(CGPoint(x: 11, y: 7.8), using: .evenOdd))
        XCTAssertFalse(path.contains(CGPoint(x: 11, y: 11.35), using: .evenOdd))
        XCTAssertFalse(path.contains(CGPoint(x: 7.2, y: 9), using: .evenOdd))
    }
}

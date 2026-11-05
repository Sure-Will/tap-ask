#if DEBUG
import XCTest
@testable import TapAsk

final class DebugSoakOptionsTests: XCTestCase {
    func testOrdinaryLaunchDoesNotStartSoak() throws {
        XCTAssertNil(try DebugSoakOptions(arguments: ["TapAsk-Debug"]))
        XCTAssertNil(try DebugSoakOptions(arguments: ["TapAsk-Debug", "-TapAskSoakReleaseOthers", "YES"]))
    }

    func testDefaultAndFractionalDwell() throws {
        let defaults = try XCTUnwrap(DebugSoakOptions(arguments: ["TapAsk-Debug", "-TapAskSoak", "3"]))
        XCTAssertEqual(defaults.rounds, 3)
        XCTAssertEqual(defaults.dwell, 8)
        XCTAssertFalse(defaults.releaseOthers)
        let custom = try XCTUnwrap(DebugSoakOptions(arguments: ["TapAsk-Debug", "-TapAskSoakDwell", "0.25",
                                                               "-TapAskSoak", "2"]))
        XCTAssertEqual(custom.rounds, 2)
        XCTAssertEqual(custom.dwell, 0.25)
    }

    func testInvalidOrMissingRoundCountIsRejected() {
        XCTAssertThrowsError(try DebugSoakOptions(arguments: ["TapAsk-Debug", "-TapAskSoak"]))
        for value in ["0", "-1", "1.5", "abc", "999999999999999999999999"] {
            XCTAssertThrowsError(try DebugSoakOptions(arguments: ["TapAsk-Debug", "-TapAskSoak", value]))
        }
    }

    func testInvalidOrMissingDwellIsRejected() {
        let args = ["TapAsk-Debug", "-TapAskSoak", "2", "-TapAskSoakDwell"]
        XCTAssertThrowsError(try DebugSoakOptions(arguments: args))
        for value in ["0", "-0.1", "nan", "inf", "1e300", "abc"] {
            XCTAssertThrowsError(try DebugSoakOptions(arguments: args + [value]))
        }
    }

    func testReleaseOthersRequiresExplicitYes() throws {
        let args = ["TapAsk-Debug", "-TapAskSoak", "2", "-TapAskSoakReleaseOthers"]
        XCTAssertTrue(try XCTUnwrap(DebugSoakOptions(arguments: args + ["YES"])).releaseOthers)
        XCTAssertFalse(try XCTUnwrap(DebugSoakOptions(arguments: args + ["NO"])).releaseOthers)
        XCTAssertThrowsError(try DebugSoakOptions(arguments: args))
        for value in ["", "true", "1", "abc"] {
            XCTAssertThrowsError(try DebugSoakOptions(arguments: args + [value]))
        }
    }
}
#endif

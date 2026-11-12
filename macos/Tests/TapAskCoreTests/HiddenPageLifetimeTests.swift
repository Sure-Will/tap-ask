import TapAskCore
import XCTest

final class HiddenPageLifetimeTests: XCTestCase {
    func testHiddenPageExpiresAfterThirtyMinutesAndShowingCancelsDeadline() {
        let start = ContinuousClock.now
        var lifetime = HiddenPageLifetime()
        lifetime.hide(at: start)
        lifetime.hide(at: start.advanced(by: .seconds(60)))
        XCTAssertFalse(lifetime.hasExpired(at: start.advanced(by: .seconds(1_800) - .nanoseconds(1))))
        XCTAssertTrue(lifetime.hasExpired(at: start.advanced(by: .seconds(1_800))))
        lifetime.show()
        XCTAssertNil(lifetime.deadline)
        XCTAssertFalse(lifetime.hasExpired(at: start.advanced(by: .seconds(2_000))))
        lifetime.hide(at: start.advanced(by: .seconds(2_000)))
        XCTAssertEqual(lifetime.deadline, start.advanced(by: .seconds(3_800)))
    }
}

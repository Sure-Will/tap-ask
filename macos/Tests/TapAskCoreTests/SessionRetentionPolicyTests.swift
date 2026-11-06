import TapAskCore
import XCTest

final class SessionRetentionPolicyTests: XCTestCase {
    func testBackgroundPageExpiresExactlyFiveMinutesAfterLeaving() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        let leftAt = start.advanced(by: .seconds(10))
        policy.didDisplay("b", at: leftAt)

        XCTAssertEqual(SessionRetentionPolicy.backgroundLifetime, .seconds(300))
        XCTAssertEqual(policy.nextExpiration, leftAt.advanced(by: .seconds(300)))
        XCTAssertEqual(policy.expire(at: leftAt.advanced(by: .seconds(300) - .nanoseconds(1))), [])
        XCTAssertEqual(policy.expire(at: leftAt.advanced(by: .seconds(300))), ["a"])
        XCTAssertNil(policy.nextExpiration)
        XCTAssertEqual(policy.expire(at: leftAt.advanced(by: .seconds(301))), [])
        XCTAssertEqual(policy.currentProviderID, "b")
    }

    func testCurrentPageNeverExpires() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)

        XCTAssertNil(policy.nextExpiration)
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(30_000))), [])
        XCTAssertEqual(policy.currentProviderID, "a")
    }

    func testRepeatedDisplayOfCurrentPageDoesNotRefreshBackgroundDeadline() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        policy.didDisplay("b", at: start)

        XCTAssertEqual(policy.didDisplay("b", at: start.advanced(by: .seconds(299))), [])
        XCTAssertEqual(policy.nextExpiration, start.advanced(by: .seconds(300)))
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(300))), ["a"])
        XCTAssertEqual(policy.currentProviderID, "b")
    }

    func testReturningToPreviousPageMakesItMostRecentlySelected() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        XCTAssertEqual(policy.didDisplay("a", at: start), [])
        XCTAssertEqual(policy.didDisplay("b", at: start.advanced(by: .seconds(1))), [])
        XCTAssertEqual(policy.didDisplay("a", at: start.advanced(by: .seconds(2))), [])
        XCTAssertEqual(policy.didDisplay("c", at: start.advanced(by: .seconds(3))), ["b"])

        XCTAssertEqual(policy.currentProviderID, "c")
        XCTAssertEqual(policy.releaseBackgroundPages(), ["a"])
    }

    func testEqualTimestampsPreserveSelectionOrder() {
        let now = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: now)
        policy.didDisplay("b", at: now)
        policy.didDisplay("a", at: now)

        XCTAssertEqual(policy.didDisplay("c", at: now), ["b"])
        XCTAssertEqual(policy.didDisplay("d", at: now), ["a"])
        XCTAssertEqual(policy.releaseBackgroundPages(), ["c"])
        XCTAssertEqual(policy.currentProviderID, "d")
    }

    func testLeavingPageAgainStartsANewBackgroundLifetime() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        policy.didDisplay("b", at: start.advanced(by: .seconds(10)))
        policy.didDisplay("a", at: start.advanced(by: .seconds(100)))
        policy.didDisplay("b", at: start.advanced(by: .seconds(200)))

        XCTAssertEqual(policy.nextExpiration, start.advanced(by: .seconds(500)))
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(310))), [])
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(500))), ["a"])
    }

    func testDisplayDoesNotExpireThePageBeingSelected() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        policy.didDisplay("b", at: start)
        let later = start.advanced(by: .seconds(400))

        XCTAssertEqual(policy.didDisplay("a", at: later), [])
        XCTAssertEqual(policy.currentProviderID, "a")
        XCTAssertEqual(policy.nextExpiration, later.advanced(by: .seconds(300)))
        XCTAssertEqual(policy.expire(at: later), [])
        XCTAssertEqual(policy.releaseBackgroundPages(), ["b"])
    }

    func testExpiredPageCanBeDisplayedAgainWithFreshRetention() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        policy.didDisplay("b", at: start)
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(300))), ["a"])

        let rebuiltAt = start.advanced(by: .seconds(400))
        XCTAssertEqual(policy.didDisplay("a", at: rebuiltAt), [])
        XCTAssertEqual(policy.currentProviderID, "a")
        XCTAssertEqual(policy.nextExpiration, rebuiltAt.advanced(by: .seconds(300)))
        XCTAssertEqual(policy.expire(at: rebuiltAt.advanced(by: .seconds(300))), ["b"])
        XCTAssertEqual(policy.currentProviderID, "a")
    }

    func testManualReleaseClearsDeadlineAndKeepsCurrentPage() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        policy.didDisplay("b", at: start)

        XCTAssertEqual(policy.releaseBackgroundPages(), ["a"])
        XCTAssertNil(policy.nextExpiration)
        XCTAssertEqual(policy.currentProviderID, "b")
        XCTAssertEqual(policy.releaseBackgroundPages(), [])
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(300))), [])
        XCTAssertEqual(policy.didDisplay("a", at: start.advanced(by: .seconds(400))), [])
        XCTAssertEqual(policy.releaseBackgroundPages(), ["b"])
    }

    func testResetClearsCurrentPageAndDeadline() {
        let start = ContinuousClock.now
        var policy = SessionRetentionPolicy()
        policy.didDisplay("a", at: start)
        policy.didDisplay("b", at: start)

        policy.reset()

        XCTAssertNil(policy.currentProviderID)
        XCTAssertNil(policy.nextExpiration)
        XCTAssertEqual(policy.expire(at: start.advanced(by: .seconds(300))), [])
        XCTAssertEqual(policy.releaseBackgroundPages(), [])
        XCTAssertEqual(policy.didDisplay("c", at: start), [])
        XCTAssertEqual(policy.currentProviderID, "c")
        XCTAssertNil(policy.nextExpiration)
    }
}

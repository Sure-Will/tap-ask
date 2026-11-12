import Foundation
import TapAskCore
import XCTest

final class IdleUpdateRelaunchTests: XCTestCase {
    func testOnlyTheExpectedUpdatedVersionStartsHiddenAndMarkerIsConsumed() throws {
        let name = "TapAsk.IdleUpdateRelaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        IdleUpdateRelaunch.prepare(targetVersion: "42", defaults: defaults)
        XCTAssertTrue(IdleUpdateRelaunch.consume(currentVersion: "42", defaults: defaults))
        XCTAssertFalse(IdleUpdateRelaunch.consume(currentVersion: "42", defaults: defaults))
        IdleUpdateRelaunch.prepare(targetVersion: "43", defaults: defaults)
        XCTAssertFalse(IdleUpdateRelaunch.consume(currentVersion: "42", defaults: defaults))
        XCTAssertFalse(IdleUpdateRelaunch.consume(currentVersion: "43", defaults: defaults))
    }
}

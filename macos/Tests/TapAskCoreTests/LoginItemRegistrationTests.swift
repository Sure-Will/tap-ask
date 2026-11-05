import XCTest
import TapAskCore

final class LoginItemRegistrationTests: XCTestCase {
    private let home = "/Users/example"

    func testSystemApplicationsAllowsFirstRegistration() {
        XCTAssertTrue(shouldRegister("/Applications/TapAsk.app"))
        XCTAssertTrue(shouldRegister("/Applications/Tools/TapAsk.app"))
    }

    func testUserApplicationsAllowsFirstRegistration() {
        XCTAssertTrue(shouldRegister("/Users/example/Applications/TapAsk.app"))
        XCTAssertFalse(shouldRegister("/Users/another/Applications/TapAsk.app"))
    }

    func testBuildDirectoryDefersRegistration() {
        XCTAssertFalse(shouldRegister("/Users/example/repos/tap-ask/macos/build/TapAsk.app"))
    }

    func testPreviousAttemptPreventsRegistration() {
        for path in ["/Applications/TapAsk.app", "/Users/example/Applications/TapAsk.app"] {
            XCTAssertFalse(LoginItemRegistration.shouldRegister(appBundlePath: path,
                                                                 homeDirectory: home,
                                                                 hasAttempted: true))
        }
    }

    func testParentComponentsAreStandardizedBeforeMatching() {
        XCTAssertTrue(shouldRegister("/Applications/Tools/../TapAsk.app"))
        XCTAssertFalse(shouldRegister("/Applications/../tmp/TapAsk.app"))
        XCTAssertTrue(shouldRegister("/Users/example/Applications/Tools/../TapAsk.app"))
        XCTAssertFalse(shouldRegister("/Users/example/Applications/../Downloads/TapAsk.app"))
        XCTAssertTrue(LoginItemRegistration.shouldRegister(
            appBundlePath: "/Users/example/Applications/TapAsk.app",
            homeDirectory: "/Users/temporary/../example/", hasAttempted: false))
    }

    func testTrailingSeparatorsDoNotChangeMembership() {
        XCTAssertTrue(shouldRegister("/Applications/TapAsk.app/"))
        XCTAssertTrue(LoginItemRegistration.shouldRegister(
            appBundlePath: "/Users/example/Applications/TapAsk.app/",
            homeDirectory: "/Users/example/", hasAttempted: false))
        XCTAssertFalse(shouldRegister("/Applications/"))
        XCTAssertFalse(shouldRegister("/Users/example/Applications/"))
    }

    func testSimilarDirectoryNamesAreRejected() {
        XCTAssertFalse(shouldRegister("/ApplicationsX/TapAsk.app"))
        XCTAssertFalse(shouldRegister("/Users/example/ApplicationsX/TapAsk.app"))
        XCTAssertFalse(shouldRegister("/Users/example2/Applications/TapAsk.app"))
    }

    func testRelativePathsAreNotInstalledPaths() {
        XCTAssertFalse(shouldRegister("Applications/TapAsk.app"))
        XCTAssertFalse(LoginItemRegistration.shouldRegister(
            appBundlePath: "/Users/example/Applications/TapAsk.app",
            homeDirectory: "Users/example", hasAttempted: false))
    }

    private func shouldRegister(_ appBundlePath: String) -> Bool {
        LoginItemRegistration.shouldRegister(appBundlePath: appBundlePath,
                                             homeDirectory: home, hasAttempted: false)
    }
}

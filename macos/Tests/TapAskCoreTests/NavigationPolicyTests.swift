import Foundation
import XCTest
import TapAskCore

final class NavigationPolicyTests: XCTestCase {
    func testChatAndSpecificLoginEndpoints() throws {
        try assertCases(in: "testChatAndSpecificLoginEndpoints")
    }

    func testGoogleAccountCrossDomainSignInRemainsInsidePanel() throws {
        try assertCases(in: "testGoogleAccountCrossDomainSignInRemainsInsidePanel")
    }

    func testUntrustedOriginsCannotRenderInPanel() throws {
        try assertCases(in: "testUntrustedOriginsCannotRenderInPanel")
    }

    func testExternalClickScriptAndFormAreDifferent() throws {
        try assertCases(in: "testExternalClickScriptAndFormAreDifferent")
    }

    func testFinalRedirectResponseCannotBypassActionCheck() throws {
        try assertCases(in: "testFinalRedirectResponseCannotBypassActionCheck")
    }

    func testDownloadsNeverBecomePanelDocuments() throws {
        try assertCases(in: "testDownloadsNeverBecomePanelDocuments")
    }

    func testCaptchaSubframesAreSeparateFromTopLevelTrust() throws {
        try assertCases(in: "testCaptchaSubframesAreSeparateFromTopLevelTrust")
    }

    func testOriginDisplayOmitsCredentialsPathsAndLoginTokens() throws {
        try assertCases(in: "testOriginDisplayOmitsCredentialsPathsAndLoginTokens")
    }

    func testAdditionalPolicyBranches() throws {
        try assertCases(in: "additionalPolicyBranches")
    }

    private func assertCases(in group: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        let cases = try SharedFixtures.decode("policy-cases.json", as: PolicyCases.self)
        let panelCases = cases.isPanelURL.filter { $0.group == group }
        let actionCases = cases.actions.filter { $0.group == group }
        let responseCases = cases.responses.filter { $0.group == group }
        let originCases = cases.origins.filter { $0.group == group }
        XCTAssertFalse(panelCases.isEmpty && actionCases.isEmpty && responseCases.isEmpty && originCases.isEmpty,
                       "Missing shared cases for \(group)", file: file, line: line)

        for item in panelCases {
            XCTAssertEqual(policy.isPanelURL(try url(item.url)), item.expected, item.id, file: file, line: line)
        }
        for item in actionCases {
            XCTAssertEqual(policy.action(url: try url(item.url), topLevel: item.topLevel,
                                         clickedLink: item.clickedLink, method: item.method,
                                         wantsDownload: item.wantsDownload, sourceURL: try url(item.sourceURL)).rawValue,
                           item.expected, item.id, file: file, line: line)
        }
        for item in responseCases {
            XCTAssertEqual(policy.response(url: try url(item.url), mainFrame: item.mainFrame,
                                           canDisplay: item.canDisplay, attachment: item.attachment).rawValue,
                           item.expected, item.id, file: file, line: line)
        }
        for item in originCases {
            let result = NavigationPolicy.origin(try url(item.url))
            if let expected = item.expected {
                XCTAssertEqual(result, expected, item.id, file: file, line: line)
            } else {
                let excluded = try XCTUnwrap(item.excludes, "Origin case needs an expectation: \(item.id)",
                                            file: file, line: line)
                XCTAssertFalse(result.contains(excluded), item.id, file: file, line: line)
            }
        }
    }

    private func url(_ value: String?) throws -> URL? {
        guard let value else { return nil }
        return try XCTUnwrap(URL(string: value), "Invalid fixture URL: \(value)")
    }
}

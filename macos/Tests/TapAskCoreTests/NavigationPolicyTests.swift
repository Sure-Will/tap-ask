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

    func testDeepSeekNavigationAndOrigins() throws {
        try assertCases(in: "testDeepSeekNavigationAndOrigins")
    }

    func testClaudeNavigationAndOrigins() throws {
        try assertCases(in: "testClaudeNavigationAndOrigins")
    }

    func testGeminiNavigationAndOrigins() throws {
        try assertCases(in: "testGeminiNavigationAndOrigins")
    }

    func testGrokNavigationAndOrigins() throws {
        try assertCases(in: "testGrokNavigationAndOrigins")
    }

    func testDoubaoNavigationAndOrigins() throws {
        try assertCases(in: "testDoubaoNavigationAndOrigins")
    }

    func testGrokAccountsHostIsProviderSpecific() throws {
        try assertCases(in: "testGrokAccountsHostIsProviderSpecific")
    }

    func testUnknownFixtureProviderIsAnError() throws {
        let catalog = try SharedFixtures.catalog()
        XCTAssertEqual(try SharedFixtures.policy(for: nil, in: catalog).provider.id, "chatgpt")
        for id in ["deepseke", ""] {
            XCTAssertThrowsError(try SharedFixtures.policy(for: id, in: catalog)) { error in
                XCTAssertEqual(error as? SharedFixtures.FixtureError, .unknownProvider(id))
            }
        }
    }

    private func assertCases(in group: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let catalog = try SharedFixtures.catalog()
        let cases = try SharedFixtures.decode("policy-cases.json", as: PolicyCases.self)
        let panelCases = cases.isPanelURL.filter { $0.group == group }
        let actionCases = cases.actions.filter { $0.group == group }
        let responseCases = cases.responses.filter { $0.group == group }
        let originCases = cases.origins.filter { $0.group == group }
        XCTAssertFalse(panelCases.isEmpty && actionCases.isEmpty && responseCases.isEmpty && originCases.isEmpty,
                       "Missing shared cases for \(group)", file: file, line: line)

        for item in panelCases {
            let policy = try SharedFixtures.policy(for: item.provider, in: catalog)
            XCTAssertEqual(policy.isPanelURL(try url(item.url)), item.expected, item.id, file: file, line: line)
        }
        for item in actionCases {
            let policy = try SharedFixtures.policy(for: item.provider, in: catalog)
            XCTAssertEqual(policy.action(url: try url(item.url), topLevel: item.topLevel,
                                         clickedLink: item.clickedLink, method: item.method,
                                         wantsDownload: item.wantsDownload, sourceURL: try url(item.sourceURL)).rawValue,
                           item.expected, item.id, file: file, line: line)
        }
        for item in responseCases {
            let policy = try SharedFixtures.policy(for: item.provider, in: catalog)
            XCTAssertEqual(policy.response(url: try url(item.url), mainFrame: item.mainFrame,
                                           canDisplay: item.canDisplay, attachment: item.attachment).rawValue,
                           item.expected, item.id, file: file, line: line)
        }
        for item in originCases {
            let policy = try SharedFixtures.policy(for: item.provider, in: catalog)
            let result = NavigationPolicy.origin(try url(item.url))
            if let isProviderURL = item.isProviderURL {
                XCTAssertEqual(policy.isProviderURL(try url(item.url)), isProviderURL, item.id, file: file, line: line)
            }
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

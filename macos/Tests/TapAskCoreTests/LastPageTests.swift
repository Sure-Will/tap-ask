import Foundation
import TapAskCore
import XCTest

final class LastPageTests: XCTestCase {
    func testSavesEachHomeHostWithoutQueryOrFragment() throws {
        let catalog = try SharedFixtures.catalog()
        for provider in catalog.providers {
            let policy = NavigationPolicy(provider: provider, identityHosts: catalog.identityHosts)
            let page = provider.home.appendingPathComponent("conversation")
            let url = try XCTUnwrap(URL(string: page.absoluteString + "?token=secret#message"))
            XCTAssertEqual(LastPage.saved(from: url, policy: policy), page.absoluteString, provider.id)
        }
    }

    func testGeminiAccountPathIsPreserved() throws {
        let policy = try SharedFixtures.policy(for: "gemini", in: SharedFixtures.catalog())
        let url = URL(string: "https://gemini.google.com/u/1/app?hl=zh")!
        XCTAssertEqual(LastPage.saved(from: url, policy: policy), "https://gemini.google.com/u/1/app")
        XCTAssertEqual(LastPage.restored(from: "https://gemini.google.com/u/1/app", policy: policy),
                       URL(string: "https://gemini.google.com/u/1/app"))
    }

    func testLoginAndIdentityHostsAreNeverSavedOrRestored() throws {
        let catalog = try SharedFixtures.catalog()
        for provider in catalog.providers {
            let policy = NavigationPolicy(provider: provider, identityHosts: catalog.identityHosts)
            let otherHosts = provider.hosts.filter { $0.lowercased() != provider.home.host?.lowercased() }
            for host in otherHosts + catalog.identityHosts {
                let url = try XCTUnwrap(URL(string: "https://\(host)/login?token=secret"))
                XCTAssertNil(LastPage.saved(from: url, policy: policy), "\(provider.id): \(host)")
                XCTAssertNil(LastPage.restored(from: url.absoluteString, policy: policy), "\(provider.id): \(host)")
            }
        }
    }

    func testInsecureAndLookalikeURLsAreNeverSavedOrRestored() throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        let rejected = [
            "http://chatgpt.com/c/one",
            "https://chatgpt.com.attacker.invalid/c/one",
            "https://sub.chatgpt.com/c/one",
            "https://chаtgpt.com/c/one", // Cyrillic 'а'.
            "https://chatgpt.com@attacker.invalid/c/one",
            "https://user:secret@chatgpt.com/c/one",
            "https://chatgpt.com:8443/c/one",
            "https://claude.ai/c/one",
        ]
        for value in rejected {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(LastPage.saved(from: url, policy: policy), value)
            XCTAssertNil(LastPage.restored(from: value, policy: policy), value)
        }
        XCTAssertNil(LastPage.saved(from: nil, policy: policy))
    }

    func testInvalidStoredStringsAreNotRestored() throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        let rejected: [String?] = [nil, "", "not a URL", "/c/one", "https://", "https://[invalid",
                                   "https://chatgpt.com/c/%zz", "https://chatgpt.com/c/a b"]
        for value in rejected {
            XCTAssertNil(LastPage.restored(from: value, policy: policy), value ?? "nil")
        }
    }

    func testSavedPageMustStillPassTheCurrentNavigationPolicy() throws {
        let provider = try JSONDecoder().decode(Provider.self, from: Data("""
            {"id":"chatgpt","name":"ChatGPT","home":"https://chatgpt.com/","hosts":["chat.openai.com"]}
            """.utf8))
        let policy = NavigationPolicy(provider: provider, identityHosts: ["chatgpt.com"])
        let page = "https://chatgpt.com/c/one"
        XCTAssertTrue(policy.isPanelURL(URL(string: page)))
        XCTAssertNil(LastPage.restored(from: page, policy: policy))
    }

    func testEncodingIsPreservedAndOnlySchemeHostAndPathAreStored() throws {
        let policy = try SharedFixtures.chatGPTPolicy()
        let value = "https://CHATGPT.COM:443/c/a%2Fb%3Fc%23d?token=secret#message"
        let expected = "https://chatgpt.com/c/a%2Fb%3Fc%23d"
        XCTAssertEqual(LastPage.saved(from: URL(string: value), policy: policy), expected)
        XCTAssertEqual(LastPage.restored(from: value, policy: policy)?.absoluteString, expected)
    }
}

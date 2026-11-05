import Foundation
import XCTest
import TapAskCore

final class ProviderCatalogTests: XCTestCase {
    func testSharedProviderCatalogIncludesSixProvidersInDefaultOrderAndValidHTTPSHomes() throws {
        let catalog = try SharedFixtures.catalog()
        XCTAssertEqual(catalog.providers.count, 6)
        XCTAssertEqual(catalog.providers.map(\.id), ["chatgpt", "claude", "gemini", "deepseek", "grok", "doubao"])
        XCTAssertEqual(catalog.providers.map(\.name), ["ChatGPT", "Claude", "Gemini", "DeepSeek", "Grok", "豆包"])
        XCTAssertEqual(catalog.providers.map { $0.home.absoluteString },
                       ["https://chatgpt.com/", "https://claude.ai/", "https://gemini.google.com/app",
                        "https://chat.deepseek.com/", "https://grok.com/", "https://www.doubao.com/chat/"])
        XCTAssertEqual(catalog.providers.map(\.hosts), [
            ["chatgpt.com", "chat.openai.com", "auth.openai.com", "auth0.openai.com", "setup.auth.openai.com"],
            ["claude.ai"], ["gemini.google.com"], ["chat.deepseek.com"],
            ["grok.com", "accounts.x.ai"], ["www.doubao.com"],
        ])
        XCTAssertEqual(catalog.identityHosts, ["accounts.google.com", "accounts.youtube.com", "appleid.apple.com",
                                              "account.apple.com", "login.microsoftonline.com", "login.microsoft.com",
                                              "login.live.com", "account.live.com"])
        XCTAssertEqual(Set(catalog.providers.map(\.id)).count, catalog.providers.count)

        var allHosts = catalog.identityHosts
        for provider in catalog.providers {
            XCTAssertFalse(provider.hosts.isEmpty, provider.id)
            XCTAssertEqual(provider.home.scheme, "https", provider.id)
            let homeHost = try XCTUnwrap(provider.home.host, provider.id)
            XCTAssertTrue(provider.hosts.contains(homeHost), provider.id)
            allHosts.append(contentsOf: provider.hosts)
        }
        for host in allHosts {
            XCTAssertEqual(host, host.lowercased(), host)
            XCTAssertFalse(host.isEmpty)
        }
        XCTAssertEqual(Set(allHosts).count, allHosts.count, "Hosts must be globally unique")
    }

    func testProviderPolicyTrustsOnlyItsOwnHostsAndSharedIdentityHosts() throws {
        let catalog = try SharedFixtures.catalog()
        for provider in catalog.providers {
            let policy = NavigationPolicy(provider: provider, identityHosts: catalog.identityHosts)
            for host in provider.hosts + catalog.identityHosts {
                XCTAssertTrue(policy.isPanelURL(URL(string: "https://\(host)/")), "\(provider.id): \(host)")
            }
            for other in catalog.providers where other.id != provider.id {
                for host in other.hosts {
                    XCTAssertFalse(policy.isPanelURL(URL(string: "https://\(host)/")), "\(provider.id): \(host)")
                }
            }
        }
    }

    func testCatalogRejectsAnEmptyProviderList() throws {
        XCTAssertThrowsError(try decodeCatalog(providers: [])) { error in
            XCTAssertEqual(error as? ProviderCatalog.ValidationError, .noProviders)
        }
    }

    func testCatalogRejectsDuplicateIDsWithDistinctHosts() throws {
        XCTAssertThrowsError(try decodeCatalog(providers: [
            provider(id: "same", host: "one.example"), provider(id: "same", host: "two.example"),
        ])) { error in
            XCTAssertEqual(error as? ProviderCatalog.ValidationError, .duplicateID("same"))
        }
    }

    func testCatalogRejectsHostsSharedByProvidersIgnoringCase() throws {
        XCTAssertThrowsError(try decodeCatalog(providers: [
            provider(id: "one", host: "chat.example"), provider(id: "two", host: "CHAT.EXAMPLE"),
        ])) { error in
            XCTAssertEqual(error as? ProviderCatalog.ValidationError,
                           .providerHostOverlap(host: "chat.example", firstID: "one", secondID: "two"))
        }
    }

    func testCatalogRejectsProviderHostsOverlappingIdentityHostsIgnoringCase() throws {
        XCTAssertThrowsError(try decodeCatalog(providers: [provider(id: "one", host: "login.example")],
                                               identityHosts: ["LOGIN.EXAMPLE"])) { error in
            XCTAssertEqual(error as? ProviderCatalog.ValidationError,
                           .identityHostOverlap(host: "login.example", providerID: "one"))
        }
    }

    private func provider(id: String, host: String) -> [String: Any] {
        ["id": id, "name": id, "home": "https://\(host)/", "hosts": [host]]
    }

    private func decodeCatalog(providers: [[String: Any]], identityHosts: [String] = []) throws -> ProviderCatalog {
        let data = try JSONSerialization.data(withJSONObject: ["providers": providers, "identityHosts": identityHosts])
        return try JSONDecoder().decode(ProviderCatalog.self, from: data)
    }
}

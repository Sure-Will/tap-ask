import Foundation
import XCTest
import TapAskCore

final class ProviderCatalogTests: XCTestCase {
    func testSharedProviderCatalogIncludesBothProvidersAndValidHTTPSHomes() throws {
        let catalog = try SharedFixtures.catalog()
        XCTAssertEqual(catalog.providers.map(\.id), ["chatgpt", "deepseek"])
        XCTAssertTrue(catalog.providers.contains { $0.name == "ChatGPT" && $0.home.host == "chatgpt.com" })
        XCTAssertTrue(catalog.providers.contains { $0.name == "DeepSeek" && $0.home.absoluteString == "https://chat.deepseek.com/" })
        XCTAssertFalse(catalog.providers.isEmpty)
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

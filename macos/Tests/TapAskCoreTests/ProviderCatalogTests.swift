import Foundation
import XCTest
import TapAskCore

final class ProviderCatalogTests: XCTestCase {
    func testSharedProviderCatalogIncludesChatGPTAndValidHTTPSHomes() throws {
        let catalog = try SharedFixtures.catalog()
        XCTAssertTrue(catalog.providers.contains { $0.name == "ChatGPT" && $0.home.host == "chatgpt.com" })
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
}

import XCTest
import TapAskCore

final class ProviderOrderTests: XCTestCase {
    func testNoSavedOrderUsesCatalogOrder() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderOrder.ordered(providers, savedIDs: nil).map(\.id), providers.map(\.id))
        XCTAssertEqual(ProviderOrder.ordered(providers, savedIDs: []).map(\.id), providers.map(\.id))
    }

    func testPartialSavedOrderSkipsUnknownAndDuplicateIDs() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderOrder.ordered(providers, savedIDs: ["removed", "grok", "chatgpt", "grok"]).map(\.id),
                       ["grok", "chatgpt", "claude", "gemini", "deepseek", "doubao"])
    }

    func testNewProvidersAppendAfterTheExistingSavedOrder() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderOrder.ordered(providers, savedIDs: ["deepseek", "chatgpt"]).map(\.id),
                       ["deepseek", "chatgpt", "claude", "gemini", "grok", "doubao"])
    }

    func testMoveUpUsesTheProposedInsertionRow() {
        XCTAssertEqual(ProviderOrder.moving(["a", "b", "c", "d"], from: 2, to: 0), ["c", "a", "b", "d"])
    }

    func testMoveDownAccountsForRemovingTheSourceRow() {
        XCTAssertEqual(ProviderOrder.moving(["a", "b", "c", "d"], from: 0, to: 3), ["b", "c", "a", "d"])
    }

    func testMoveToEndAcceptsTheRowAfterTheLastItem() {
        XCTAssertEqual(ProviderOrder.moving(["a", "b", "c", "d"], from: 1, to: 4), ["a", "c", "d", "b"])
    }

    func testDropsOnEitherSideOfTheSourceKeepTheSameOrder() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(ProviderOrder.moving(ids, from: 1, to: 1), ids)
        XCTAssertEqual(ProviderOrder.moving(ids, from: 1, to: 2), ids)
        XCTAssertEqual(ProviderOrder.moving(ids, from: 2, to: 3), ids)
        XCTAssertEqual(ProviderOrder.moving(["a"], from: 0, to: 1), ["a"])
    }
}

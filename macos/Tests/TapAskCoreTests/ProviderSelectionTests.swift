import XCTest
import TapAskCore

final class ProviderSelectionTests: XCTestCase {
    func testRestoresSavedProvider() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: "deepseek")?.id, "deepseek")
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: "chatgpt")?.id, "chatgpt")
    }

    func testFirstLaunchDefaultsToDeepSeekRegardlessOfOrder() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: nil)?.id, "deepseek")
        XCTAssertEqual(ProviderSelection.restored(in: Array(providers.reversed()), savedID: nil)?.id, "deepseek")
        XCTAssertEqual(ProviderSelection.restored(in: providers.filter { $0.id != "deepseek" }, savedID: nil)?.id,
                       "chatgpt")
    }

    func testInvalidAndEmptySavedIDsUseFirstProvider() throws {
        let providers = try SharedFixtures.catalog().providers
        for savedID: String? in ["", "removed-provider"] {
            XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: savedID)?.id, "chatgpt")
        }
    }

    func testRestorationFollowsIDsAcrossReorderingAndRemoval() throws {
        let providers = try SharedFixtures.catalog().providers.reversed()
        XCTAssertEqual(ProviderSelection.restored(in: Array(providers), savedID: "chatgpt")?.id, "chatgpt")
        XCTAssertEqual(ProviderSelection.restored(in: Array(providers), savedID: "removed-provider")?.id, "doubao")
        XCTAssertEqual(ProviderSelection.restored(in: providers.filter { $0.id != "chatgpt" },
                                                 savedID: "chatgpt")?.id, "doubao")
    }

    func testProviderNumbersAreOneBasedAndOutOfRangeReturnsNil() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderSelection.provider(at: 1, in: providers)?.id, "chatgpt")
        XCTAssertEqual(ProviderSelection.provider(at: 2, in: providers)?.id, "claude")
        XCTAssertEqual(ProviderSelection.provider(at: 4, in: providers)?.id, "deepseek")
        XCTAssertEqual(ProviderSelection.provider(at: 6, in: providers)?.id, "doubao")
        for number in [Int.min, -1, 0, 7, 9, Int.max] {
            XCTAssertNil(ProviderSelection.provider(at: number, in: providers), "Shortcut \(number)")
        }
    }

    func testCustomOrderControlsFallbackAndNumberedSelection() throws {
        let providers = ProviderOrder.ordered(try SharedFixtures.catalog().providers, savedIDs: ["grok", "deepseek"])
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: nil)?.id, "deepseek")
        for savedID: String? in ["", "removed-provider"] {
            XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: savedID)?.id, "grok")
        }
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: "claude")?.id, "claude")
        XCTAssertEqual(ProviderSelection.provider(at: 1, in: providers)?.id, "grok")
        XCTAssertEqual(ProviderSelection.provider(at: 2, in: providers)?.id, "deepseek")
    }

    func testSelectionFromAnEmptyListReturnsNil() {
        XCTAssertNil(ProviderSelection.restored(in: [], savedID: "chatgpt"))
        XCTAssertNil(ProviderSelection.provider(at: 1, in: []))
    }
}

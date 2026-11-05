import XCTest
import TapAskCore

final class ProviderSelectionTests: XCTestCase {
    func testRestoresSavedProvider() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: "deepseek")?.id, "deepseek")
        XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: "chatgpt")?.id, "chatgpt")
    }

    func testMissingInvalidAndEmptySavedIDsUseFirstProvider() throws {
        let providers = try SharedFixtures.catalog().providers
        for savedID: String? in [nil, "", "removed-provider"] {
            XCTAssertEqual(ProviderSelection.restored(in: providers, savedID: savedID)?.id, "chatgpt")
        }
    }

    func testRestorationFollowsIDsAcrossReorderingAndRemoval() throws {
        let providers = try SharedFixtures.catalog().providers.reversed()
        XCTAssertEqual(ProviderSelection.restored(in: Array(providers), savedID: "chatgpt")?.id, "chatgpt")
        XCTAssertEqual(ProviderSelection.restored(in: Array(providers), savedID: "removed-provider")?.id, "deepseek")
        XCTAssertEqual(ProviderSelection.restored(in: providers.filter { $0.id != "chatgpt" },
                                                 savedID: "chatgpt")?.id, "deepseek")
    }

    func testProviderNumbersAreOneBasedAndOutOfRangeReturnsNil() throws {
        let providers = try SharedFixtures.catalog().providers
        XCTAssertEqual(ProviderSelection.provider(at: 1, in: providers)?.id, "chatgpt")
        XCTAssertEqual(ProviderSelection.provider(at: 2, in: providers)?.id, "deepseek")
        for number in [Int.min, -1, 0, 3, 9, Int.max] {
            XCTAssertNil(ProviderSelection.provider(at: number, in: providers), "Shortcut \(number)")
        }
    }

    func testSelectionFromAnEmptyListReturnsNil() {
        XCTAssertNil(ProviderSelection.restored(in: [], savedID: "chatgpt"))
        XCTAssertNil(ProviderSelection.provider(at: 1, in: []))
    }
}

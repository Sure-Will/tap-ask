import AppKit
import XCTest
import TapAskCore
@testable import TapAsk

final class StatusMenuTests: XCTestCase {
    @MainActor
    func testMenuOrderAndSelection() throws {
        let target = MenuActionTarget()
        let providers = try SharedFixtures.catalog().providers
        let action = #selector(MenuActionTarget.action(_:))
        let items = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek", target: target, action: action)
        let menu = makeStatusMenu(isPanelVisible: false, providerItems: items, target: target,
                                  toggleAction: action, reloadAction: action,
                                  shortcut: .defaultShortcut, settingsAction: action)
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "separator" : $0.title },
                       ["显示 TapAsk", "separator", "ChatGPT", "Claude", "Gemini", "DeepSeek", "Grok", "豆包",
                        "设置…", "separator", "重新加载", "separator", "退出 TapAsk"])
        XCTAssertEqual(items.map(\.state), providers.map { $0.id == "deepseek" ? .on : .off })
        XCTAssertEqual(items.map(\.tag), Array(1...providers.count))
        XCTAssertTrue(menu.items[8].target === target)
        XCTAssertEqual(menu.items[10].keyEquivalent, "r")
    }

    @MainActor
    func testMenusOwnSeparateItemsAndUseSavedOrder() throws {
        let target = MenuActionTarget()
        let providers = ProviderOrder.ordered(try SharedFixtures.catalog().providers,
                                              savedIDs: ["doubao", "deepseek", "grok"])
        let action = #selector(MenuActionTarget.action(_:))
        let first = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek", target: target, action: action)
        let second = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek", target: target, action: action)
        let menu = makeStatusMenu(isPanelVisible: true, providerItems: second, target: target,
                                  toggleAction: action, reloadAction: action,
                                  shortcut: .defaultShortcut, settingsAction: action)
        XCTAssertEqual(menu.items.first?.title, "隐藏 TapAsk")
        XCTAssertEqual(second.map(\.title), ["豆包", "DeepSeek", "Grok", "ChatGPT", "Claude", "Gemini"])
        for (a, b) in zip(first, second) { XCTAssertFalse(a === b) }
    }

    @MainActor
    func testStatusImageIsTemplateAtMenuBarSize() {
        let image = makeStatusImage()
        XCTAssertEqual(image.size, NSSize(width: 22, height: 18))
        XCTAssertTrue(image.isTemplate)
    }
}

@MainActor
private final class MenuActionTarget: NSObject {
    @objc func action(_ sender: Any?) {}
}

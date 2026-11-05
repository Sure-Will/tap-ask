import AppKit
import XCTest
import TapAskCore
@testable import TapAsk

final class StatusMenuTests: XCTestCase {
    @MainActor
    func testMenuOrderSelectionShortcutsAndActions() throws {
        let target = MenuActionTarget()
        let providers = try SharedFixtures.catalog().providers
        let select = #selector(MenuActionTarget.selectProvider(_:))
        let toggle = #selector(MenuActionTarget.togglePanel(_:))
        let order = #selector(MenuActionTarget.showProviderOrder(_:))
        let reload = #selector(MenuActionTarget.reloadPage(_:))
        let items = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek",
                                          target: target, action: select)
        let menu = makeStatusMenu(isPanelVisible: false, providerItems: items, target: target,
                                  toggleAction: toggle, orderAction: order, reloadAction: reload)
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "separator" : $0.title },
                       ["显示 TapAsk", "separator", "ChatGPT", "Claude", "Gemini", "DeepSeek", "Grok", "豆包",
                        "服务商排序…", "separator",
                        "重新加载", "separator", "退出 TapAsk"])
        XCTAssertEqual(menu.items.map(\.keyEquivalent), [" ", "", "1", "2", "3", "4", "5", "6", "", "", "r", "", "q"])
        XCTAssertEqual(menu.items[0].keyEquivalentModifierMask, .option)
        for index in [2, 3, 4, 5, 6, 7, 10, 12] { XCTAssertEqual(menu.items[index].keyEquivalentModifierMask, .command) }
        for (index, item) in items.enumerated() {
            XCTAssertEqual(item.state, providers[index].id == "deepseek" ? .on : .off)
            XCTAssertEqual(item.tag, index + 1)
            XCTAssertEqual(item.action, select)
        }
        XCTAssertEqual(menu.items[0].action, toggle)
        XCTAssertEqual(menu.items[8].action, order)
        XCTAssertEqual(menu.items[10].action, reload)
        XCTAssertEqual(menu.items[12].action, #selector(NSApplication.terminate(_:)))
        for index in [0, 2, 3, 4, 5, 6, 7, 8, 10] { XCTAssertTrue(menu.items[index].target === target) }
    }

    @MainActor
    func testVisiblePanelUsesHideTitleAndMenusOwnSeparateProviderItems() throws {
        let target = MenuActionTarget()
        let providers = try SharedFixtures.catalog().providers
        let mainItems = makeProviderMenuItems(providers: providers, currentProviderID: "chatgpt",
                                              target: target, action: #selector(MenuActionTarget.selectProvider(_:)))
        let statusItems = makeProviderMenuItems(providers: providers, currentProviderID: "chatgpt",
                                                target: target, action: #selector(MenuActionTarget.selectProvider(_:)))
        let mainMenu = NSMenu()
        for item in mainItems { mainMenu.addItem(item) }
        let menu = makeStatusMenu(isPanelVisible: true, providerItems: statusItems, target: target,
                                  toggleAction: #selector(MenuActionTarget.togglePanel(_:)),
                                  orderAction: #selector(MenuActionTarget.showProviderOrder(_:)),
                                  reloadAction: #selector(MenuActionTarget.reloadPage(_:)))
        XCTAssertEqual(menu.items.first?.title, "隐藏 TapAsk")
        XCTAssertEqual(menu.items[2].state, .on)
        XCTAssertEqual(menu.items[3].state, .off)
        for (main, status) in zip(mainItems, statusItems) {
            XCTAssertFalse(main === status)
            XCTAssertTrue(main.menu === mainMenu)
            XCTAssertTrue(status.menu === menu)
        }
    }

    @MainActor
    func testSavedOrderControlsShortcutsTagsAndSelectionInBothMenus() throws {
        let target = MenuActionTarget()
        let providers = ProviderOrder.ordered(try SharedFixtures.catalog().providers,
                                               savedIDs: ["doubao", "deepseek", "grok"])
        let mainItems = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek",
                                              target: target, action: #selector(MenuActionTarget.selectProvider(_:)))
        let statusItems = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek",
                                                target: target, action: #selector(MenuActionTarget.selectProvider(_:)))
        let statusMenu = makeStatusMenu(isPanelVisible: false, providerItems: statusItems, target: target,
                                        toggleAction: #selector(MenuActionTarget.togglePanel(_:)),
                                        orderAction: #selector(MenuActionTarget.showProviderOrder(_:)),
                                        reloadAction: #selector(MenuActionTarget.reloadPage(_:)))
        XCTAssertEqual(Array(statusMenu.items[2..<8]).map(\.title),
                       ["豆包", "DeepSeek", "Grok", "ChatGPT", "Claude", "Gemini"])
        for items in [mainItems, statusItems] {
            for (index, item) in items.enumerated() {
                XCTAssertEqual(item.title, providers[index].name)
                XCTAssertEqual(item.keyEquivalent, String(index + 1))
                XCTAssertEqual(item.tag, index + 1)
                XCTAssertEqual(item.state, index == 1 ? .on : .off)
                XCTAssertEqual(ProviderSelection.provider(at: item.tag, in: providers)?.name, item.title)
            }
        }
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
    @objc func selectProvider(_ sender: NSMenuItem) {}
    @objc func togglePanel(_ sender: Any?) {}
    @objc func reloadPage(_ sender: Any?) {}
    @objc func showProviderOrder(_ sender: Any?) {}
}

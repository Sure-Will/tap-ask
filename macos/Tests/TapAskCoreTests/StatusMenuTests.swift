import AppKit
import XCTest
@testable import TapAsk

final class StatusMenuTests: XCTestCase {
    @MainActor
    func testMenuOrderSelectionShortcutsAndActions() throws {
        let target = MenuActionTarget()
        let providers = try SharedFixtures.catalog().providers
        let select = #selector(MenuActionTarget.selectProvider(_:))
        let toggle = #selector(MenuActionTarget.togglePanel(_:))
        let reload = #selector(MenuActionTarget.reloadPage(_:))
        let items = makeProviderMenuItems(providers: providers, currentProviderID: "deepseek",
                                          target: target, action: select)
        let menu = makeStatusMenu(isPanelVisible: false, providerItems: items, target: target,
                                  toggleAction: toggle, reloadAction: reload)
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "separator" : $0.title },
                       ["显示 TapAsk", "separator", "ChatGPT", "DeepSeek", "separator",
                        "重新加载", "separator", "退出 TapAsk"])
        XCTAssertEqual(menu.items.map(\.keyEquivalent), [" ", "", "1", "2", "", "r", "", "q"])
        XCTAssertEqual(menu.items[0].keyEquivalentModifierMask, .option)
        for index in [2, 3, 5, 7] { XCTAssertEqual(menu.items[index].keyEquivalentModifierMask, .command) }
        XCTAssertEqual(menu.items[2].state, .off)
        XCTAssertEqual(menu.items[3].state, .on)
        XCTAssertEqual(menu.items[2].tag, 1)
        XCTAssertEqual(menu.items[3].tag, 2)
        XCTAssertEqual(menu.items[0].action, toggle)
        XCTAssertEqual(menu.items[2].action, select)
        XCTAssertEqual(menu.items[3].action, select)
        XCTAssertEqual(menu.items[5].action, reload)
        XCTAssertEqual(menu.items[7].action, #selector(NSApplication.terminate(_:)))
        for index in [0, 2, 3, 5] { XCTAssertTrue(menu.items[index].target === target) }
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
}

import AppKit
import TapAskCore

/// Each menu owns fresh items; NSMenuItem instances cannot belong to two menus.
@MainActor
func makeProviderMenuItems(providers: [Provider], currentProviderID: String,
                           target: AnyObject, action: Selector) -> [NSMenuItem] {
    providers.enumerated().map { index, provider in
        let item = NSMenuItem(title: provider.name, action: action,
                              keyEquivalent: index < 9 ? String(index + 1) : "")
        item.target = target
        item.tag = index + 1
        item.keyEquivalentModifierMask = .command
        item.state = provider.id == currentProviderID ? .on : .off
        return item
    }
}

/// Menu assembly is independent of NSStatusBar so its contract can be tested.
@MainActor
func makeStatusMenu(isPanelVisible: Bool, providerItems: [NSMenuItem], target: AnyObject,
                    toggleAction: Selector, reloadAction: Selector, shortcut: GlobalShortcut,
                    settingsAction: Selector) -> NSMenu {
    let menu = NSMenu()
    let toggle = menu.addItem(withTitle: panelVisibilityMenuTitle(isVisible: isPanelVisible),
                              action: toggleAction, keyEquivalent: shortcut.keyEquivalent)
    toggle.target = target
    toggle.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
    menu.addItem(.separator())
    for item in providerItems { menu.addItem(item) }
    let settings = menu.addItem(withTitle: "设置…", action: settingsAction, keyEquivalent: "")
    settings.target = target
    menu.addItem(.separator())
    let reload = menu.addItem(withTitle: "重新加载", action: reloadAction, keyEquivalent: "r")
    reload.target = target
    reload.keyEquivalentModifierMask = .command
    menu.addItem(.separator())
    let quit = menu.addItem(withTitle: "退出 TapAsk", action: #selector(NSApplication.terminate(_:)),
                            keyEquivalent: "q")
    quit.target = NSApp
    quit.keyEquivalentModifierMask = .command
    return menu
}

func panelVisibilityMenuTitle(isVisible: Bool) -> String {
    isVisible ? "隐藏 TapAsk" : "显示 TapAsk"
}

@MainActor
func makeStatusImage() -> NSImage {
    let image = NSImage(size: BrandMark.viewBox.size, flipped: true) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(BrandMark.path())
        context.drawPath(using: .eoFill)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "TapAsk"
    return image
}

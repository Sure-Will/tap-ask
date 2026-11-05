import AppKit
import Carbon.HIToolbox
import ServiceManagement
import TapAskCore
import WebKit
import os

enum AppLog {
    private static let subsystem = "io.github.sure-will.tap-ask"
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
}

@main
enum TapAskApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var panel: ChatPanel!
    private var catalog: ProviderCatalog!
    private var sessions: [String: ProviderSession] = [:]
    private var currentSession: ProviderSession!
    private var loginPopup: LoginPopup?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var hotKeyStartedAt: UInt64?
    private var needsWebFocus = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
            || launchEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil

        catalog = loadProviders()
        guard let provider = ProviderSelection.restored(in: catalog.providers,
                                                        savedID: UserDefaults.standard.string(forKey: "LastProviderID")) else {
            fatalError("TapAsk: providers.json 必须至少包含一个服务商。")
        }
        panel = ChatPanel()
        panel.onCancel = { [weak self] in self?.hidePanel() }
        panel.onRetry = { [weak self] in self?.currentSession.loadHome() }
        panel.onBecomeKey = { [weak self] in
            if self?.loginPopup == nil { self?.recordKeyLatency() }
        }

        switchProvider(to: provider)
        installMainMenu()
        installStatusItem()

        registerLoginItemOnce()
        var hotKeyUnavailable = false
        do {
            hotKey = try HotKey { [weak self] in self?.togglePanel() }
        } catch {
            hotKeyUnavailable = true
            AppLog.hotkey.error("Hotkey registration failed: \(String(describing: error), privacy: .public)")
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "⌥空格 注册失败"
            alert.informativeText = "请重新打开 TapAsk 后再试，当前仍可使用窗口。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
        if !launchedAtLogin || hotKeyUnavailable { presentPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel != nil { presentPanel() }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Activation can complete after the hotkey callback returns.
        if needsWebFocus, panel?.isVisible == true {
            focusChatWindow()
            needsWebFocus = false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        loginPopup?.dispose()
    }

    private func togglePanel() {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        switch PanelToggle.action(isVisible: panel.isVisible) {
        case .show:
            hotKeyStartedAt = startedAt
            presentPanel()
        case .hide:
            hidePanel()
            AppLog.hotkey.info("action=hide")
        }
    }

    private func presentPanel() {
        if !panel.isVisible { panel.prepareForPresentation() }
        needsWebFocus = true
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        focusChatWindow()
        if NSApp.isActive { needsWebFocus = false }
    }

    private func focusChatWindow() {
        if let loginPopup {
            panel.orderFront(nil)
            loginPopup.show(relativeTo: panel)
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(currentSession.webView)
        }
    }

    private func switchProvider(to provider: Provider) {
        if let currentSession, currentSession.policy.provider.id == provider.id {
            if case .failed = currentSession.loadState { currentSession.loadHome() }
            return
        }
        closeLoginPopup(restoreFocus: false)
        let existing = sessions[provider.id]
        let session = existing ?? makeSession(for: provider)
        sessions[provider.id] = session
        currentSession = session
        panel.contentView = session.webView
        panel.origin = session.title
        panel.updateLoadState(session.loadState, providerName: provider.name)
        if panel.isVisible, !NSApp.isHidden { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(session.webView)
        UserDefaults.standard.set(provider.id, forKey: "LastProviderID")
        if existing == nil { session.loadHome() }
        else if case .failed = session.loadState { session.loadHome() }
    }

    private func makeSession(for provider: Provider) -> ProviderSession {
        let session = ProviderSession(provider: provider, identityHosts: catalog.identityHosts)
        let policy = session.policy
        session.onLoadStateChange = { [weak self] state in
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return }
            self.panel.updateLoadState(state, providerName: provider.name)
        }
        session.webDelegate.onCommit = { [weak self] _ in
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return }
            self.panel.origin = self.currentSession.title
        }
        session.webDelegate.onCreatePopup = { [weak self] configuration, url in
            // A retained background page must not open a login window for the visible provider.
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return nil }
            return self.openLoginPopup(configuration: configuration, policy: policy, initialURL: url)
        }
        return session
    }

    private func openLoginPopup(configuration: WKWebViewConfiguration, policy: NavigationPolicy,
                                initialURL: URL?) -> WKWebView {
        closeLoginPopup(restoreFocus: false)
        let popup = LoginPopup(configuration: configuration, policy: policy, initialURL: initialURL)
        loginPopup = popup
        popup.onClose = { [weak self] in self?.closeLoginPopup() }
        popup.panel.onBecomeKey = { [weak self] in self?.recordKeyLatency() }
        // A request can complete after the user has hidden the app; keep that popup hidden too.
        if panel.isVisible, !NSApp.isHidden {
            needsWebFocus = true
            NSApp.activate()
            focusChatWindow()
            if NSApp.isActive { needsWebFocus = false }
        }
        return popup.webView
    }

    private func closeLoginPopup(restoreFocus: Bool = true) {
        let popup = loginPopup
        loginPopup = nil
        popup?.dispose()
        if restoreFocus, panel.isVisible, !NSApp.isHidden {
            needsWebFocus = true
            NSApp.activate()
            focusChatWindow()
            if NSApp.isActive { needsWebFocus = false }
        }
    }

    private func hidePanel() {
        needsWebFocus = false
        hotKeyStartedAt = nil
        loginPopup?.hide()
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    private func recordKeyLatency() {
        guard let start = hotKeyStartedAt else { return }
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        AppLog.hotkey.info("key latency milliseconds=\(milliseconds, privacy: .public)")
        hotKeyStartedAt = nil
    }

    @objc private func reloadPage(_ sender: Any?) { currentSession.reload() }

    @objc private func togglePanelFromMenu(_ sender: Any?) { togglePanel() }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let provider = ProviderSelection.provider(at: sender.tag, in: catalog.providers) else { return }
        switchProvider(to: provider)
        presentPanel()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectProvider(_:)) {
            let provider = ProviderSelection.provider(at: menuItem.tag, in: catalog.providers)
            menuItem.state = provider?.id == currentSession.policy.provider.id ? .on : .off
        } else if menuItem.action == #selector(togglePanelFromMenu(_:)) {
            menuItem.title = panelVisibilityMenuTitle(isVisible: panel.isVisible)
        }
        return true
    }

    private func makeProviderMenuItems() -> [NSMenuItem] {
        TapAsk.makeProviderMenuItems(providers: catalog.providers,
                                    currentProviderID: currentSession.policy.provider.id,
                                    target: self, action: #selector(selectProvider(_:)))
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusImage()
        item.button?.toolTip = "TapAsk"
        item.menu = makeStatusMenu(isPanelVisible: panel.isVisible,
                                   providerItems: makeProviderMenuItems(), target: self,
                                   toggleAction: #selector(togglePanelFromMenu(_:)),
                                   reloadAction: #selector(reloadPage(_:)))
        statusItem = item
    }

    private func loadProviders() -> ProviderCatalog {
        guard let url = Bundle.main.url(forResource: "providers", withExtension: "json") else {
            fatalError("TapAsk: app 资源中缺少 providers.json，请使用 scripts/build-app.sh 构建。")
        }
        do {
            return try JSONDecoder().decode(ProviderCatalog.self, from: Data(contentsOf: url))
        } catch {
            fatalError("TapAsk: 无法读取或解析 providers.json：\(error)")
        }
    }

    private func registerLoginItemOnce() {
        let key = "LoginItemRegistrationAttempted"
        let defaults = UserDefaults.standard
        let hasAttempted = defaults.bool(forKey: key)
        guard LoginItemRegistration.shouldRegister(appBundlePath: Bundle.main.bundlePath,
                                                   homeDirectory: NSHomeDirectory(),
                                                   hasAttempted: hasAttempted) else {
            if !hasAttempted {
                AppLog.lifecycle.info("Login item registration deferred: install in /Applications or ~/Applications first")
            }
            return
        }
        // Mark the attempt before registering; later launches respect the user's system setting.
        defaults.set(true, forKey: key)
        do {
            try SMAppService.mainApp.register()
        } catch {
            AppLog.lifecycle.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "TapAsk")
        appMenu.addItem(withTitle: "退出 TapAsk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let viewMenu = NSMenu(title: "View")
        let reload = viewMenu.addItem(withTitle: "重新加载", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        reload.target = self
        let providerMenu = NSMenu(title: "服务商")
        for item in makeProviderMenuItems() { providerMenu.addItem(item) }
        for submenu in [appMenu, editMenu, providerMenu, viewMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

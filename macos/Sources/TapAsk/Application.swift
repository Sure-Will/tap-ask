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
        #if DEBUG
        let delegate = AppDelegate()
        #else
        let delegate = AppDelegate(updater: AppUpdater())
        #endif
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private(set) var panel: ChatPanel!
    private var catalog: ProviderCatalog!
    private var orderedProviders: [Provider] = []
    private var providerOrderWindow: ProviderOrderWindowController?
    private var shortcutSettingsWindow: ShortcutSettingsWindowController?
    private var settingsPopover: SettingsPopoverController?
    private var providerMenu: NSMenu?
    private var statusMenu: NSMenu?
    private(set) var sessions: [String: ProviderSession] = [:]
    private(set) var currentSession: ProviderSession!
    private var currentProvider: Provider?
    private let defaults: UserDefaults
    private let updater: (any AppUpdating)?
    private lazy var generalSettings = SettingsGeneralView(updater: updater, defaults: defaults)
    private let websiteDataStore: WKWebsiteDataStore
    private let retentionNow: () -> ContinuousClock.Instant
    private var retentionPolicy = SessionRetentionPolicy()
    private(set) var backgroundPageReleaseTask: Task<Void, Never>?
    private var hiddenPageLifetime = HiddenPageLifetime()
    private var hiddenPageReleaseTask: Task<Void, Never>?
    private(set) var loginPopup: LoginPopup?
    private lazy var shortcutController = GlobalShortcutController(defaults: defaults) { [weak self] shortcut in
        try HotKey(shortcut: shortcut) { [weak self] in self?.togglePanel() }
    }
    private var statusItem: NSStatusItem?
    private var hotKeyStartedAt: UInt64?
    private var needsWebFocus = false
    #if DEBUG
    private var soakTask: Task<Void, Never>?
    #endif

    init(catalog: ProviderCatalog? = nil, defaults: UserDefaults = .standard,
         updater: (any AppUpdating)? = nil,
         websiteDataStore: WKWebsiteDataStore = .default(),
         retentionNow: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.catalog = catalog
        self.defaults = defaults
        self.updater = updater
        self.websiteDataStore = websiteDataStore
        self.retentionNow = retentionNow
        super.init()
    }

    deinit { backgroundPageReleaseTask?.cancel(); hiddenPageReleaseTask?.cancel() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
            || launchEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
        let launchedAfterIdleUpdate = IdleUpdateRelaunch.consume(
            currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, defaults: defaults)

        catalog = catalog ?? loadProviders()
        orderedProviders = ProviderOrder.ordered(catalog.providers,
                                                 savedIDs: defaults.stringArray(forKey: "ProviderOrder"))
        guard let provider = ProviderSelection.restored(in: orderedProviders,
                                                        savedID: defaults.string(forKey: "LastProviderID")) else {
            fatalError("TapAsk: providers.json 必须至少包含一个服务商。")
        }
        configurePanel()

        if launchedAfterIdleUpdate { currentProvider = provider }
        else { switchProvider(to: provider) }
        installMainMenu()
        installStatusItem()
        startUpdater()

        #if !DEBUG
        registerLoginItemOnce()
        #endif
        var hotKeyUnavailable = false
        do {
            try shortcutController.start()
        } catch {
            hotKeyUnavailable = true
            AppLog.hotkey.error("Hotkey registration failed: \(String(describing: error), privacy: .public)")
            #if !DEBUG
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "\(shortcutController.shortcut.displayString) 注册失败"
            alert.informativeText = "仍可点击菜单栏图标呼出窗口，或在“设置…”的快捷键页更换组合键。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            #endif
        }
        if (!launchedAtLogin && !launchedAfterIdleUpdate) || hotKeyUnavailable { presentPanel() }
        else { scheduleHiddenPageRelease() }
        #if DEBUG
        startSoakIfRequested()
        #endif
    }

    func configurePanel() {
        panel = ChatPanel(defaults: defaults)
        panel.onCancel = { [weak self] in self?.hidePanel() }
        panel.onRetry = { [weak self] in self?.currentSession?.loadHome() }
        panel.onBecomeKey = { [weak self] in
            if self?.loginPopup == nil { self?.recordKeyLatency() }
        }
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
        #if DEBUG
        soakTask?.cancel()
        soakTask = nil
        #endif
        shortcutSettingsWindow?.onRecordingChange = nil
        settingsPopover?.close()
        shortcutSettingsWindow?.close()
        shortcutController.stop()
        closeLoginPopup(restoreFocus: false)
        removeAllSessions()
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
        releaseExpiredBackgroundPages()
        releaseIdleCurrentPageIfNeeded()
        hiddenPageReleaseTask?.cancel()
        hiddenPageReleaseTask = nil
        hiddenPageLifetime.show()
        if currentSession == nil, let currentProvider { switchProvider(to: currentProvider) }
        if currentSession?.needsReloadOnDisplay == true { currentSession?.prepareForDisplay() }
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
            panel.makeFirstResponder(currentSession?.webView)
        }
    }

    func switchProvider(to provider: Provider) {
        // Check before lookup: a delayed timer must not revive an expired cached page.
        releaseExpiredBackgroundPages()
        releaseIdleCurrentPageIfNeeded()
        if let currentSession, currentSession.policy.provider.id == provider.id {
            currentSession.prepareForDisplay()
            return
        }
        if currentProvider?.id != provider.id { closeLoginPopup(restoreFocus: false) }
        let existing = sessions[provider.id]
        let session = existing ?? makeSession(for: provider)
        displaySession(session)
        defaults.set(provider.id, forKey: "LastProviderID")
        if existing == nil { session.loadInitialPage() }
    }

    /// Shared assembly path; initial loading is separate so idle lifecycle fixtures need no network.
    func displaySession(_ session: ProviderSession) {
        sessions[session.policy.provider.id] = session
        currentSession = session
        currentProvider = session.policy.provider
        panel.pageView = session.webView
        panel.origin = session.title
        panel.updateLoadState(session.loadState, providerName: session.policy.provider.name)
        if panel.isVisible, !NSApp.isHidden { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(session.webView)
        let released = retentionPolicy.didDisplay(session.policy.provider.id, at: retentionNow())
        releasePages(released, reason: "capacity")
        scheduleBackgroundPageRelease()
        session.prepareForDisplay()
    }

    /// Termination releases both the visible page and the cached background pages.
    func removeAllSessions() {
        backgroundPageReleaseTask?.cancel()
        backgroundPageReleaseTask = nil
        hiddenPageReleaseTask?.cancel()
        hiddenPageReleaseTask = nil
        hiddenPageLifetime.show()
        retentionPolicy.reset()
        for session in sessions.values { session.dispose() }
        panel?.makeFirstResponder(nil)
        panel?.pageView = nil
        currentSession = nil
        currentProvider = nil
        sessions.removeAll()
    }

    @objc func releaseOtherProviderPages(_ sender: Any?) {
        releasePages(retentionPolicy.releaseBackgroundPages(), reason: "manual")
        scheduleBackgroundPageRelease()
    }

    func releaseExpiredBackgroundPages() {
        releasePages(retentionPolicy.expire(at: retentionNow()), reason: "timeout")
        scheduleBackgroundPageRelease()
    }

    private func releasePages(_ providerIDs: [String], reason: String) {
        for id in providerIDs {
            guard let session = sessions.removeValue(forKey: id) else { continue }
            session.dispose()
            AppLog.lifecycle.info("phase=page-release reason=\(reason, privacy: .public) provider=\(id, privacy: .public) sessions=\(self.sessions.count, privacy: .public)")
        }
    }

    private func scheduleBackgroundPageRelease() {
        backgroundPageReleaseTask?.cancel()
        backgroundPageReleaseTask = nil
        guard let deadline = retentionPolicy.nextExpiration else { return }
        backgroundPageReleaseTask = Task { @MainActor [weak self] in
            // ContinuousClock includes system sleep; cancellation is the only sleep error.
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.releaseExpiredBackgroundPages()
        }
    }

    func makeSession(for provider: Provider) -> ProviderSession {
        let session = ProviderSession(provider: provider, identityHosts: catalog.identityHosts,
                                      defaults: defaults, websiteDataStore: websiteDataStore)
        let policy = session.policy
        session.onLoadStateChange = { [weak self] state in
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return }
            self.panel.updateLoadState(state, providerName: provider.name)
        }
        session.onCommit = { [weak self] in
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return }
            self.panel.origin = self.currentSession.title
        }
        session.webDelegate.onNavigationNotice = { [weak self] notice in
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return }
            self.panel.showNavigationNotice(notice)
        }
        session.webDelegate.onCreatePopup = { [weak self] configuration, url in
            // A retained background page must not open a login window for the visible provider.
            guard let self, self.currentSession?.policy.provider.id == provider.id else { return nil }
            return self.openLoginPopup(configuration: configuration, policy: policy, initialURL: url)
        }
        return session
    }

    func openLoginPopup(configuration: WKWebViewConfiguration, policy: NavigationPolicy,
                        initialURL: URL?) -> WKWebView {
        closeLoginPopup(restoreFocus: false)
        let popup = LoginPopup(configuration: configuration, policy: policy, initialURL: initialURL)
        loginPopup = popup
        popup.onClose = { [weak self] in self?.closeLoginPopup() }
        let openingProviderID = policy.provider.id
        popup.onComplete = { [weak self] in
            guard let self else { return }
            self.closeLoginPopup()
            switch loginPopupCompletionReload(openingProviderID: openingProviderID,
                                               displayedProviderID: self.currentSession?.policy.provider.id) {
            case let .now(providerID):
                self.sessions[providerID]?.reload()
            case let .onNextDisplay(providerID):
                self.sessions[providerID]?.needsReloadOnDisplay = true
            }
        }
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

    func closeLoginPopup(restoreFocus: Bool = true) {
        let popup = loginPopup
        loginPopup = nil
        popup?.dispose()
        if restoreFocus, panel?.isVisible == true, !NSApp.isHidden {
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
        scheduleHiddenPageRelease()
    }

    private func scheduleHiddenPageRelease() {
        guard currentSession != nil else { return }
        hiddenPageLifetime.hide(at: retentionNow())
        hiddenPageReleaseTask?.cancel()
        guard let deadline = hiddenPageLifetime.deadline else { return }
        hiddenPageReleaseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.releaseExpiredBackgroundPages()
            self.releaseIdleCurrentPageIfNeeded()
        }
    }

    func releaseIdleCurrentPageIfNeeded() {
        guard panel?.isVisible == false, hiddenPageLifetime.hasExpired(at: retentionNow()),
              let session = currentSession else { return }
        panel.makeFirstResponder(nil)
        panel.pageView = nil
        sessions.removeValue(forKey: session.policy.provider.id)
        currentSession = nil
        session.dispose()
        retentionPolicy.reset()
        hiddenPageLifetime.show()
        hiddenPageReleaseTask?.cancel()
        hiddenPageReleaseTask = nil
        AppLog.lifecycle.info("phase=page-release reason=idle provider=\(session.policy.provider.id, privacy: .public)")
    }

    private func recordKeyLatency() {
        guard let start = hotKeyStartedAt else { return }
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        AppLog.hotkey.info("key latency milliseconds=\(milliseconds, privacy: .public)")
        hotKeyStartedAt = nil
    }

    @objc private func reloadPage(_ sender: Any?) {
        let popupIsKey = loginPopup.map { NSApp.keyWindow === $0.panel } ?? false
        switch pageReloadTarget(isAppActive: NSApp.isActive, isLoginPopupKeyWindow: popupIsKey) {
        case .loginPopup: loginPopup?.reload()
        case .provider: reloadCurrentProvider()
        }
    }

    @objc private func reloadProviderPage(_ sender: Any?) { reloadCurrentProvider() }

    private func reloadCurrentProvider() {
        if currentSession == nil, let currentProvider {
            switchProvider(to: currentProvider)
            if panel.isVisible == false { scheduleHiddenPageRelease() }
        } else { currentSession?.reload() }
    }

    @objc private func togglePanelFromMenu(_ sender: Any?) { togglePanel() }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let provider = ProviderSelection.provider(at: sender.tag, in: orderedProviders) else { return }
        switchProvider(to: provider)
        presentPanel()
    }

    func startUpdater() { updater?.start() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectProvider(_:)) {
            let provider = ProviderSelection.provider(at: menuItem.tag, in: orderedProviders)
            menuItem.state = provider?.id == currentProvider?.id ? .on : .off
        } else if menuItem.action == #selector(togglePanelFromMenu(_:)) {
            menuItem.title = panelVisibilityMenuTitle(isVisible: panel.isVisible)
        }
        return true
    }

    private func makeProviderMenuItems() -> [NSMenuItem] {
        TapAsk.makeProviderMenuItems(providers: orderedProviders,
                                    currentProviderID: currentProvider?.id ?? "",
                                    target: self, action: #selector(selectProvider(_:)))
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusImage()
        item.button?.toolTip = "TapAsk — 单击呼出，右键菜单"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let statusItem, let button = statusItem.button else { return }
            statusMenu = makeCurrentStatusMenu()
            // Let NSStatusItem position and track the menu directly below its button.
            statusItem.menu = statusMenu
            defer { statusItem.menu = nil }
            button.performClick(nil)
        } else {
            togglePanel()
        }
    }

    func makeCurrentStatusMenu() -> NSMenu {
        var settingsItems = generalSettings.toggleMenuItems()
        let shortcut = NSMenuItem(title: "设置快捷键…", action: #selector(showShortcutSettings(_:)), keyEquivalent: "")
        shortcut.target = self
        let order = NSMenuItem(title: "调整服务商顺序…", action: #selector(showProviderOrder(_:)), keyEquivalent: "")
        order.target = self
        settingsItems.append(contentsOf: [shortcut, order])
        var updateItems = generalSettings.updateMenuItems()
        if updater?.updateReadyToInstall == true {
            let install = NSMenuItem(title: "立即安装并重启", action: #selector(installPreparedUpdate(_:)), keyEquivalent: "")
            install.target = self
            updateItems.insert(install, at: updateItems.count - 1)
        }
        settingsItems.append(contentsOf: updateItems)
        return makeStatusMenu(isPanelVisible: panel.isVisible, providerItems: makeProviderMenuItems(), target: self,
                       toggleAction: #selector(togglePanelFromMenu(_:)),
                       reloadAction: #selector(reloadProviderPage(_:)),
                       shortcut: shortcutController.shortcut, settingsItems: settingsItems)
    }

    private func rebuildProviderMenus() {
        providerMenu?.removeAllItems()
        for item in makeProviderMenuItems() { providerMenu?.addItem(item) }
        statusMenu = makeCurrentStatusMenu()
    }

    @objc private func showProviderOrder(_ sender: Any?) {
        showSettingsPopover(.providerOrder)
    }

    @objc private func showShortcutSettings(_ sender: Any?) {
        showSettingsPopover(.shortcut)
    }

    private func showSettingsPopover(_ section: SettingsPopoverController.Section) {
        if shortcutSettingsWindow == nil {
            if providerOrderWindow == nil {
                let order = ProviderOrderWindowController(providers: orderedProviders)
                order.onOrderChange = { [weak self] ids in self?.saveProviderOrder(ids) }
                providerOrderWindow = order
            }
            let controller = ShortcutSettingsWindowController(shortcut: shortcutController.shortcut)
            controller.onRecordingChange = { [weak self] recording in
                try self?.shortcutController.setRecording(recording)
            }
            controller.onSave = { [weak self] shortcut in
                guard let self else { return }
                try self.shortcutController.save(shortcut)
                self.rebuildProviderMenus()
            }
            shortcutSettingsWindow = controller
        }
        if settingsPopover == nil, let shortcutSettingsWindow, let providerOrderWindow {
            let controller = SettingsPopoverController(shortcutController: shortcutSettingsWindow,
                                                       orderController: providerOrderWindow)
            settingsPopover = controller
        }
        needsWebFocus = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let button = self.statusItem?.button else { return }
            self.settingsPopover?.show(section, relativeTo: button, shortcut: self.shortcutController.shortcut)
        }
    }

    @objc private func installPreparedUpdate(_ sender: Any?) {
        guard let updater, updater.updateReadyToInstall else { return }
        for session in sessions.values { session.saveCurrentPage() }
        if panel?.isVisible == false, let version = updater.preparedUpdateVersion {
            IdleUpdateRelaunch.prepare(targetVersion: version, defaults: defaults)
        }
        updater.installAndRestart()
    }

    private func saveProviderOrder(_ ids: [String]?) {
        if let ids { defaults.set(ids, forKey: "ProviderOrder") }
        else { defaults.removeObject(forKey: "ProviderOrder") }
        orderedProviders = ProviderOrder.ordered(catalog.providers, savedIDs: ids)
        providerOrderWindow?.update(providers: orderedProviders)
        rebuildProviderMenus()
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

    #if !DEBUG
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
    #endif

    #if DEBUG
    private func startSoakIfRequested() {
        let options: DebugSoakOptions
        do {
            guard let parsed = try DebugSoakOptions(arguments: CommandLine.arguments) else { return }
            options = parsed
        } catch {
            AppLog.lifecycle.error("phase=soak error=\(error.localizedDescription, privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        let providers = orderedProviders
        soakTask = Task { @MainActor [weak self] in
            for round in 1...options.rounds {
                for provider in providers {
                    guard !Task.isCancelled, self != nil else { return }
                    self?.switchProvider(to: provider)
                    do { try await Task.sleep(for: .seconds(options.dwell)) }
                    catch { return }
                }
                guard let self else { return }
                AppLog.lifecycle.notice("phase=soak round=\(round, privacy: .public) sessions=\(self.sessions.count, privacy: .public)")
                if round < options.rounds {
                    self.showProviderOrder(nil)
                    // Give AppKit a turn to present and lay out the window before closing it.
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return }
                    self.settingsPopover?.close()
                }
            }
            if options.releaseOthers {
                guard !Task.isCancelled, let self, let first = providers.first else { return }
                self.switchProvider(to: first)
                let before = self.sessions.count
                self.releaseOtherProviderPages(nil)
                AppLog.lifecycle.notice("phase=soak release-others before=\(before, privacy: .public) sessions=\(self.sessions.count, privacy: .public)")
                // Leave a bounded sampling window before the usual soak shutdown.
                do { try await Task.sleep(for: .seconds(options.dwell)) }
                catch { return }
            }
            AppLog.lifecycle.notice("phase=soak done")
            self?.soakTask = nil
            NSApp.terminate(nil)
        }
    }
    #endif

    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "TapAsk")
        let shortcuts = appMenu.addItem(withTitle: "设置…", action: #selector(showShortcutSettings(_:)), keyEquivalent: ",")
        shortcuts.target = self
        appMenu.addItem(.separator())
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
        self.providerMenu = providerMenu
        rebuildProviderMenus()
        for submenu in [appMenu, editMenu, providerMenu, viewMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

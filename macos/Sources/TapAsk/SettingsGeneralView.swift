import AppKit
import ServiceManagement
import TapAskCore

@MainActor
final class SettingsGeneralView: NSView {
    private let updater: (any AppUpdating)?
    private let defaults: UserDefaults
    private let login = NSButton(checkboxWithTitle: "登录时启动 TapAsk", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let automaticUpdates = NSButton(checkboxWithTitle: "自动检查并下载更新", target: nil, action: nil)
    private let check = NSButton(title: "检查更新…", target: nil, action: nil)
    private let updateStatus = NSTextField(wrappingLabelWithString: "")

    init(updater: (any AppUpdating)?, defaults: UserDefaults) {
        self.updater = updater
        self.defaults = defaults
        super.init(frame: .zero)
        login.target = self; login.action = #selector(changeLogin(_:))
        automaticUpdates.target = self; automaticUpdates.action = #selector(changeUpdates(_:))
        check.target = self; check.action = #selector(checkUpdates(_:))
        loginStatus.textColor = .secondaryLabelColor
        updateStatus.textColor = .secondaryLabelColor
        loginStatus.font = .systemFont(ofSize: 12)
        updateStatus.font = .systemFont(ofSize: 12)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let versionLabel = NSTextField(labelWithString: "TapAsk \(version)")
        versionLabel.textColor = .secondaryLabelColor
        for view in [login, loginStatus, automaticUpdates, check, updateStatus, versionLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            login.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            login.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            loginStatus.topAnchor.constraint(equalTo: login.bottomAnchor, constant: 6),
            loginStatus.leadingAnchor.constraint(equalTo: login.leadingAnchor, constant: 20),
            loginStatus.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            automaticUpdates.topAnchor.constraint(equalTo: loginStatus.bottomAnchor, constant: 24),
            automaticUpdates.leadingAnchor.constraint(equalTo: login.leadingAnchor),
            check.topAnchor.constraint(equalTo: automaticUpdates.bottomAnchor, constant: 12),
            check.leadingAnchor.constraint(equalTo: login.leadingAnchor, constant: 20),
            updateStatus.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 10),
            updateStatus.centerYAnchor.constraint(equalTo: check.centerYAnchor),
            updateStatus.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            versionLabel.leadingAnchor.constraint(equalTo: login.leadingAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        let installed = LoginItemRegistration.shouldRegister(appBundlePath: Bundle.main.bundlePath,
                                                               homeDirectory: NSHomeDirectory(), hasAttempted: false)
        let status = SMAppService.mainApp.status
        login.isEnabled = installed
        login.state = status == .enabled ? .on : .off
        loginStatus.stringValue = !installed ? "请先将 TapAsk 安装到“应用程序”。"
            : status == .requiresApproval ? "请在系统设置的登录项中允许 TapAsk。" : ""
        automaticUpdates.isEnabled = updater != nil
        automaticUpdates.state = updater?.automaticUpdatesEnabled == true ? .on : .off
        check.isEnabled = updater?.canCheckForUpdates == true
        updateStatus.stringValue = updater?.updateReadyToInstall == true ? "更新已下载" :
            updater?.updateAvailable == true ? "有可用更新" : ""
    }

    func toggleMenuItems() -> [NSMenuItem] {
        refresh()
        let loginItem = NSMenuItem(title: "登录时启动 TapAsk", action: #selector(toggleLoginFromMenu(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = login.state
        loginItem.isEnabled = login.isEnabled
        let updatesItem = NSMenuItem(title: "自动检查并下载更新", action: #selector(toggleUpdatesFromMenu(_:)), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.state = automaticUpdates.state
        updatesItem.isEnabled = automaticUpdates.isEnabled
        var items = [loginItem]
        if !loginStatus.stringValue.isEmpty {
            let status = NSMenuItem(title: loginStatus.stringValue, action: nil, keyEquivalent: "")
            status.isEnabled = false
            items.append(status)
        }
        items.append(updatesItem)
        return items
    }

    func updateMenuItems() -> [NSMenuItem] {
        refresh()
        let checkItem = NSMenuItem(title: "检查更新…", action: #selector(checkUpdates(_:)), keyEquivalent: "")
        checkItem.target = self
        checkItem.isEnabled = check.isEnabled
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let versionItem = NSMenuItem(title: "TapAsk \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        var items = [checkItem]
        if !updateStatus.stringValue.isEmpty {
            let status = NSMenuItem(title: updateStatus.stringValue, action: nil, keyEquivalent: "")
            status.isEnabled = false
            items.append(status)
        }
        items.append(versionItem)
        return items
    }

    @objc private func toggleLoginFromMenu(_ sender: Any?) {
        login.state = login.state == .on ? .off : .on
        changeLogin(login)
    }

    @objc private func toggleUpdatesFromMenu(_ sender: Any?) {
        automaticUpdates.state = automaticUpdates.state == .on ? .off : .on
        changeUpdates(automaticUpdates)
    }

    @objc private func changeLogin(_ sender: NSButton) {
        defaults.set(true, forKey: "LoginItemRegistrationAttempted")
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法更改登录时启动"
            alert.runModal()
        }
        refresh()
    }

    @objc private func changeUpdates(_ sender: NSButton) {
        updater?.automaticUpdatesEnabled = sender.state == .on
        refresh()
    }

    @objc private func checkUpdates(_ sender: Any?) { updater?.checkForUpdates(); refresh() }
}

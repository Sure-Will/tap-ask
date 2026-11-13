import AppKit
import Sparkle
import WebKit
import XCTest
import TapAskCore
@testable import TapAsk

final class AppUpdaterTests: XCTestCase {
    @MainActor
    func testPreparedUpdateCanBeInstalledFromStatusMenu() throws {
        _ = NSApplication.shared
        let updater = FakeAppUpdater()
        let suite = "TapAsk.ManualUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = AppDelegate(defaults: defaults, updater: updater, websiteDataStore: .nonPersistent())
        owner.configurePanel()
        defer { owner.removeAllSessions(); owner.panel.orderOut(nil) }
        XCTAssertFalse(owner.makeCurrentStatusMenu().items.contains { $0.title == "立即安装并重启" })
        updater.updateReadyToInstall = true
        updater.preparedUpdateVersion = "99"
        let menu = owner.makeCurrentStatusMenu()
        let index = try XCTUnwrap(menu.items.firstIndex { $0.title == "立即安装并重启" })
        menu.performActionForItem(at: index)
        XCTAssertEqual(updater.installCount, 1)
        XCTAssertTrue(IdleUpdateRelaunch.consume(currentVersion: "99", defaults: defaults))
    }

    @MainActor
    func testIdleUpdateWaitsWhenPageSafetyCannotBeVerified() throws {
        _ = NSApplication.shared
        let catalog = try SharedFixtures.catalog()
        let updater = FakeAppUpdater()
        updater.preparedUpdateVersion = "99"
        let suite = "TapAsk.IdleUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = ContinuousClock.now
        let owner = AppDelegate(catalog: catalog, defaults: defaults, updater: updater, websiteDataStore: .nonPersistent(),
                                retentionNow: { now })
        owner.configurePanel()
        defer { owner.closeLoginPopup(restoreFocus: false); owner.removeAllSessions(); owner.panel.orderOut(nil) }
        let session = owner.makeSession(for: catalog.providers[0])
        owner.displaySession(session)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        _ = owner.openLoginPopup(configuration: configuration, policy: session.policy, initialURL: nil)
        owner.panel.onCancel?()
        now = now.advanced(by: .seconds(1_800))
        updater.updateReadyToInstall = true
        owner.releaseIdleCurrentPageIfNeeded()
        XCTAssertNil(owner.currentSession)
        XCTAssertNotNil(owner.loginPopup)
        XCTAssertEqual(updater.installCount, 0)
        owner.closeLoginPopup(restoreFocus: false)
        XCTAssertEqual(updater.installCount, 0)
        XCTAssertFalse(IdleUpdateRelaunch.consume(currentVersion: "99", defaults: defaults))
        XCTAssertTrue(owner.makeCurrentStatusMenu().items.contains { $0.title == "立即安装并重启" })
    }
    @MainActor
    func testSettingsControlsRouteToInjectedUpdater() throws {
        _ = NSApplication.shared
        let updater = FakeAppUpdater()
        let owner = AppDelegate(updater: updater, websiteDataStore: .nonPersistent())
        XCTAssertEqual(updater.startCount, 0)
        owner.startUpdater()
        XCTAssertEqual(updater.startCount, 1)
        updater.canCheckForUpdates = true
        let view = SettingsGeneralView(updater: updater, defaults: .standard)
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        let automatic = try XCTUnwrap(buttons.first { $0.title == "自动检查并下载更新" })
        let check = try XCTUnwrap(buttons.first { $0.title == "检查更新…" })
        automatic.performClick(nil)
        XCTAssertTrue(updater.automaticUpdatesEnabled)
        check.performClick(nil)
        XCTAssertEqual(updater.checkCount, 1)
        updater.updateReadyToInstall = true
        view.refresh()
        XCTAssertTrue(view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "更新已下载" })
    }

    @MainActor
    func testUnavailableUpdaterDisablesUpdateControls() throws {
        _ = NSApplication.shared
        let view = SettingsGeneralView(updater: nil, defaults: .standard)
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        XCTAssertFalse(try XCTUnwrap(buttons.first { $0.title == "自动检查并下载更新" }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(buttons.first { $0.title == "检查更新…" }).isEnabled)
    }

    @MainActor
    func testScheduledUpdatesRemainSilentAndNormalExitDoesNotInvokeImmediateInstallation() throws {
        _ = NSApplication.shared
        let updater = AppUpdater()
        XCTAssertFalse(updater.controller.updater.canCheckForUpdates,
                       "Constructing the controller must leave Sparkle stopped")
        XCTAssertTrue(updater.supportsGentleScheduledUpdateReminders)
        let item = try XCTUnwrap(SUAppcastItem(dictionary: [
            "enclosure": ["url": "https://example.invalid/TapAsk.zip", "sparkle:version": "99"],
        ]))
        XCTAssertFalse(updater.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true))
        XCTAssertFalse(updater.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: false))
        let state = try updateState(stage: .downloaded, userInitiated: false)
        updater.standardUserDriverWillHandleShowingUpdate(false, forUpdate: item, state: state)
        XCTAssertTrue(updater.updateAvailable)
        XCTAssertFalse(updater.updateReadyToInstall, "Downloaded UI state alone does not establish installation on quit")
        updater.standardUserDriverWillFinishUpdateSession()
        XCTAssertFalse(updater.updateAvailable)
        updater.standardUserDriverWillHandleShowingUpdate(false, forUpdate: item, state: state)
        XCTAssertTrue(updater.updateAvailable)
        var installedImmediately = false
        XCTAssertTrue(updater.updater(updater.controller.updater, willInstallUpdateOnQuit: item,
                                     immediateInstallationBlock: { installedImmediately = true }))
        XCTAssertTrue(updater.updateReadyToInstall)
        XCTAssertEqual(updater.preparedUpdateVersion, "99")
        updater.standardUserDriverDidReceiveUserAttention(forUpdate: item)
        XCTAssertFalse(updater.updateAvailable)
        XCTAssertTrue(updater.updateReadyToInstall)
        updater.standardUserDriverWillFinishUpdateSession()
        XCTAssertTrue(updater.updateReadyToInstall)
        updater.standardUserDriverWillHandleShowingUpdate(true, forUpdate: item,
            state: try updateState(stage: .downloaded, userInitiated: true))
        XCTAssertFalse(updater.updateAvailable)
        XCTAssertFalse(installedImmediately)
        let owner = AppDelegate(updater: updater, websiteDataStore: .nonPersistent())
        owner.configurePanel()
        owner.panel.onCancel?() // The production hide path must remain unrelated to updating.
        XCTAssertFalse(installedImmediately)
        owner.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertFalse(installedImmediately)
        XCTAssertTrue(owner.sessions.isEmpty)
        XCTAssertNil(owner.backgroundPageReleaseTask)
        updater.installAndRestart()
        XCTAssertTrue(installedImmediately)
    }

    @MainActor
    func testSkippingPreparedUpdateClearsReadyButDismissingKeepsInstallationOnQuit() throws {
        let updater = AppUpdater()
        let item = try XCTUnwrap(SUAppcastItem(dictionary: [
            "enclosure": ["url": "https://example.invalid/TapAsk.zip", "sparkle:version": "99"],
        ]))
        let state = try updateState(stage: .installing, userInitiated: true)
        var installedImmediately = false
        XCTAssertTrue(updater.updater(updater.controller.updater, willInstallUpdateOnQuit: item,
                                     immediateInstallationBlock: { installedImmediately = true }))
        XCTAssertTrue(updater.updateReadyToInstall)
        // Invoke Sparkle's optional delegate callback so the regression also
        // executes against the old implementation where it was unhandled.
        let delegate: any SPUUpdaterDelegate = updater
        delegate.updater?(updater.controller.updater, userDidMake: .dismiss, forUpdate: item, state: state)
        XCTAssertTrue(updater.updateReadyToInstall, "Dismissing keeps Sparkle's scheduled installation")
        delegate.updater?(updater.controller.updater, userDidMake: .skip, forUpdate: item, state: state)
        XCTAssertFalse(updater.updateReadyToInstall, "Skipping cancels Sparkle's prepared installation")
        updater.installAndRestart()
        XCTAssertFalse(installedImmediately)
    }

    // Sparkle 2.10.1 supports NSSecureCoding but exposes no public state initializer.
    // Build a serialized fixture using the pinned version's documented source keys.
    private func updateState(stage: SPUUserUpdateStage, userInitiated: Bool) throws -> SPUUserUpdateState {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        encoder.encode(stage.rawValue, forKey: "SPUUserUpdateStateStage")
        encoder.encode(userInitiated, forKey: "SPUUserUpdateStateUserInitiated")
        encoder.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: encoder.encodedData)
        defer { decoder.finishDecoding() }
        return try XCTUnwrap(SPUUserUpdateState(coder: decoder))
    }


}

@MainActor
private final class FakeAppUpdater: AppUpdating {
    var canCheckForUpdates = false
    var automaticUpdatesEnabled = false
    var updateReadyToInstall = false
    var updateAvailable = false
    var preparedUpdateVersion: String?
    var startCount = 0
    var checkCount = 0
    var installCount = 0
    func start() { startCount += 1 }
    func checkForUpdates() { checkCount += 1 }
    func installAndRestart() { installCount += 1 }
}

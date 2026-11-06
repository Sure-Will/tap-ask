import AppKit
import Sparkle
import WebKit
import XCTest
@testable import TapAsk

final class AppUpdaterTests: XCTestCase {
    @MainActor
    func testConstructionDoesNotStartAndActionsRouteToInjectedUpdater() {
        let updater = FakeAppUpdater()
        let owner = AppDelegate(updater: updater, websiteDataStore: .nonPersistent())
        XCTAssertEqual(updater.startCount, 0)
        XCTAssertEqual(updater.checkCount, 0)
        owner.startUpdater()
        XCTAssertEqual(updater.startCount, 1)
        owner.checkForUpdates(nil)
        XCTAssertEqual(updater.checkCount, 1)
        owner.toggleAutomaticUpdates(nil)
        XCTAssertTrue(updater.automaticUpdatesEnabled)
        owner.toggleAutomaticUpdates(nil)
        XCTAssertFalse(updater.automaticUpdatesEnabled)
    }

    @MainActor
    func testMenuValidationReflectsBusyAutomaticAndReadyState() {
        let updater = FakeAppUpdater()
        let owner = AppDelegate(updater: updater, websiteDataStore: .nonPersistent())
        let items = updateItems(owner)
        XCTAssertFalse(owner.validateMenuItem(items[0]))
        XCTAssertEqual(items[0].title, "检查更新…")
        XCTAssertTrue(owner.validateMenuItem(items[1]))
        XCTAssertEqual(items[1].state, .off)
        updater.updateAvailable = true
        XCTAssertFalse(owner.validateMenuItem(items[0]), "Background downloads must still respect Sparkle canCheckForUpdates")
        XCTAssertEqual(items[0].title, "查看更新…")
        updater.canCheckForUpdates = true
        XCTAssertTrue(owner.validateMenuItem(items[0]), "A resumable reminder uses Sparkle's standard check action")
        updater.updateAvailable = false
        updater.automaticUpdatesEnabled = true
        updater.updateReadyToInstall = true
        XCTAssertTrue(owner.validateMenuItem(items[0]))
        XCTAssertEqual(items[0].title, "检查更新…（退出时安装）")
        XCTAssertTrue(owner.validateMenuItem(items[1]))
        XCTAssertEqual(items[1].state, .on)
        updater.updateReadyToInstall = false
        XCTAssertTrue(owner.validateMenuItem(items[0]))
        XCTAssertEqual(items[0].title, "检查更新…")
    }

    @MainActor
    func testMissingUpdaterDisablesMenusAndSeparateMenusOwnSeparateItems() {
        let owner = AppDelegate(websiteDataStore: .nonPersistent())
        let main = NSMenu()
        let status = NSMenu()
        let mainItems = updateItems(owner)
        let statusItems = updateItems(owner)
        for item in mainItems { main.addItem(item) }
        for item in statusItems { status.addItem(item) }
        for (first, second) in zip(mainItems, statusItems) {
            XCTAssertFalse(first === second)
            XCTAssertTrue(first.menu === main)
            XCTAssertTrue(second.menu === status)
            XCTAssertFalse(owner.validateMenuItem(first))
        }
        XCTAssertEqual(mainItems[1].state, .off)
        owner.checkForUpdates(nil)
        owner.toggleAutomaticUpdates(nil)
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
        XCTAssertFalse(updater.updater(updater.controller.updater, willInstallUpdateOnQuit: item,
                                      immediateInstallationBlock: { installedImmediately = true }))
        XCTAssertTrue(updater.updateReadyToInstall)
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
    }

    @MainActor
    func testSkippingPreparedUpdateClearsReadyButDismissingKeepsInstallationOnQuit() throws {
        let updater = AppUpdater()
        let item = try XCTUnwrap(SUAppcastItem(dictionary: [
            "enclosure": ["url": "https://example.invalid/TapAsk.zip", "sparkle:version": "99"],
        ]))
        let state = try updateState(stage: .installing, userInitiated: true)
        var installedImmediately = false
        XCTAssertFalse(updater.updater(updater.controller.updater, willInstallUpdateOnQuit: item,
                                      immediateInstallationBlock: { installedImmediately = true }))
        XCTAssertTrue(updater.updateReadyToInstall)
        // Invoke Sparkle's optional delegate callback so the regression also
        // executes against the old implementation where it was unhandled.
        let delegate: any SPUUpdaterDelegate = updater
        delegate.updater?(updater.controller.updater, userDidMake: .dismiss, forUpdate: item, state: state)
        XCTAssertTrue(updater.updateReadyToInstall, "Dismissing keeps Sparkle's scheduled installation")
        delegate.updater?(updater.controller.updater, userDidMake: .skip, forUpdate: item, state: state)
        XCTAssertFalse(updater.updateReadyToInstall, "Skipping cancels Sparkle's prepared installation")
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

    @MainActor
    private func updateItems(_ owner: AppDelegate) -> [NSMenuItem] {
        makeUpdateMenuItems(target: owner, checkAction: #selector(AppDelegate.checkForUpdates(_:)),
                            automaticAction: #selector(AppDelegate.toggleAutomaticUpdates(_:)))
    }
}

@MainActor
private final class FakeAppUpdater: AppUpdating {
    var canCheckForUpdates = false
    var automaticUpdatesEnabled = false
    var updateReadyToInstall = false
    var updateAvailable = false
    var startCount = 0
    var checkCount = 0
    func start() { startCount += 1 }
    func checkForUpdates() { checkCount += 1 }
}

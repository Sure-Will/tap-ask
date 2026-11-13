import AppKit
import Sparkle

@MainActor
protocol AppUpdating: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticUpdatesEnabled: Bool { get set }
    var updateReadyToInstall: Bool { get }
    var updateAvailable: Bool { get }
    var preparedUpdateVersion: String? { get }
    func start()
    func checkForUpdates()
    func installAndRestart()
}

/// Sparkle owns downloading and installation on normal application termination.
/// Creating this object does not start an updater or schedule network requests.
@MainActor
// Sparkle invokes its standard user driver delegate on the main thread, but
// its Objective-C protocol does not carry Swift actor annotations.
final class AppUpdater: NSObject, AppUpdating, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var controller: SPUStandardUpdaterController!
    private(set) var updateReadyToInstall = false
    private(set) var updateAvailable = false
    private(set) var preparedUpdateVersion: String?
    private var immediateInstallation: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                updaterDelegate: self, userDriverDelegate: self)
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticUpdatesEnabled: Bool {
        get {
            controller.updater.automaticallyChecksForUpdates
                && controller.updater.automaticallyDownloadsUpdates
        }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func start() {
        // swift run and XCTest do not provide an installable application bundle.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.startUpdater()
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func installAndRestart() { immediateInstallation?() }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        // The standard driver always owns user-initiated UI. For scheduled
        // updates, expose a menu reminder even when silent installation needs
        // user authorization (for example a critical or major update).
        updateAvailable = !handleShowingUpdate && !state.userInitiated
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
        // A completed UI session does not cancel installation already scheduled
        // on quit; only willInstallUpdateOnQuit establishes that separate state.
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip, state.stage == .installing {
            updateReadyToInstall = false
            immediateInstallation = nil
            preparedUpdateVersion = nil
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        updateReadyToInstall = true
        preparedUpdateVersion = item.versionString
        immediateInstallation = immediateInstallHandler
        return true
    }
}

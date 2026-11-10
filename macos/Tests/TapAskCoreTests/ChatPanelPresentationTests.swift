import AppKit
import XCTest
@testable import TapAsk

/// Requires WindowServer. Uses synthetic screen bounds without changing system settings.
final class ChatPanelPresentationTests: XCTestCase {
    @MainActor
    func testTinyScreenFitsActualPanelAndNormalScreenRestoresMinimum() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let suite = "TapAsk.ChatPanelPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = ChatPanel(defaults: defaults)
        defer { panel.orderOut(nil) }
        let tinyVisible = NSRect(origin: screen.visibleFrame.origin, size: NSSize(width: 320, height: 400))

        panel.prepareForPresentation(screenFrame: screen.frame, visibleFrame: tinyVisible)
        XCTAssertEqual(panel.frame, tinyVisible)
        XCTAssertEqual(panel.minSize, tinyVisible.size)
        XCTAssertEqual(defaults.string(forKey: "PanelFrame"), NSStringFromRect(panel.frame))
        panel.prepareForPresentation(screenFrame: screen.frame, visibleFrame: tinyVisible)
        XCTAssertEqual(panel.frame, tinyVisible, "Repeated presentation must remain stable")

        let restored = ChatPanel(defaults: defaults)
        defer { restored.orderOut(nil) }
        restored.prepareForPresentation(screenFrame: screen.frame, visibleFrame: tinyVisible)
        XCTAssertEqual(restored.frame, tinyVisible, "A reduced saved frame must survive relaunch")

        panel.prepareForPresentation(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        XCTAssertEqual(panel.minSize, NSSize(width: 360, height: 480))
        XCTAssertEqual(panel.frame.size, NSSize(width: 360, height: 480))
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
    }

    @MainActor
    func testMoveAndResizeCallbacksOnlySaveUntilNextPresentation() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let suite = "TapAsk.ChatPanelPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = ChatPanel(defaults: defaults)
        defer { panel.orderOut(nil) }
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.minX - 100, y: visible.minY,
                              width: 480, height: 720), display: false)
        let userFrame = panel.frame
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        panel.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: panel))
        XCTAssertEqual(panel.frame, userFrame)
        XCTAssertEqual(defaults.string(forKey: "PanelFrame"), NSStringFromRect(userFrame))

        panel.prepareForPresentation(screenFrame: screen.frame, visibleFrame: visible)
        XCTAssertTrue(visible.contains(panel.frame))
        XCTAssertEqual(panel.frame.minX, visible.minX)
    }
}

import CoreGraphics

/// Window frames use AppKit coordinates: the y axis points up.
public func loginPopupFrame(parentFrame: CGRect, desiredSize: CGSize, visibleFrame: CGRect) -> CGRect {
    var size = desiredSize
    var bounds = visibleFrame
    if size.width > visibleFrame.width || size.height > visibleFrame.height {
        size.width = min(visibleFrame.width, max(360, min(size.width, visibleFrame.width - 16)))
        size.height = min(visibleFrame.height, max(480, min(size.height, visibleFrame.height - 16)))
        // Keep 8pt around a reduced popup when possible; the minimum size takes
        // precedence over that margin, and the screen takes precedence over both.
        bounds = visibleFrame.insetBy(dx: min(8, (visibleFrame.width - size.width) / 2),
                                     dy: min(8, (visibleFrame.height - size.height) / 2))
    }

    let right = parentFrame.maxX + 12
    let left = parentFrame.minX - 12 - size.width
    let x: CGFloat
    if right >= bounds.minX, right + size.width <= bounds.maxX {
        x = right
    } else if left >= bounds.minX, left + size.width <= bounds.maxX {
        x = left
    } else {
        // Overlay the parent, centered horizontally and still top-aligned.
        x = parentFrame.midX - size.width / 2
    }
    return CGRect(x: min(max(x, bounds.minX), bounds.maxX - size.width),
                  y: min(max(parentFrame.maxY - size.height, bounds.minY), bounds.maxY - size.height),
                  width: size.width, height: size.height)
}

/// One popup's placement history, independent of AppKit and screen enumeration.
public struct LoginPopupPlacement {
    private var lastScreenFrame: CGRect?
    private var userAdjustedFrame = false

    public init() {}

    public mutating func userDidAdjustFrame() { userAdjustedFrame = true }

    /// Nil preserves the current frame. Full screen bounds distinguish displays
    /// without treating a Dock/menu-bar change as a move to another display.
    public mutating func frameForPresentation(parentFrame: CGRect, desiredSize: CGSize,
                                             screenFrame: CGRect, visibleFrame: CGRect) -> CGRect? {
        guard !userAdjustedFrame, lastScreenFrame != screenFrame else { return nil }
        lastScreenFrame = screenFrame
        return loginPopupFrame(parentFrame: parentFrame, desiredSize: desiredSize, visibleFrame: visibleFrame)
    }
}

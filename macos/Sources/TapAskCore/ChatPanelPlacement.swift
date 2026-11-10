import CoreGraphics

/// Window frames use AppKit coordinates: the y axis points up.
public func chatPanelFrame(currentFrame: CGRect, savedFrame: CGRect?,
                           screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
    let preferred = savedFrame ?? currentFrame
    let size = CGSize(width: min(visibleFrame.width, max(360, preferred.width)),
                      height: min(visibleFrame.height, max(480, preferred.height)))
    let staysOnScreen = savedFrame.map {
        screenFrame.contains(CGPoint(x: $0.midX, y: $0.midY))
    } ?? false
    let origin = staysOnScreen ? preferred.origin
        : CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
    return CGRect(x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
                  y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height),
                  width: size.width, height: size.height)
}

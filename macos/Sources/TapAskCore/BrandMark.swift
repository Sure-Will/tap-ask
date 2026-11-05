import CoreGraphics

/// Shared geometry for both icons. Coordinates follow SVG: origin at top left, y down.
public enum BrandMark {
    public static let viewBox = CGRect(x: 0, y: 0, width: 22, height: 18)

    public static var screenPath: CGPath {
        roundedRect(minX: 1, minY: 2.5, maxX: 21, maxY: 15.5, radius: 2.4)
    }

    public static var gapPath: CGPath {
        roundedRect(minX: 6.6, minY: 3.7, maxX: 15.4, maxY: 14.3, radius: 1.8)
    }

    public static var windowPath: CGPath {
        roundedRect(minX: 7.8, minY: 4.9, maxX: 14.2, maxY: 13.1, radius: 1)
    }

    public static var starPath: CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: 11, y: 7.8)
        let inset: CGFloat = 0.3
        let top = CGPoint(x: center.x, y: 5.9)
        path.move(to: top)
        path.addQuadCurve(to: CGPoint(x: 12.8, y: center.y),
                          control: CGPoint(x: center.x + inset, y: center.y - inset))
        path.addQuadCurve(to: CGPoint(x: center.x, y: 9.7),
                          control: CGPoint(x: center.x + inset, y: center.y + inset))
        path.addQuadCurve(to: CGPoint(x: 9.2, y: center.y),
                          control: CGPoint(x: center.x - inset, y: center.y + inset))
        path.addQuadCurve(to: top,
                          control: CGPoint(x: center.x - inset, y: center.y - inset))
        path.closeSubpath()
        return path
    }

    public static var inputPath: CGPath {
        roundedRect(minX: 8.7, minY: 10.6, maxX: 13.3, maxY: 12.1, radius: 0.75)
    }

    /// Always fill with even-odd. The app icon paints the star over a solid window.
    public static func path(cutOutStar: Bool = true) -> CGPath {
        let path = CGMutablePath()
        for part in [screenPath, gapPath, windowPath, inputPath] { path.addPath(part) }
        if cutOutStar { path.addPath(starPath) }
        return path
    }

    private static func roundedRect(minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat,
                                    radius: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
               cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

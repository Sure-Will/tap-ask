import CoreGraphics
import Foundation
import ImageIO
import TapAskCore
import UniformTypeIdentifiers

@main
enum MakeIcons {
    static func main() {
        do {
            try generate()
        } catch {
            FileHandle.standardError.write(Data("make-icons: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func generate() throws {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let iconset = package.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
        let resources = package.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        // Standard macOS iconset: 16…1024 physical pixels, including Retina variants.
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let url = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                try writePNG(size: points * scale, to: url)
            }
        }

        let output = resources.appendingPathComponent("AppIcon.icns")
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", "-o", output.path, iconset.path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else {
            throw IconError.conversionFailed(iconutil.terminationStatus)
        }
        print("Generated \(output.path)")
    }

    private static func writePNG(size: Int, to url: URL) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw IconError.bitmapCreationFailed(size)
        }
        context.translateBy(x: 0, y: CGFloat(size))
        let scale = CGFloat(size) / 1024
        context.scaleBy(x: scale, y: -scale)

        let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
        context.setFillColor(color(0x24221F))
        context.addPath(CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil))
        context.fillPath()

        let mark = BrandMark.path(cutOutStar: false)
        let bounds = mark.boundingBoxOfPath
        let markScale = plate.width * 0.62 / bounds.width
        context.translateBy(x: plate.midX - bounds.midX * markScale,
                            y: plate.midY - bounds.midY * markScale)
        context.scaleBy(x: markScale, y: markScale)
        context.setFillColor(color(0xF4F1EA))
        context.addPath(mark)
        context.drawPath(using: .eoFill)
        context.setFillColor(color(0xF2A93B))
        context.addPath(BrandMark.starPath)
        context.fillPath()

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                1, nil) else {
            throw IconError.pngCreationFailed(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconError.pngCreationFailed(url) }
    }

    private static func color(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

private enum IconError: Error, CustomStringConvertible {
    case bitmapCreationFailed(Int)
    case pngCreationFailed(URL)
    case conversionFailed(Int32)

    var description: String {
        switch self {
        case .bitmapCreationFailed(let size):
            return "Could not create a \(size)px bitmap."
        case .pngCreationFailed(let url):
            return "Could not write PNG: \(url.path)"
        case .conversionFailed(let status):
            return "iconutil exited with \(status). PNGs remain in build/AppIcon.iconset."
        }
    }
}

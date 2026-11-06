// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapAsk",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapAskCore", targets: ["TapAskCore"]),
        .executable(name: "TapAsk", targets: ["TapAsk"]),
        .executable(name: "make-icons", targets: ["make-icons"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "TapAskCore"),
        .executableTarget(name: "TapAsk", dependencies: ["TapAskCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "make-icons", dependencies: ["TapAskCore"], path: "Sources/MakeIcons"),
        .testTarget(name: "TapAskCoreTests", dependencies: ["TapAskCore", "TapAsk"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapAsk",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapAskCore", targets: ["TapAskCore"]),
        .executable(name: "TapAsk", targets: ["TapAsk"]),
    ],
    targets: [
        .target(name: "TapAskCore"),
        .executableTarget(name: "TapAsk", dependencies: ["TapAskCore"]),
        .testTarget(name: "TapAskCoreTests", dependencies: ["TapAskCore", "TapAsk"]),
    ]
)

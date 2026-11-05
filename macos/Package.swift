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
    targets: [
        .target(name: "TapAskCore"),
        .executableTarget(name: "TapAsk", dependencies: ["TapAskCore"]),
        .executableTarget(name: "make-icons", dependencies: ["TapAskCore"], path: "Sources/MakeIcons"),
        .testTarget(name: "TapAskCoreTests", dependencies: ["TapAskCore", "TapAsk"]),
    ]
)

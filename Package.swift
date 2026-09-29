// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clutter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClutterCore"),
        .executableTarget(name: "Clutter", dependencies: ["ClutterCore"]),
        .testTarget(name: "ClutterCoreTests", dependencies: ["ClutterCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clutter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    ],
    targets: [
        .target(name: "ClutterCore", dependencies: ["KeyboardShortcuts"]),
        .executableTarget(name: "Clutter", dependencies: ["ClutterCore", "KeyboardShortcuts"]),
        .testTarget(name: "ClutterCoreTests", dependencies: ["ClutterCore", "KeyboardShortcuts"]),
    ]
)

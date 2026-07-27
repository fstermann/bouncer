// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "BouncerModules",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BouncerFoundation", targets: ["BouncerFoundation"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "MenuBar", targets: ["MenuBar"]),
        .library(name: "BouncerUI", targets: ["BouncerUI"]),
    ],
    targets: [
        .target(name: "BouncerFoundation"),
        .target(name: "Settings", dependencies: ["BouncerFoundation"]),
        .target(name: "MenuBar", dependencies: ["BouncerFoundation", "Settings"]),
        .target(name: "BouncerUI", dependencies: ["MenuBar", "Settings"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings"]),
    ],
    swiftLanguageModes: [.v6]
)

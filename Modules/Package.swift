// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "BouncerModules",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BouncerFoundation", targets: ["BouncerFoundation"]),
        .library(name: "Hotkeys", targets: ["Hotkeys"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "MenuBar", targets: ["MenuBar"]),
        .library(name: "BouncerUI", targets: ["BouncerUI"]),
    ],
    targets: [
        .target(name: "BouncerFoundation"),
        .target(name: "Hotkeys", dependencies: ["BouncerFoundation"]),
        .target(name: "Settings", dependencies: ["BouncerFoundation", "Hotkeys"]),
        .target(name: "MenuBar", dependencies: ["BouncerFoundation", "Settings"]),
        .target(name: "BouncerUI", dependencies: ["MenuBar", "Settings", "Hotkeys"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings"]),
    ],
    swiftLanguageModes: [.v6]
)

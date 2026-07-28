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
        .library(name: "StandaloneBar", targets: ["StandaloneBar"]),
    ],
    targets: [
        .target(name: "BouncerFoundation"),
        .target(name: "Settings", dependencies: ["BouncerFoundation"]),
        .target(name: "MenuBar", dependencies: ["BouncerFoundation", "Settings"]),
        .target(name: "BouncerUI", dependencies: ["MenuBar", "Settings"]),
        // Behind its own module because it is the one feature that asks for permissions.
        .target(name: "StandaloneBar", dependencies: ["BouncerFoundation", "Settings", "MenuBar"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings"]),
        .testTarget(name: "StandaloneBarTests", dependencies: ["StandaloneBar"]),
    ],
    swiftLanguageModes: [.v6]
)

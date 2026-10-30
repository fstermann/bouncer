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
        .library(name: "Updates", targets: ["Updates"]),
        .library(name: "Todos", targets: ["Todos"]),
    ],
    dependencies: [
        // Keep in step with the Sparkle version in project.yml.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5"),
    ],
    targets: [
        .target(name: "BouncerFoundation"),
        .target(name: "Settings", dependencies: ["BouncerFoundation"]),
        .target(name: "MenuBar", dependencies: ["BouncerFoundation", "Settings"]),
        .target(name: "BouncerUI", dependencies: ["MenuBar", "Settings", "StandaloneBar", "Todos", "Updates"]),
        .target(name: "Updates", dependencies: ["BouncerFoundation", .product(name: "Sparkle", package: "Sparkle")]),
        // Behind its own module because it is the one feature that asks for permissions.
        .target(name: "StandaloneBar", dependencies: ["BouncerFoundation", "MenuBar"]),
        .target(name: "Todos", dependencies: ["BouncerFoundation", "MenuBar", "Settings"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings"]),
        .testTarget(name: "StandaloneBarTests", dependencies: ["StandaloneBar"]),
        .testTarget(name: "TodosTests", dependencies: ["Todos"]),
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
    ],
    swiftLanguageModes: [.v6]
)

// `#if DEV` marks code that only Bouncer Dev contains. Xcode builds packages as debug only under a
// configuration named Debug, so that name stays.
for target in package.targets {
    target.swiftSettings = [.define("DEV", .when(configuration: .debug))]
}

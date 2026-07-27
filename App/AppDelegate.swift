import AppKit
import BouncerFoundation
import BouncerUI
import MenuBar
import Settings
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var menuBar = MenuBarManager(
        settings: settings,
        iconImage: Self.templateImage(named: "MenuBarIcon"),
        iconOpenImage: Self.templateImage(named: "MenuBarIconOpen"),
        dividerImage: Self.templateImage(named: "SectionEndIcon"),
        outerDividerImage: Self.templateImage(named: "SectionStartIcon")
    )
    private lazy var reveal = RevealController(manager: menuBar, settings: settings)
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.iconMenu = makeIconMenu()
        reveal.start()
        Log.app.info("Bouncer launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.flush()
    }

    /// Fitted to the menu bar's usable height; the width follows the asset's aspect.
    /// Every Bouncer glyph is drawn in the same 96-unit box, so one height keeps the
    /// mark and the boundary glyphs the same size in the bar.
    private static func templateImage(named name: String) -> NSImage? {
        guard let image = NSImage(named: name) else {
            Log.app.error("\(name, privacy: .public) missing from the asset catalog")
            return nil
        }
        // Kept low so the mark is no wider than a typical square menu bar icon.
        let height = 10.5
        image.size = NSSize(width: height * image.size.width / image.size.height, height: height)
        image.isTemplate = true
        return image
    }

    private func makeIconMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Bouncer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, manager: menuBar)
            ))
            window.title = "Bouncer Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

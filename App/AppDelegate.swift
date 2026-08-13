import AppKit
import BouncerFoundation
import BouncerUI
import MenuBar
import Settings
import StandaloneBar
import SwiftUI
import Updates

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
    private lazy var standaloneBar = StandaloneBarController(menuBar: menuBar, settings: settings)
    private let updates = UpdateController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.iconMenu = makeIconMenu()
        reveal.start()
        // After `reveal.start()`, which installs the default click behaviour: whether a
        // click reveals the menu bar or opens Bouncer's own bar is a preference, and
        // RevealController has no business knowing about the standalone bar.
        menuBar.onIconClick = { [weak self] in self?.handleIconClick() }
        reveal.onHoverReveal = { [weak self] in self?.handleHoverReveal() }
        updates.start()
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
        if UpdateController.isSupported {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
                .target = self
        }
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(Self.appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    /// "Bouncer", or "Bouncer Dev" in a Debug build. A dev build sits in the menu bar beside an
    /// installed Bouncer wearing the same glyph, so the words are the only way to tell whose
    /// menu and whose window you have in front of you.
    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Bouncer"
    }

    /// A left click either walks the menu bar open, or opens Bouncer's own bar.
    private func handleIconClick() {
        guard settings.preferences.showItemsInBar else {
            menuBar.toggle()
            return
        }
        guard hasStandaloneBarPermissions() else { return }
        Task { await standaloneBar.toggle() }
    }

    /// The pointer reaching the menu bar shows the hidden section wherever the user has asked
    /// for it — walking the bar open, or opening Bouncer's own.
    ///
    /// Permissions are preflighted rather than requested: a pointer in the menu bar is not a
    /// request for the bar, and prompting on it would put a dialog up for simply moving the
    /// mouse. The bar stays behind a click until both are granted.
    private func handleHoverReveal() {
        guard settings.preferences.showItemsInBar else {
            menuBar.setVisibility(.revealed)
            return
        }
        guard CGPreflightScreenCaptureAccess() else { return }
        Task { await standaloneBar.open() }
    }

    /// Asks for the two permissions the standalone bar needs, at the moment the user asks
    /// for the bar — never at launch, and never for anything else Bouncer does.
    ///
    /// Both are reported rather than failing quietly. Screen Recording in particular only
    /// takes effect on the next launch, and without saying so the bar simply does nothing.
    private func hasStandaloneBarPermissions() -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            Log.app.error("Standalone bar: requesting Screen Recording; Bouncer must be restarted after granting")
            CGRequestScreenCaptureAccess()
            return false
        }
        if !ClickForwarder.isPermitted {
            Log.app.error("Standalone bar: requesting Accessibility; replicas will not be clickable until granted")
            ClickForwarder.requestPermission()
            // The bar is still worth showing: the items are visible, just not yet clickable.
        }
        return true
    }

    @objc private func checkForUpdates() {
        updates.checkForUpdates()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, updates: updates)
            )
            hosting.sizingOptions = [.preferredContentSize]
            // The style mask has to be set at init; assigning it afterwards drops the
            // layout the hosting controller established and the first tab renders empty.
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.title = "\(Self.appName) Settings"
            window.setContentSize(hosting.view.fittingSize)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

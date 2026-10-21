import AppKit
import BouncerFoundation
import BouncerUI
import MenuBar
import Settings
import StandaloneBar
import SwiftUI
import Todos
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
    private lazy var todos = TodoController(settings: settings)
    private var pageSwitches: ObservationLoop?
    private let permissions = StandaloneBarPermissions()
    private let updates = UpdateController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before the menu is built: whether it carries a "Check for Updates…" item depends on
        // whether the updater actually started.
        updates.start()
        menuBar.iconMenu = makeIconMenu()
        reveal.start()
        // After `reveal.start()`, which installs the default click behaviour: whether a
        // click reveals the menu bar or opens Bouncer's own bar is a preference, and
        // RevealController has no business knowing about the standalone bar.
        menuBar.onIconClick = { [weak self] in self?.handleIconClick() }
        reveal.onHoverReveal = { [weak self] in self?.handleHoverReveal() }
        pageSwitches = ObservationLoop { [weak self] in self?.wirePageSwitches() }
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
        if updates.isRunning {
            let item = menu.addItem(
                withTitle: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
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
    ///
    /// The permissions are normally asked for when the bar is turned on, in Settings; this
    /// re-asks only as a fallback for a user who dismissed those prompts. Accessibility
    /// missing still opens the bar — the items show, they are just not clickable yet.
    private func handleIconClick() {
        guard settings.preferences.showItemsInBar else {
            menuBar.toggle()
            return
        }
        permissions.refresh()
        guard permissions.screenRecording == .granted else {
            Log.app.error("Standalone bar: Screen Recording not granted; requesting")
            permissions.request()
            return
        }
        Task { await standaloneBar.toggle() }
    }

    /// The pointer reaching the menu bar shows the hidden section wherever the user has asked
    /// for it — walking the bar open, or opening Bouncer's own.
    ///
    /// Permissions are preflighted rather than requested: a pointer in the menu bar is not a
    /// request for the bar, and prompting on it would put a dialog up for simply moving the
    /// mouse. The bar stays behind a click until both are granted.
    private func handleHoverReveal() {
        let preferences = settings.preferences
        if todos.isAvailable, !preferences.showItemsInBar || preferences.notchPage == .todos {
            Task { await todos.open() }
            return
        }
        guard settings.preferences.showItemsInBar else {
            menuBar.setVisibility(.revealed)
            return
        }
        guard StandaloneBarPermissions.screenRecordingGranted else { return }
        // With hover over the whole menu bar off, only the notch could have opened it.
        Task { await standaloneBar.open(closingWhenLeft: !settings.preferences.revealOnHover) }
    }

    /// Each page of the notch panel offers the other only while the other has something to show.
    private func wirePageSwitches() {
        let preferences = settings.preferences
        standaloneBar.onSwitchPage = nil
        todos.onSwitchPage = nil
        if preferences.todoFile != nil {
            standaloneBar.onSwitchPage = { [weak self] in self?.switchPage(to: .todos) }
        }
        // Only while there is a todo page to open, so ⌘⇧B is left to the apps otherwise.
        if preferences.todoFile == nil {
            if todos.onShortcut != nil { todos.onShortcut = nil }
        } else if todos.onShortcut == nil {
            todos.onShortcut = { [weak self] in self?.handleTodoShortcut() }
        }
        if preferences.showItemsInBar {
            todos.onSwitchPage = { [weak self] in self?.switchPage(to: .items) }
        }
    }

    /// Turns one page into the other, which hover then opens next time. The todo panel does the
    /// moving both ways: it grows out of the items panel and takes it away once covering it, or
    /// has it built underneath itself and shrinks into its shape before it shows.
    private func switchPage(to page: NotchPage) {
        settings.preferences.notchPage = page
        Task { [standaloneBar, todos, settings] in
            switch page {
            case .todos:
                await todos.open(from: standaloneBar.panelFrame) { await standaloneBar.close(animated: false) }
            case .items:
                await todos.close { shape in
                    await standaloneBar.open(closingWhenLeft: !settings.preferences.revealOnHover, takingShape: shape)
                }
            }
        }
    }

    /// ⌘⇧B opens the todo page, from the items page if that is up, and closes it again.
    private func handleTodoShortcut() {
        guard !standaloneBar.isOpen else { return switchPage(to: .todos) }
        Task { [todos] in
            todos.isOpen ? await todos.close() : await todos.open(closesOnLeave: false)
        }
    }

    @objc private func checkForUpdates() {
        updates.checkForUpdates()
    }

    @objc private func openSettings() {
        // A fresh hosting controller on every open: the window is reused, but its SwiftUI
        // content would otherwise keep the state it was first built with, so the view's mirrors
        // of Sparkle's and the login item's state would go stale when those change out of band.
        let hosting = NSHostingController(
            rootView: SettingsView(settings: settings, updates: updates, permissions: permissions)
        )
        hosting.sizingOptions = [.preferredContentSize]
        if settingsWindow == nil {
            // The style mask has to be set at init; assigning it afterwards drops the
            // layout the hosting controller established and the first tab renders empty.
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "\(Self.appName) Settings"
            window.isReleasedWhenClosed = false
            // Content runs under a transparent, title-less titlebar so the sidebar shade and the
            // divider reach the very top; only the traffic lights sit on top.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            settingsWindow = window
        }
        settingsWindow?.contentViewController = hosting
        settingsWindow?.setContentSize(hosting.view.fittingSize)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

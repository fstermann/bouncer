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
    private lazy var notes = NoteController(settings: settings)
    private var pageSwitches: ObservationLoop?
    private let permissions = StandaloneBarPermissions()
    private let updates = UpdateController()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    #if DEV
    private var harness: DevHarness?
    #endif

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
        reveal.onHoverReveal = { [weak self] screen, atNotch in self?.handleHoverReveal(on: screen, atNotch: atNotch) }
        pageSwitches = ObservationLoop { [weak self] in self?.wirePageSwitches() }
        if settings.isFirstLaunch { showWelcome() }
        #if DEV
        harness = DevHarness(controller: standaloneBar, menuBar: menuBar)
        harness?.listen()
        #endif
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

    /// "Bouncer", or "Bouncer Dev" in a Dev build. A dev build sits in the menu bar beside an
    /// installed Bouncer wearing the same glyph, so the words are the only way to tell whose
    /// menu and whose window you have in front of you.
    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Bouncer"
    }

    /// A left click either walks the menu bar open, or opens Bouncer's own bar, or, with menu bar
    /// items off, the todo or the notes page.
    ///
    /// The permissions are normally asked for when the bar is turned on, in Settings; this
    /// re-asks only as a fallback for a user who dismissed those prompts. Accessibility
    /// missing still opens the bar — the items show, they are just not clickable yet.
    private func handleIconClick() {
        guard settings.preferences.enableMenuBarItems else {
            if let page = contentPage { toggle(page) }
            return
        }
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
    ///
    /// The notch opens the todo or the notes page, whichever the switch last chose. With the items bar
    /// there to share it, it opens whichever of the three the switch last chose.
    private func handleHoverReveal(on screen: NSScreen, atNotch: Bool) {
        let preferences = settings.preferences
        let showsItemsBar = preferences.enableMenuBarItems && preferences.showItemsInBar
        if let page = contentPage,
           showsItemsBar ? preferences.notchPage == page : atNotch || !preferences.enableMenuBarItems {
            Task { [todos, notes] in
                if page == .notes { await notes.open(on: screen) } else { await todos.open(on: screen) }
            }
            return
        }
        guard showsItemsBar else {
            menuBar.setVisibility(.revealed)
            return
        }
        guard StandaloneBarPermissions.screenRecordingGranted else { return }
        // With hover over the whole menu bar off, only the notch could have opened it.
        Task { await standaloneBar.open(closingWhenLeft: !settings.preferences.revealOnHover) }
    }

    /// The notch panel's pages that are on, in the order their switches show them.
    private var notchPages: [NotchPage] {
        let preferences = settings.preferences
        return [
            preferences.enableMenuBarItems && preferences.showItemsInBar ? NotchPage.items : nil,
            preferences.enableTodos ? .todos : nil,
            preferences.enableNotes ? .notes : nil
        ].compactMap(\.self)
    }

    /// The todo or the notes page, whichever the switch last chose while both are on.
    private var contentPage: NotchPage? {
        let pages = notchPages.filter { $0 != .items }
        return pages.contains(settings.preferences.notchPage) ? settings.preferences.notchPage : pages.first
    }

    /// Each page offers the others only while they are on, and a page switched off closes. The items
    /// page has room for one switch, to the todo page, or to the notes page without it.
    private func wirePageSwitches() {
        let preferences = settings.preferences
        let pages = notchPages
        todos.pageSwitches = pages.filter { $0 != .todos }
        todos.onSwitchPage = { [weak self] in self?.switchPage(to: $0) }
        notes.pageSwitches = pages.filter { $0 != .notes }
        notes.onSwitchPage = { [weak self] in self?.switchPage(to: $0) }
        standaloneBar.onSwitchPage = nil
        if let target = pages.first(where: { $0 != .items }) {
            standaloneBar.setPageSwitch(symbol: target.symbol, help: target.help)
            standaloneBar.onSwitchPage = { [weak self] in self?.switchPage(to: target) }
        }
        // Assigned only on a change, since assigning registers the shortcut again.
        if preferences.enableTodos != (todos.onShortcut != nil) {
            todos.onShortcut = nil
            if preferences.enableTodos { todos.onShortcut = { [weak self] in self?.handleShortcut(for: .todos) } }
        }
        if preferences.enableNotes != (notes.onShortcut != nil) {
            notes.onShortcut = nil
            if preferences.enableNotes { notes.onShortcut = { [weak self] in self?.handleShortcut(for: .notes) } }
        }
        if !preferences.enableTodos { Task { [todos] in await todos.close() } }
        if !preferences.enableNotes { Task { [notes] in await notes.close() } }
        if !pages.contains(.items) { Task { [standaloneBar] in await standaloneBar.close() } }
    }

    /// Turns the open page into `page`, which hover then opens next time. The todo and notes panels
    /// do the moving: one grows out of the panel open and takes it away once covering it, or, going
    /// to the items page, has it built underneath itself and shrinks into its shape before it shows.
    private func switchPage(to page: NotchPage) {
        settings.preferences.notchPage = page
        Task { [standaloneBar, todos, notes, settings] in
            let closingWhenLeft = !settings.preferences.revealOnHover
            if page == .items {
                let intoItems: (@escaping Shaping) async -> Void = { shape in
                    await standaloneBar.open(closingWhenLeft: closingWhenLeft, takingShape: shape)
                }
                if todos.isOpen { await todos.close(into: intoItems) } else { await notes.close(into: intoItems) }
                return
            }
            let (from, closeUnderneath): (CGRect?, @MainActor () async -> Void) = if standaloneBar.isOpen {
                (standaloneBar.panelFrame, { await standaloneBar.close(animated: false) })
            } else if page == .notes {
                (todos.panelFrame, { await todos.close(animated: false) })
            } else {
                (notes.panelFrame, { await notes.close(animated: false) })
            }
            if page == .notes {
                await notes.open(from: from, onceCovered: closeUnderneath)
            } else {
                await todos.open(from: from, onceCovered: closeUnderneath)
            }
        }
    }

    /// ⌘⇧B opens the todo page and ⌘⇧N the notes page, from another page if one is up, and closes it
    /// again.
    private func handleShortcut(for page: NotchPage) {
        let isOpen = page == .notes ? notes.isOpen : todos.isOpen
        guard isOpen || !(standaloneBar.isOpen || todos.isOpen || notes.isOpen) else { return switchPage(to: page) }
        toggle(page)
    }

    /// Opened from the keyboard or the icon, with the pointer anywhere, so leaving does not close it.
    private func toggle(_ page: NotchPage) {
        Task { [todos, notes] in
            switch page {
            case .todos: todos.isOpen ? await todos.close() : await todos.open(closesOnLeave: false)
            case .notes: notes.isOpen ? await notes.close() : await notes.open(closesOnLeave: false)
            case .items: break
            }
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
            let window = Self.makeWindow(styleMask: [.titled, .closable])
            window.title = "\(Self.appName) Settings"
            settingsWindow = window
        }
        settingsWindow?.contentViewController = hosting
        settingsWindow?.setContentSize(hosting.view.fittingSize)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Picks the modes on first launch. Only Continue closes it, and it stores the choice even
    /// when nothing was changed, so the window does not come back.
    private func showWelcome() {
        let hosting = NSHostingController(rootView: WelcomeView(settings: settings) { [weak self] in
            self?.settings.flush()
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        })
        hosting.sizingOptions = [.preferredContentSize]
        let window = Self.makeWindow(styleMask: [.titled])
        window.title = Self.appName
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// The style mask has to be set at init; assigning it afterwards drops the layout the hosting
    /// controller established and the content renders empty.
    private static func makeWindow(styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}

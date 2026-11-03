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
    private lazy var claude = ClaudeController(settings: settings)
    /// Every page but the items page, in the order the page button lists them.
    private lazy var contentPages: [(page: NotchPage, controller: any NotchPageController)] = [
        (.todos, todos), (.notes, notes), (.claude, claude)
    ]
    private var pageSwitches: ObservationLoop?
    private let pageKeys = PageKeys()
    private var pageKeysArming: ObservationLoop?
    /// A page turning into the other, which nothing else may open or close until it has.
    private var isSwitching = false
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
        pageKeys.onStep = { [weak self] in self?.stepPage(by: $0) }
        pageKeysArming = ObservationLoop { [weak self] in self?.armPageKeys() }
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
    /// items off, the page the switch last chose.
    ///
    /// The permissions are normally asked for when the bar is turned on, in Settings; this
    /// re-asks only as a fallback for a user who dismissed those prompts. Accessibility
    /// missing still opens the bar — the items show, they are just not clickable yet.
    private func handleIconClick() {
        guard !isSwitching else { return }
        guard settings.preferences.enableMenuBarItems else {
            if let page = contentPage { toggle(page) }
            return
        }
        guard settings.preferences.showItemsInBar else {
            menuBar.toggle()
            return
        }
        // The other pages share the notch with the bar, so the bar takes their place.
        guard openContentPage == nil else { return switchPage(to: .items) }
        permissions.refresh()
        guard !StandaloneBarController.needsScreenRecording || permissions.screenRecording == .granted else {
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
    /// The notch opens whichever page the switch last chose, the items bar among them while it is there
    /// to share it.
    private func handleHoverReveal(on screen: NSScreen, atNotch: Bool) {
        guard !isSwitching else { return }
        let preferences = settings.preferences
        let showsItemsBar = preferences.enableMenuBarItems && preferences.showItemsInBar
        if let page = contentPage,
           showsItemsBar ? preferences.notchPage == page : atNotch || !preferences.enableMenuBarItems {
            // One page at a time: the other is switched to, not opened over it.
            guard !standaloneBar.isShowing else { return }
            let controller = controller(of: page)
            Task { await controller?.open(on: screen, from: nil, closesOnLeave: true, onceCovered: {}) }
            return
        }
        guard showsItemsBar else {
            menuBar.setVisibility(.revealed)
            return
        }
        guard openContentPage == nil,
              !StandaloneBarController.needsScreenRecording || StandaloneBarPermissions.screenRecordingGranted
        else { return }
        // With hover over the whole menu bar off, only the notch could have opened it.
        Task { await standaloneBar.open(closingWhenLeft: !settings.preferences.revealOnHover) }
    }

    /// The page other than the items page that the switch last chose, or the first one on.
    private var contentPage: NotchPage? {
        let pages = settings.preferences.notchPages.filter { $0 != .items }
        return pages.contains(settings.preferences.notchPage) ? settings.preferences.notchPage : pages.first
    }

    /// Every page's button offers the pages that are on, and a page switched off closes.
    private func wirePageSwitches() {
        let preferences = settings.preferences
        let pages = preferences.notchPages
        standaloneBar.pages = pages
        standaloneBar.onSwitchPage = { [weak self] in self?.switchPage(to: $0) }
        for (page, controller) in contentPages {
            controller.pages = pages
            controller.onSwitchPage = { [weak self] in self?.switchPage(to: $0) }
            let isOn = pages.contains(page)
            // Assigned only on a change, since assigning registers the shortcut again.
            if isOn != (controller.onShortcut != nil) {
                controller.onShortcut = nil
                if isOn { controller.onShortcut = { [weak self] in self?.handleShortcut(for: page) } }
            }
            if !isOn { Task { await controller.close(animated: true, into: nil) } }
        }
        if !pages.contains(.items) { Task { [standaloneBar] in await standaloneBar.close() } }
    }

    /// Turns the open page into `page`, which hover then opens next time. The pages other than the
    /// items page do the moving: one grows out of the panel open and takes it away once covering it,
    /// or, going to the items page, has it built underneath itself and shrinks into its shape before
    /// it shows.
    private func switchPage(to page: NotchPage) {
        guard !isSwitching else { return }
        isSwitching = true
        settings.preferences.notchPage = page
        let current = openContentPage.flatMap(controller(of:))
        let target = controller(of: page)
        Task { [weak self, standaloneBar, settings] in
            defer { self?.isSwitching = false }
            let closingWhenLeft = !settings.preferences.revealOnHover
            guard let target else {
                await current?.close(animated: true) { shape in
                    await standaloneBar.open(closingWhenLeft: closingWhenLeft, takingShape: shape)
                }
                return
            }
            // Grown out of the band as it rests: one still opening has no outline yet.
            if standaloneBar.isShowing { await standaloneBar.opening() }
            let open: @MainActor (CGRect?, @MainActor () async -> Void) async -> Void = { from, covered in
                await target.open(on: nil, from: from, closesOnLeave: true, onceCovered: covered)
            }
            if standaloneBar.isOpen {
                let from = standaloneBar.panelFrame
                await standaloneBar.close(into: { await open(from, $0) })
            } else {
                await open(current?.panelFrame, { await current?.close(animated: false, into: nil) })
            }
        }
    }

    /// ⌘⇧B opens the todo page, ⌘⇧N the notes page and ⌘⇧C the Claude page, from another page if one
    /// is up, and closes it again.
    private func handleShortcut(for page: NotchPage) {
        guard !isSwitching else { return }
        guard openContentPage == page || openPage == nil else { return switchPage(to: page) }
        toggle(page)
    }

    /// The page showing in the notch panel, or on its way.
    private var openPage: NotchPage? {
        openContentPage ?? (standaloneBar.isShowing ? .items : nil)
    }

    /// The page other than the items page that is open.
    private var openContentPage: NotchPage? {
        contentPages.first { $0.controller.isOpen }?.page
    }

    private func controller(of page: NotchPage) -> (any NotchPageController)? {
        contentPages.first { $0.page == page }?.controller
    }

    /// ⌘⇧← and ⌘⇧→ are Bouncer's only while one of its pages is open.
    private func armPageKeys() {
        pageKeys.isActive = openPage != nil
    }

    private func stepPage(by step: Int) {
        guard let page = openPage, let next = page.stepped(by: step, in: settings.preferences.notchPages),
              next != page
        else { return }
        switchPage(to: next)
    }

    /// Opened from the keyboard or the icon, with the pointer anywhere, so leaving does not close it.
    private func toggle(_ page: NotchPage) {
        guard let controller = controller(of: page) else { return }
        Task {
            if controller.isOpen {
                await controller.close(animated: true, into: nil)
            } else {
                await controller.open(on: nil, from: nil, closesOnLeave: false, onceCovered: {})
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

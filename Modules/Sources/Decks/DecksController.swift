import AppKit
import BouncerFoundation
import Settings
import SwiftUI

/// The window overview: opens on its shortcut over the display under the pointer, lists every
/// window, and brings forward the one picked.
///
/// While the overview is off nothing is registered. While it is on and closed only the hot key is.
/// Everything else, the window list and the panel among it, exists only while it is open.
///
/// Known limits: minimized windows and windows on other Spaces are not on screen, so the window
/// server does not list them. Full screen apps live in Spaces of their own and show only while
/// theirs is the current one.
@MainActor
public final class DecksController {
    /// The feature's name wherever the user reads it.
    public static let name = "Decks"

    private let settings: SettingsStore
    public let permissions = DecksPermissions()
    private var hotKey: HotKey?
    private var registered: HotKey.Shortcut?
    private var arming: ObservationLoop?
    private var panel: OverlayPanel?
    private var overview: Overview?
    private var resignObserver: NSObjectProtocol?
    private var capture: Task<Void, Never>?

    public var isOpen: Bool { panel != nil }

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Registers the shortcut while the overview is on, and again whenever it changes.
    public func start() {
        arming = ObservationLoop { [weak self] in self?.arm() }
    }

    private func arm() {
        let preferences = settings.preferences
        let wanted = preferences.enableDecks ? preferences.decksShortcut : nil
        guard wanted != registered else { return }
        hotKey?.unregister()
        hotKey = wanted.flatMap { HotKey($0, id: Self.hotKeyID) { [weak self] in self?.toggle() } }
        registered = wanted
        if wanted == nil { close() }
    }

    public func toggle() {
        if isOpen { close() } else { open() }
    }

    public func open() {
        guard panel == nil, let screen = Self.pointerScreen else { return }
        permissions.refresh()
        let windows = WindowList.onScreen()
        // Brought up to date with what is open before anything is shown, and stored as it is.
        let decks = DeckMatching.refreshed(
            settings.preferences.decks, with: DeckMatching.arrange(settings.preferences.decks, over: windows),
            existing: WindowList.existing()
        )
        settings.preferences.decks = decks
        let overview = Overview(
            windows: windows,
            decks: decks,
            wallpaper: NSWorkspace.shared.desktopImageURL(for: screen).flatMap(NSImage.init(contentsOf:)),
            canRaise: permissions.accessibility,
            canSeeTitles: permissions.screenRecording
        )
        overview.onPick = { [weak self] in self?.bringForward($0) }
        overview.onDismiss = { [weak self] in self?.close() }
        overview.onGrant = { [weak self] in self?.grant($0) }
        overview.onDecksChange = { [weak self] in self?.settings.preferences.decks = $0 }
        let panel = OverlayPanel(frame: screen.frame)
        let host = PointerHost(rootView: OverviewView(overview: overview))
        host.onPointer = { [weak overview] in overview?.pointerMoved(to: $0) }
        // The panel covers the display exactly; the content never resizes it.
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(screen.frame, display: false)
        panel.onEscape = { [weak self] in self?.close() }
        panel.orderFrontRegardless()
        panel.makeKey()
        // Another app or window coming forward, Bouncer's settings among them, takes the overview away.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        self.panel = panel
        self.overview = overview
        guard overview.canSeeTitles else { return }
        capture = Task { [windows = overview.windows.map(\.id), scale = screen.backingScaleFactor] in
            await Thumbnails.capture(windows, scale: scale) { [weak overview] id, image in
                overview?.thumbnails[id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    public func close() {
        capture?.cancel()
        capture = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        overview?.stopWaiting()
        overview = nil
    }

    private func bringForward(_ windows: [WindowInfo]) {
        close()
        guard let focused = windows.last else { return }
        NSRunningApplication(processIdentifier: focused.pid)?.activate()
        Task.detached { WindowFocus.raise(windows) }
    }

    private func grant(_ permission: Overview.Permission) {
        close()
        permissions.request()
        let pane = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    #if DEV
    /// Groups the `count` frontmost windows on screen into a new deck, for checking decks from a shell.
    public func devGroup(_ count: Int) -> String {
        let windows = Array(WindowList.onScreen().prefix(count))
        guard !windows.isEmpty else { return "no windows" }
        settings.preferences.decks = DeckMatching.grouping(windows, in: settings.preferences.decks).decks
        return "grouped \(windows.map(\.label))"
    }

    /// Hovers the deck at `index` in the open overview, as the pointer would.
    public func devHover(_ index: Int) -> String {
        guard let overview, index < overview.decks.count else { return "no such deck" }
        overview.devShow(overview.decks[index].id)
        return "hovering \(overview.decks[index].name)"
    }

    public func devClearDecks() {
        settings.preferences.decks = []
    }
    #endif

    private static let hotKeyID: UInt32 = 10

    private static var pointerScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}

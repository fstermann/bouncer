import AppKit
import BouncerFoundation
import Settings
import SwiftUI

/// The window overview: opens on its shortcut over the display under the pointer, lists every
/// window, and brings forward the one picked.
///
/// While the overview is off nothing is registered. While it is on and closed only the hot key is.
/// The most recent thumbnails stay in memory between openings.
///
/// Lists the windows of every Space, full screen apps' among them, through SkyLight; without it, only
/// the current Space's. Known limit: minimized windows are left out.
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
    private var thumbnailCache = ThumbnailCache()
    /// The view the overview was last left on, to open on again until Bouncer quits.
    private var lastView: DeckKind = .windows

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
        if wanted == nil {
            close()
            thumbnailCache = ThumbnailCache()
        }
    }

    public func toggle() {
        if isOpen { close() } else { open() }
    }

    public func open() {
        guard panel == nil, let screen = Self.pointerScreen else { return }
        permissions.refresh()
        let opening = Opening.read(
            on: screen, decks: settings.preferences.decks, names: settings.preferences.spaceNames
        )
        let items = opening.items
        // Brought up to date with what is open before anything is shown, and stored as it is.
        settings.preferences.decks = SpaceItems.stored(opening.decks, with: items)
        let windows = opening.windows
        let overview = Overview(
            windows: windows,
            spaces: opening.spaceOf,
            spaceItems: opening.shownItems,
            decks: opening.decks,
            wallpaper: Wallpaper.image(for: screen, spaces: opening.spaces),
            topInset: screen.safeAreaInsets.top,
            canRaise: permissions.accessibility,
            canSeeTitles: permissions.screenRecording
        )
        if overview.canSeeTitles { overview.thumbnails = thumbnailCache.pictures(for: windows) }
        thumbnailCache = ThumbnailCache()
        overview.onPick = { [weak self] in self?.bringForward($0) }
        overview.onDismiss = { [weak self] in self?.close() }
        overview.onGrant = { [weak self] in self?.grant($0) }
        overview.onDecksChange = { [weak self] in
            self?.settings.preferences.decks = SpaceItems.stored($0, with: items)
        }
        overview.onSpaceRename = { [weak self] uuid, name in self?.settings.preferences.spaceNames[uuid] = name }
        overview.onFullScreen = { [weak self] in self?.setFullScreen($0, $1) }
        overview.view = overview.hasSpaces ? lastView : .windows
        overview.onViewChange = { [weak self] in self?.lastView = $0 }
        overview.onTile = { [weak self] in self?.tile($0, on: screen) }
        let panel = Self.panel(showing: overview, on: screen)
        panel.onEscape = { [weak self] in self?.close() }
        panel.onKey = { [weak overview] event in
            guard let overview, let key = OverviewKey(event) else { return false }
            return overview.key(key)
        }
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
        if overview.canRaise { Self.readBadges(into: overview) }
        if overview.canSeeTitles { capturePictures(into: overview, scale: screen.backingScaleFactor) }
    }

    /// Takes every window's picture, those with none from the last opening first.
    private func capturePictures(into overview: Overview, scale: CGFloat) {
        let ids = overview.windows.map(\.id)
        let windowIDs = ids.filter { overview.thumbnails[$0] == nil } + ids.filter { overview.thumbnails[$0] != nil }
        capture = Task.detached(priority: .userInitiated) { [weak overview] in
            await Thumbnails.capture(windowIDs, scale: scale) { [weak overview] id, image in
                overview?.thumbnails[id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    private static func readBadges(into overview: Overview) {
        Task.detached(priority: .userInitiated) { [weak overview] in
            let badges = DockBadges.read()
            await MainActor.run { overview?.badges = badges }
        }
    }

    /// The overview's panel over `screen`, its content reporting the pointer and Tab to `overview`.
    private static func panel(showing overview: Overview, on screen: NSScreen) -> OverlayPanel {
        let panel = OverlayPanel(frame: screen.frame)
        let host = PointerHost(rootView: OverviewView(overview: overview))
        host.onPointer = { [weak overview] in overview?.pointerMoved(to: $0) }
        host.onPress = { [weak overview] in overview?.press(at: $0) ?? false }
        host.onDrag = { [weak overview] in overview?.dragged(to: $0) }
        panel.onPointerEvent = { [weak host] in host?.handlePointerEvent($0) ?? false }
        host.onRelease = { [weak overview] in overview?.released(at: $0) }
        // The panel covers the display exactly; the content never resizes it.
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(screen.frame, display: false)
        panel.onTab = { [weak overview] in
            guard let overview, overview.hasSpaces, overview.renaming == nil else { return false }
            overview.view = overview.view == .windows ? .spaces : .windows
            return true
        }
        return panel
    }

    public func close() {
        capture?.cancel()
        capture = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        if let overview {
            thumbnailCache = ThumbnailCache(windows: overview.windows, pictures: overview.thumbnails)
            overview.stopWaiting()
        }
        overview = nil
    }

    private func bringForward(_ windows: [WindowInfo]) {
        let destination = windows.last.flatMap { overview?.spaces[$0.id] }
        close()
        guard let focused = windows.last else { return }
        // The window server fronts a window elsewhere and raising it switches to its Space; the app alone
        // would go to whichever of its windows was last in front.
        if let destination, !destination.isCurrent {
            let group = SpaceFocus.members(windows, on: destination)
            Task.detached {
                for window in group { SpaceFocus.raise(window) }
            }
            return
        }
        NSRunningApplication(processIdentifier: focused.pid)?.activate()
        Task.detached { WindowFocus.raise(windows) }
    }

    private func setFullScreen(_ window: WindowInfo, _ isOn: Bool) {
        close()
        Task.detached { WindowFocus.setFullScreen(window, isOn) }
    }

    /// Lays the windows side by side over the display's visible area, the front one first, and brings
    /// them all forward.
    private func tile(_ windows: [WindowInfo], on screen: NSScreen) {
        let isElsewhere = overview?.spaces[windows[0].id]?.isCurrent == false
        close()
        let area = Self.windowServerRect(of: screen.visibleFrame)
        let frames = Array(zip(windows, Tiling.frames(count: windows.count, in: area)))
        NSRunningApplication(processIdentifier: windows[0].pid)?.activate()
        Task.detached {
            // Switched to their desktop first: Accessibility lists only the current Space's windows.
            if isElsewhere {
                SpaceFocus.raise(windows[0])
                try? await Task.sleep(for: .milliseconds(400))
            }
            Tiling.apply(frames)
            WindowFocus.raise(windows.reversed())
        }
    }

    /// An AppKit screen rectangle as the window server and Accessibility take it: from the top left of
    /// the main display, y downwards.
    static func windowServerRect(of rect: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
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

    /// Removes every deck, or only those of one view.
    public func devClearDecks(_ kind: DeckKind? = nil) {
        settings.preferences.decks.removeAll { kind == nil || $0.kind == kind }
    }

    /// Brings the window numbered `id` forward from wherever it is, as picking it in the overview would.
    public func devFocus(_ id: CGWindowID) -> String {
        guard let window = SpaceList.read()?.flatMap(\.windows).first(where: { $0.id == id }) else {
            return "no window \(id)"
        }
        Task.detached { SpaceFocus.raise(window) }
        return "focusing \(window.label)"
    }

    /// How many of the open overview's windows have their picture, of how many.
    public func devPictures() -> String {
        guard let overview else { return "closed" }
        return "\(overview.thumbnails.count)/\(overview.windows.count)"
    }

    /// Where the open overview draws each window's card, in screen points from the top left.
    public func devCards() -> String {
        guard let overview else { return "closed" }
        return overview.hoverFrames.compactMap { target, frame -> String? in
            let name: String
            switch target {
            case .window(let id): name = "\(id)"
            case .trayWindow(let id): name = "tray-\(id)"
            case .desktop(let id):
                guard let entry = overview.spaceItems.first(where: { $0.item.id == id }) else { return nil }
                name = "desk-\(entry.space.name)".replacingOccurrences(of: " ", with: "-")
            case .deck(let id):
                name = (overview.decks.first { $0.id == id }?.name ?? "deck").replacingOccurrences(of: " ", with: "-")
            case .newDeck: name = "new"
            case .fullScreen: name = "full-screen"
            case .tray, .grid: return nil
            }
            return "\(name) \(Int(frame.midX)) \(Int(frame.midY))"
        }.sorted().joined(separator: "\n")
    }

    /// Every Space with its windows, as the overview reads them.
    public func devSpaces() -> String {
        guard let spaces = SpaceList.read() else { return "SkyLight unavailable" }
        return spaces.map { space in
            let name = switch space.kind {
            case .desktop(let number): "Desktop \(number)"
            case .fullScreen: "full screen"
            }
            return "\(space.id) \(name)\(space.isCurrent ? " (current)" : ""): "
                + space.windows.map { "\($0.id) \($0.label)" }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
    #endif

    private static let hotKeyID: UInt32 = 10

    private static var pointerScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}

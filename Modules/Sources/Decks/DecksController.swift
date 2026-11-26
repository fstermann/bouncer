import AppKit
import BouncerFoundation
import Settings
import SwiftUI

/// The window overview: opens on its shortcut over every display, each listing its own windows, and
/// brings forward the one picked. A window dragged onto another display's overview moves there.
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

    let settings: SettingsStore
    public let permissions = DecksPermissions()
    private var hotKey: HotKey?
    private var swipe: ThreeFingerSwipe?
    private var registered: HotKey.Shortcut?
    private var arming: ObservationLoop?
    /// One overview for each display while open.
    private(set) var sessions: [Session] = []
    private var resignObservers: [NSObjectProtocol] = []
    private var capture: Task<Void, Never>?
    private var thumbnailCache = ThumbnailCache()
    /// The view the overview was last left on, to open on again until Bouncer quits.
    private var lastView: DeckKind = .windows
    /// While Mission Control adds or removes a desktop under the overview, which then loses the keys.
    var isChangingDesktops = false

    public var isOpen: Bool { !sessions.isEmpty }

    struct Session {
        let area: Area
        let panel: OverlayPanel
        let overview: Overview
    }

    /// The overview of the display under the pointer, else the first.
    var overview: Overview? {
        (sessions.first { NSMouseInRect(NSEvent.mouseLocation, $0.area.frame, false) } ?? sessions.first)?.overview
    }

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Registers the shortcut while the overview is on, and again whenever it changes.
    public func start() {
        arming = ObservationLoop { [weak self] in self?.arm() }
    }

    private func arm() {
        let preferences = settings.preferences
        armSwipe(preferences.enableDecks && preferences.decksSwipe)
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

    /// Listens for the swipe only while it is on. Without Accessibility the tap cannot be made; turning
    /// the swipe off and on again retries.
    private func armSwipe(_ isOn: Bool) {
        guard isOn != (swipe != nil) else { return }
        swipe?.stop()
        swipe = nil
        guard isOn else { return }
        // Up only opens and down only closes.
        let listener = ThreeFingerSwipe { [weak self] direction in
            guard let self, (direction == .up) != isOpen else { return }
            toggle()
        }
        if listener.start() { swipe = listener }
    }

    public func toggle() {
        if isOpen { close() } else { open() }
    }

    /// Opens one overview over each of `areas`: each display, or in Bouncer Dev's split two halves of one.
    func open(on areas: [Area]) {
        guard sessions.isEmpty, !areas.isEmpty else { return }
        permissions.refresh()
        let opening = Opening.read(decks: settings.preferences.decks, names: settings.preferences.spaceNames)
        let items = opening.items
        // Brought up to date with what is open before anything is shown, and stored as it is.
        settings.preferences.decks = SpaceItems.stored(opening.decks, with: items)
        let cached = thumbnailCache
        thumbnailCache = ThumbnailCache()
        sessions = areas.map { area in
            let overview = overview(showing: opening.shown(on: area.screen), decks: opening.decks, on: area.screen)
            if overview.canSeeTitles { overview.thumbnails = cached.pictures(for: overview.windows) }
            return Session(area: area, panel: Self.panel(showing: overview, over: area.frame), overview: overview)
        }
        for session in sessions {
            wire(session, items: items)
            session.panel.orderFrontRegardless()
        }
        (sessions.first { NSMouseInRect(NSEvent.mouseLocation, $0.area.frame, false) } ?? sessions[0]).panel.makeKey()
        for session in sessions where session.overview.canRaise { Self.readBadges(into: session.overview) }
        if let first = sessions.first, first.overview.canSeeTitles { capturePictures() }
    }

    private func overview(showing shown: Opening.Shown, decks: [Deck], on screen: NSScreen) -> Overview {
        let overview = Overview(
            windows: shown.windows,
            spaces: shown.spaceOf,
            spaceItems: shown.items,
            elsewhere: shown.elsewhere,
            decks: decks,
            wallpaper: Wallpaper.image(for: screen, spaces: shown.spaces),
            topInset: screen.safeAreaInsets.top,
            canRaise: permissions.accessibility,
            canSeeTitles: permissions.screenRecording
        )
        overview.view = overview.hasSpaces ? lastView : .windows
        overview.spaceOrder = settings.preferences.spaceOrder
        return overview
    }

    /// Connects one display's overview to the others and to the stored decks.
    private func wire(_ session: Session, items: [(item: WindowInfo, space: SpaceInfo)]) {
        let overview = session.overview
        let panel = session.panel
        overview.onPick = { [weak self] in self?.bringForward($0) }
        overview.onSwitch = { [weak self] in self?.switchTo($0) }
        overview.onDismiss = { [weak self] in self?.close() }
        overview.onGrant = { [weak self] in self?.grant($0) }
        overview.onDecksChange = { [weak self, weak overview] decks in
            guard let self else { return }
            settings.preferences.decks = SpaceItems.stored(decks, with: items)
            for other in sessions where other.overview !== overview && other.overview.decks != decks {
                other.overview.decks = decks
            }
        }
        overview.onSpaceOrderChange = { [weak self] order in
            // Each display orders only its own Spaces; the others' keep their place in the list.
            guard let self else { return }
            let mine = Set(order)
            settings.preferences.spaceOrder = settings.preferences.spaceOrder.filter { !mine.contains($0) } + order
        }
        overview.onSpaceRename = { [weak self] uuid, name in self?.settings.preferences.spaceNames[uuid] = name }
        overview.onFullScreen = { [weak self] in self?.setFullScreen($0, $1) }
        wireDesktops(session)
        overview.onViewChange = { [weak self, weak overview] view in
            guard let self else { return }
            lastView = view
            for other in sessions where other.overview !== overview && other.overview.hasSpaces {
                other.overview.view = view
            }
        }
        overview.onTile = { [weak self] in self?.tile($0, in: session.area.visibleFrame) }
        panel.onEscape = { [weak self] in self?.close() }
        panel.onKey = { [weak overview] event in
            guard let overview, let key = OverviewKey(event) else { return false }
            return overview.key(key)
        }
        wirePointer(session)
        // Another app or window coming forward, Bouncer's settings among them, takes the overview away;
        // another display's overview taking the keys does not.
        resignObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.isChangingDesktops,
                          !self.sessions.contains(where: { $0.panel.isKeyWindow }) else { return }
                    self.close()
                }
            }
        })
    }

    /// Takes every window's picture on every display, those with none from the last opening first.
    private func capturePictures() {
        let overviews = sessions.map(\.overview)
        let all = overviews.flatMap { overview in overview.windows.map { ($0.id, overview) } }
        let owner = Dictionary(all) { first, _ in first }
        let missing = all.filter { $0.1.thumbnails[$0.0] == nil }.map(\.0)
        let cached = all.filter { $0.1.thumbnails[$0.0] != nil }.map(\.0)
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        capture = Task.detached(priority: .userInitiated) {
            await Thumbnails.capture(missing + cached, scale: scale) { id, image in
                owner[id]?.thumbnails[id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    private static func readBadges(into overview: Overview) {
        Task.detached(priority: .userInitiated) { [weak overview] in
            let badges = DockBadges.read()
            await MainActor.run { overview?.badges = badges }
        }
    }

    /// The overview's panel over `frame`, its content reporting the pointer and Tab to `overview`.
    private static func panel(showing overview: Overview, over frame: CGRect) -> OverlayPanel {
        let panel = OverlayPanel(frame: frame)
        let host = PointerHost(rootView: OverviewView(overview: overview))
        host.onPress = { [weak overview] in overview?.press(at: $0) ?? false }
        panel.onPointerEvent = { [weak host] in host?.handlePointerEvent($0) ?? false }
        // The panel covers the display exactly; the content never resizes it.
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panel.onTab = { [weak overview] in
            guard let overview, overview.hasSpaces, overview.renaming == nil else { return false }
            overview.view = overview.view == .windows ? .spaces : .windows
            return true
        }
        return panel
    }

    public func close() {
        for panel in closeKeepingPanels() { panel.orderOut(nil) }
    }

    /// Ends the sessions but leaves their panels on screen, for the caller to take down.
    func closeKeepingPanels() -> [OverlayPanel] {
        capture?.cancel()
        capture = nil
        for observer in resignObservers { NotificationCenter.default.removeObserver(observer) }
        resignObservers = []
        let closing = sessions
        sessions = []
        if !closing.isEmpty {
            let overviews = closing.map(\.overview)
            thumbnailCache = ThumbnailCache(
                windows: overviews.flatMap(\.windows),
                pictures: overviews.reduce(into: [:]) { $0.merge($1.thumbnails) { first, _ in first } }
            )
            for overview in overviews { overview.stopWaiting() }
        }
        return closing.map(\.panel)
    }

    func bringForward(_ windows: [WindowInfo]) {
        let destination = windows.last.flatMap { window in
            sessions.lazy.compactMap { $0.overview.spaces[window.id] }.first
        }
        let order = destination.map(spaceOrder(of:)) ?? []
        close()
        guard let focused = windows.last else { return }
        // The display switches to the window's Space at once, then the window comes forward there. Failing
        // that, the window server fronts it and raising it slides to its Space; the app alone would go to
        // whichever of its windows was last in front.
        if let destination, !destination.isCurrent {
            let group = SpaceFocus.members(windows, on: destination)
            Task.detached {
                if SpaceSwitch.go(to: destination.id, on: destination.display, order: order) {
                    await MainActor.run { _ = NSRunningApplication(processIdentifier: focused.pid)?.activate() }
                    WindowFocus.raise(group)
                } else {
                    for window in group { SpaceFocus.raise(window) }
                }
            }
            return
        }
        NSRunningApplication(processIdentifier: focused.pid)?.activate()
        Task.detached { WindowFocus.raise(windows) }
    }

    /// The Spaces of `space`'s display, in Mission Control's order, as this opening read them.
    func spaceOrder(of space: SpaceInfo) -> [UInt64] {
        let spaces = sessions.flatMap { $0.overview.spaceItems.map(\.space) }.filter { $0.display == space.display }
        var seen = Set<UInt64>()
        return spaces.map(\.id).filter { seen.insert($0).inserted }
    }

    private func setFullScreen(_ window: WindowInfo, _ isOn: Bool) {
        close()
        Task.detached { WindowFocus.setFullScreen(window, isOn) }
    }

    /// Lays the windows side by side over the display's visible area, the front one first, and brings
    /// them all forward.
    private func tile(_ windows: [WindowInfo], in visibleFrame: CGRect) {
        let space = sessions.lazy.compactMap { $0.overview.spaces[windows[0].id] }.first
        let elsewhere = space.flatMap { $0.isCurrent ? nil : ($0, spaceOrder(of: $0)) }
        close()
        let area = Self.windowServerRect(of: visibleFrame)
        let frames = Array(zip(windows, Tiling.frames(count: windows.count, in: area)))
        NSRunningApplication(processIdentifier: windows[0].pid)?.activate()
        Task.detached {
            // Switched to their desktop first: Accessibility lists only the current Space's windows.
            if let (space, order) = elsewhere { await Self.switchFirst(to: space, order: order, raising: windows[0]) }
            Tiling.apply(frames)
            WindowFocus.raise(windows.reversed())
        }
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

    private static let hotKeyID: UInt32 = 10

}

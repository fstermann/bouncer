import AppKit
import Observation
import Settings

/// What one opening of the overview shows. Built when it opens and dropped when it closes.
@MainActor
@Observable
final class Overview {
    let windows: [WindowInfo]
    /// The Space each window is on; empty when SkyLight could not be read.
    private(set) var spaces: [CGWindowID: SpaceInfo]
    /// The Spaces view's items, one for each Space, with the Space it stands for; empty without SkyLight.
    private(set) var spaceItems: [(item: WindowInfo, space: SpaceInfo)]
    /// Which level the grid shows. Tab switches it.
    var view: DeckKind = .windows {
        didSet {
            guard view != oldValue else { return }
            drag = nil
            trayDeck = nil
            renaming = nil
            onViewChange?(view)
        }
    }
    let wallpaper: NSImage?
    /// The height of the display's menu bar and notch, which the content starts below.
    let topInset: CGFloat
    let canRaise: Bool
    let canSeeTitles: Bool
    /// Every deck, as stored; written back through `onDecksChange` on every edit.
    var decks: [Deck] {
        didSet { onDecksChange?(decks) }
    }
    /// Each window's picture, once it has arrived.
    var thumbnails: [CGWindowID: NSImage] = [:]
    /// Each app's Dock badge, by process, once read.
    var badges: [pid_t: String] = [:]
    /// The deck the tray shows, or `nil` while it is closed.
    private(set) var trayDeck: UUID?
    @ObservationIgnored private var icons: [pid_t: NSImage] = [:]
    @ObservationIgnored private var trayClosing: Task<Void, Never>?

    /// The user picked windows to bring forward, the last of them focused.
    @ObservationIgnored var onPick: (@MainActor ([WindowInfo]) -> Void)?
    @ObservationIgnored var onDismiss: (@MainActor () -> Void)?
    /// The user asked for a permission's pane in System Settings.
    @ObservationIgnored var onGrant: (@MainActor (Permission) -> Void)?
    @ObservationIgnored var onDecksChange: (@MainActor ([Deck]) -> Void)?
    /// The user asked to tile these windows side by side.
    @ObservationIgnored var onTile: (@MainActor ([WindowInfo]) -> Void)?
    @ObservationIgnored var onViewChange: (@MainActor (DeckKind) -> Void)?
    /// The user named a desktop, by its Space's identifier; `nil` gives it back its number.
    @ObservationIgnored var onSpaceRename: (@MainActor (String, String?) -> Void)?
    /// The user asked for a window to enter full screen, or to leave it.
    @ObservationIgnored var onFullScreen: (@MainActor (WindowInfo, Bool) -> Void)?

    enum Permission {
        case screenRecording, accessibility
    }

    init(
        windows: [WindowInfo], spaces: [CGWindowID: SpaceInfo] = [:],
        spaceItems: [(item: WindowInfo, space: SpaceInfo)] = [], decks: [Deck], wallpaper: NSImage?,
        topInset: CGFloat = 0, canRaise: Bool, canSeeTitles: Bool
    ) {
        self.windows = windows
        self.spaces = spaces
        self.spaceItems = spaceItems
        self.decks = decks
        self.wallpaper = wallpaper
        self.topInset = topInset
        self.canRaise = canRaise
        self.canSeeTitles = canSeeTitles
    }

    /// Whether there is a Spaces view to switch to.
    var hasSpaces: Bool { !spaceItems.isEmpty }

    /// The items the grid shows in the current view: windows, or one for each Space.
    var items: [WindowInfo] {
        view == .windows ? windows : spaceItems.map(\.item)
    }

    /// What the user has typed to narrow the cards down.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            drag = nil
            trayDeck = nil
        }
    }

    /// The current view's decks, with the items of each, and the items in none, narrowed to `query`.
    var arrangement: Arrangement {
        OverviewFilter.filtered(DeckMatching.arrange(decks.filter { $0.kind == view }, over: items), by: query) {
            view == .spaces && SpaceItems.isDesktop($0) ? space(of: $0)?.windows ?? [] : []
        }
    }

    /// What the tray shows: one of the current view's decks, or in the Spaces view a desktop's windows.
    var trayShows: LiveDeck? {
        guard let id = trayDeck else { return nil }
        if let live = arrangement.decks.first(where: { $0.id == id }) { return live }
        guard let entry = spaceItems.first(where: { Self.trayID(of: $0.item.id) == id }) else { return nil }
        return LiveDeck(
            deck: Deck(id: id, name: entry.space.name, color: .blue, kind: .windows), windows: entry.space.windows
        )
    }

    /// Whether the tray shows a desktop's windows rather than a deck.
    var trayIsDesktop: Bool {
        guard let id = trayDeck else { return false }
        return !arrangement.decks.contains { $0.id == id }
    }

    /// The id a desktop's tray goes by: the desktop item's number, spelled as a UUID.
    nonisolated static func trayID(of id: CGWindowID) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: id.bigEndian) { raw in
            for (offset, byte) in raw.enumerated() { bytes[12 + offset] = byte }
        }
        return NSUUID(uuidBytes: bytes) as UUID
    }

    func icon(of window: WindowInfo) -> NSImage {
        if let icon = icons[window.pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: window.pid)?.icon
            ?? NSWorkspace.shared.icon(for: .application)
        icons[window.pid] = icon
        return icon
    }

    // MARK: - Editing decks

    /// The deck whose name is being typed, in the tray's head.
    var renaming: UUID?

    /// Names the deck `id`, or the desktop whose tray goes by `id`; an empty name gives a desktop back its number.
    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        renaming = nil
        if let index = decks.firstIndex(where: { $0.id == id }) {
            if !name.isEmpty { decks[index].name = name }
            return
        }
        guard let index = spaceItems.firstIndex(where: { Self.trayID(of: $0.item.id) == id }) else { return }
        var space = spaceItems[index].space
        space.customName = name.isEmpty ? nil : name
        spaceItems[index] = (SpaceItems.desktopItem(id: spaceItems[index].item.id, for: space), space)
        for (window, old) in spaces where old.id == space.id { spaces[window] = space }
        onSpaceRename?(space.uuid, space.customName)
    }

    /// Opens the name field of the deck or desktop under the pointer. Returns whether there was one.
    func renameHovered() -> Bool {
        let id: UUID
        switch hovered {
        case .deck(let deck): id = deck
        case .desktop(let desktop) where view == .spaces: id = Self.trayID(of: desktop)
        default: return false
        }
        stopWaiting()
        trayDeck = id
        renaming = id
        return true
    }

    func recolor(_ id: UUID, to color: DeckColor) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        decks[index].color = color
    }

    /// Dissolves the deck. Its windows stay open.
    func ungroup(_ id: UUID) {
        decks.removeAll { $0.id == id }
        if trayDeck == id { trayDeck = nil }
    }

    /// An empty deck, its tray open and its name ready to type.
    func newDeck() {
        let deck = DeckMatching.grouping([], in: decks)
        decks = deck.decks.map { $0.id == deck.id ? kinded($0) : $0 }
        trayDeck = deck.id
        renaming = deck.id
    }

    private func kinded(_ deck: Deck) -> Deck {
        var deck = deck
        deck.kind = view
        return deck
    }

    // MARK: - Dragging

    /// The window being dragged, where it was picked up, and where the pointer has it.
    struct Drag {
        let window: WindowInfo
        let source: DeckDrop.Source
        let start: CGPoint
        var point: CGPoint
        /// Whether the pointer has gone far enough to be a drag rather than a click.
        var isMoving = false
    }

    /// Less than this from where it started, in points, a press is still a click.
    static let dragThreshold: CGFloat = 4

    private(set) var drag: Drag?

    /// Takes a press on a window, in the grid or the tray, as a possible drag. Returns whether it took it.
    func press(at point: CGPoint) -> Bool {
        let arrangement = arrangement
        let pressed = Hover.target(at: point, in: hoverFrames)
        switch pressed {
        case .trayWindow(let id) where trayIsDesktop:
            // A desktop's windows are dragged out only to go full screen.
            guard canRaise, let window = trayShows?.windows.first(where: { $0.id == id }) else { return false }
            drag = Drag(window: window, source: .desktop, start: point, point: point)
        case .trayWindow(let id):
            guard let deck = trayDeck, arrangement.decks.contains(where: { $0.id == deck }),
                  let window = items.first(where: { $0.id == id })
            else { return false }
            drag = Drag(window: window, source: .tray(deck), start: point, point: point)
        case .window(let id), .desktop(let id):
            guard let window = arrangement.ungrouped.first(where: { $0.id == id }) else { return false }
            drag = Drag(window: window, source: .grid, start: point, point: point)
        default:
            return false
        }
        return true
    }

    /// Whether `window` is being dragged away from its card.
    func isDragging(_ window: WindowInfo) -> Bool {
        drag?.isMoving == true && drag?.window.id == window.id
    }

    func dragged(to point: CGPoint) {
        guard var drag else { return }
        drag.point = point
        drag.isMoving = drag.isMoving || hypot(point.x - drag.start.x, point.y - drag.start.y) >= Self.dragThreshold
        self.drag = drag
    }

    /// Drops the dragged window where the pointer is. A press that never moved is a click.
    func released(at point: CGPoint) {
        guard let drag else { return }
        self.drag = nil
        guard drag.isMoving else { return pick([drag.window]) }
        let target = Hover.target(at: point, in: hoverFrames)
        if let change = fullScreenDrop(of: drag) {
            if target == .fullScreen { onFullScreen?(drag.window, change == .enter) }
            return
        }
        if target == .fullScreen { return }
        let others = decks.filter { $0.kind != view }
        let mine = decks.filter { $0.kind == view }
        switch DeckDrop.drop(drag.window, from: drag.source, on: dropTarget(target), in: arrangement, decks: mine) {
        case .changed(let changed, let show):
            // A deck made by the drop takes the view's kind; the other view's decks are left as they are.
            let known = Set(mine.map(\.id))
            self.decks = others + changed.map { known.contains($0.id) ? $0 : kinded($0) }
            trayDeck = show
        case .unchanged:
            break
        }
    }

    private func dropTarget(_ target: HoverTarget?) -> HoverTarget? {
        switch target {
        case .tray, .trayWindow:
            guard let trayDeck, !trayIsDesktop else { return target }
            return .deck(trayDeck)
        default:
            return target
        }
    }

    // MARK: - The pointer and the tray

    /// Where each part the pointer can be over is drawn, as the views last reported it.
    @ObservationIgnored var hoverFrames: [HoverTarget: CGRect] = [:] {
        didSet { follow() }
    }
    @ObservationIgnored private var pointer: CGPoint?
    /// The card, tray or grid under the pointer.
    private(set) var hovered: HoverTarget?

    func pointerMoved(to point: CGPoint?) {
        pointer = point
        follow()
    }

    private func follow() {
        let target = Hover.target(at: pointer, in: hoverFrames)
        if target != hovered { hovered = target }
        defer { lastTarget = target }
        // A name being typed holds the tray, so the grid reflowing under a new deck cannot close it.
        guard renaming == nil else { return stopWaiting() }
        switch TrayRule.step(showing: trayDeck, pointerOn: target, lastOn: lastTarget) {
        case .show(let id):
            stopWaiting()
            if trayDeck != id { trayDeck = id }
        case .close:
            stopWaiting()
            if trayDeck != nil { trayDeck = nil }
        case .keep:
            stopWaiting()
        case .closeAfter(let grace):
            guard trayClosing == nil else { break }
            trayClosing = Task { [weak self] in
                try? await Task.sleep(for: grace)
                guard let self, !Task.isCancelled else { return }
                trayClosing = nil
                trayDeck = nil
            }
        }
    }

    @ObservationIgnored private var lastTarget: HoverTarget?

    #if DEV
    func devShow(_ id: UUID) {
        trayDeck = id
    }
    #endif

    func stopWaiting() {
        trayClosing?.cancel()
        trayClosing = nil
    }
}

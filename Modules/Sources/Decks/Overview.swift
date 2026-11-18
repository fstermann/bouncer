import AppKit
import Observation
import Settings

/// What one opening of the overview shows. Built when it opens and dropped when it closes.
@MainActor
@Observable
final class Overview {
    let windows: [WindowInfo]
    /// The Space each window is on; empty when SkyLight could not be read.
    let spaces: [CGWindowID: SpaceInfo]
    /// The Spaces view's items, one for each Space, with the Space it stands for; empty without SkyLight.
    let spaceItems: [(item: WindowInfo, space: SpaceInfo)]
    /// Which level the grid shows. Tab switches it.
    var view: DeckKind = .windows {
        didSet {
            guard view != oldValue else { return }
            trayDeck = nil
            renaming = nil
            onViewChange?(view)
        }
    }
    let wallpaper: NSImage?
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

    enum Permission {
        case screenRecording, accessibility
    }

    init(
        windows: [WindowInfo], spaces: [CGWindowID: SpaceInfo] = [:],
        spaceItems: [(item: WindowInfo, space: SpaceInfo)] = [], decks: [Deck], wallpaper: NSImage?,
        canRaise: Bool, canSeeTitles: Bool
    ) {
        self.windows = windows
        self.spaces = spaces
        self.spaceItems = spaceItems
        self.decks = decks
        self.wallpaper = wallpaper
        self.canRaise = canRaise
        self.canSeeTitles = canSeeTitles
    }

    /// Whether there is a Spaces view to switch to.
    var hasSpaces: Bool { !spaceItems.isEmpty }

    /// The items the grid shows in the current view: windows, or one for each Space.
    var items: [WindowInfo] {
        view == .windows ? windows : spaceItems.map(\.item)
    }

    /// The current view's decks, with the items of each, and the items in none.
    var arrangement: Arrangement {
        DeckMatching.arrange(decks.filter { $0.kind == view }, over: items)
    }

    /// What the tray shows: one of the current view's decks, or in the Spaces view a desktop's windows.
    var trayShows: LiveDeck? {
        guard let id = trayDeck else { return nil }
        if let live = arrangement.decks.first(where: { $0.id == id }) { return live }
        guard let entry = spaceItems.first(where: { Self.trayID(of: $0.item) == id }) else { return nil }
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
    static func trayID(of desktop: WindowInfo) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: desktop.id.bigEndian) { raw in
            for (offset, byte) in raw.enumerated() { bytes[12 + offset] = byte }
        }
        return NSUUID(uuidBytes: bytes) as UUID
    }

    /// The Space a Spaces view item stands for.
    func space(of item: WindowInfo) -> SpaceInfo? {
        spaceItems.first { $0.item.id == item.id }?.space
    }

    /// What picking `item` brings forward: itself, or for a desktop its front window. Empty for an empty
    /// desktop, which no public call can switch to.
    func pickable(_ item: WindowInfo) -> [WindowInfo] {
        guard view == .spaces, SpaceItems.isDesktop(item) else { return [item] }
        return space(of: item)?.windows.first.map { [$0] } ?? []
    }

    /// Where a window lives, for one off the current Space: "Desktop 2", "Full screen".
    func place(of window: WindowInfo) -> String? {
        guard let space = spaces[window.id], !space.isCurrent else { return nil }
        switch space.kind {
        case .desktop: return space.name
        case .fullScreen: return "Full screen"
        }
    }

    /// The badge a card shows: its app's, or for a desktop or deck its apps' together, each app counted once.
    func badge(of items: [WindowInfo]) -> String? {
        let windows = items.flatMap { item in
            view == .spaces && SpaceItems.isDesktop(item) ? space(of: item)?.windows ?? [] : [item]
        }
        return DockBadges.combined(Set(windows.map(\.pid)).compactMap { badges[$0] })
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

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty, let index = decks.firstIndex(where: { $0.id == id }) else { return }
        decks[index].name = name
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

    func pick(_ items: [WindowInfo]) {
        let windows = items.flatMap(pickable)
        guard !windows.isEmpty else { return }
        onPick?(windows)
    }

    func tile(_ id: UUID) {
        guard let live = arrangement.decks.first(where: { $0.id == id }) else { return }
        let windows = Tiling.tileable(live.windows, spaces: spaces)
        guard !windows.isEmpty else { return }
        onTile?(windows)
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
        case .trayWindow(let id):
            // A desktop's tray lists its windows to pick, not a deck's to drag out.
            guard let deck = trayDeck, arrangement.decks.contains(where: { $0.id == deck }),
                  let window = items.first(where: { $0.id == id })
            else { return false }
            drag = Drag(window: window, source: .tray(deck), start: point, point: point)
        case .window(let id):
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

    /// A desktop's tile hovers as a deck, for its tray; dropped on, it is the item it stands for.
    private func dropTarget(_ target: HoverTarget?) -> HoverTarget? {
        guard case .deck(let id) = target, let desktop = spaceItems.first(where: { Self.trayID(of: $0.item) == id })
        else { return target }
        return .window(desktop.item.id)
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

/// What the tray does as the pointer moves.
///
/// A deck opens it on that deck. An ungrouped window or the new deck tile closes it at once. Leaving
/// the cards waits a moment before closing, so the pointer can travel from a deck down into the tray;
/// reaching the tray, or a deck, in that moment keeps it.
enum TrayRule {
    enum Step: Equatable {
        case show(UUID)
        case close
        case keep
        case closeAfter(Duration)
    }

    /// How long the tray waits after the pointer leaves the grid, so the pointer can reach it below.
    static let leaveGrace: Duration = .milliseconds(250)
    /// How long it waits after the pointer leaves the tray itself.
    static let trayGrace: Duration = .milliseconds(300)

    static func step(showing deck: UUID?, pointerOn target: HoverTarget?, lastOn last: HoverTarget?) -> Step {
        switch target {
        case .deck(let id): return .show(id)
        case .window, .newDeck: return .close
        case .tray, .trayWindow: return deck == nil ? .close : .keep
        case .grid, nil:
            guard deck != nil else { return .close }
            return .closeAfter(isTray(last) ? trayGrace : leaveGrace)
        }
    }

    private static func isTray(_ target: HoverTarget?) -> Bool {
        switch target {
        case .tray, .trayWindow: true
        default: false
        }
    }
}

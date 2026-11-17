import AppKit
import Observation
import Settings

/// What one opening of the overview shows. Built when it opens and dropped when it closes.
@MainActor
@Observable
final class Overview {
    let windows: [WindowInfo]
    let wallpaper: NSImage?
    let canRaise: Bool
    let canSeeTitles: Bool
    /// Every deck, as stored; written back through `onDecksChange` on every edit.
    var decks: [Deck] {
        didSet { onDecksChange?(decks) }
    }
    /// Each window's picture, once it has arrived.
    var thumbnails: [CGWindowID: NSImage] = [:]
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

    enum Permission {
        case screenRecording, accessibility
    }

    init(windows: [WindowInfo], decks: [Deck], wallpaper: NSImage?, canRaise: Bool, canSeeTitles: Bool) {
        self.windows = windows
        self.decks = decks
        self.wallpaper = wallpaper
        self.canRaise = canRaise
        self.canSeeTitles = canSeeTitles
    }

    var arrangement: Arrangement {
        DeckMatching.arrange(decks, over: windows)
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
        decks = deck.decks
        trayDeck = deck.id
        renaming = deck.id
    }

    func tile(_ id: UUID) {
        guard let live = arrangement.decks.first(where: { $0.id == id }), !live.windows.isEmpty else { return }
        onTile?(live.windows)
    }

    // MARK: - Dragging

    /// The window being dragged, where it was picked up, and where the pointer has it.
    struct Drag {
        let window: WindowInfo
        let source: DeckDrop.Source
        var point: CGPoint
    }

    private(set) var drag: Drag?

    /// Starts a drag on a window in the tray, or on any window with Option held. Returns whether one started.
    func press(at point: CGPoint, option: Bool) -> Bool {
        let arrangement = arrangement
        let pressed = Hover.target(at: point, in: hoverFrames)
        switch pressed {
        case .trayWindow(let id):
            guard let deck = trayDeck, let window = windows.first(where: { $0.id == id }) else { return false }
            drag = Drag(window: window, source: .tray(deck), point: point)
        case .window(let id) where option:
            guard let window = arrangement.ungrouped.first(where: { $0.id == id }) else { return false }
            drag = Drag(window: window, source: .grid, point: point)
        default:
            return false
        }
        return true
    }

    func dragged(to point: CGPoint) {
        drag?.point = point
    }

    /// Drops the dragged window where the pointer is. A press in the tray that never moved is a click.
    func released(at point: CGPoint) {
        guard let drag else { return }
        self.drag = nil
        let target = Hover.target(at: point, in: hoverFrames)
        if case .tray = drag.source, target == .trayWindow(drag.window.id) {
            return onPick?([drag.window]) ?? ()
        }
        switch DeckDrop.drop(drag.window, from: drag.source, on: target, in: arrangement, decks: decks) {
        case .changed(let decks, let show):
            self.decks = decks
            trayDeck = show
        case .unchanged:
            break
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

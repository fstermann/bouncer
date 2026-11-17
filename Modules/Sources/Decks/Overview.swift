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
        lastTarget = target
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

import Foundation

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
        case .desktop(let id): return .show(Overview.trayID(of: id))
        case .window, .newDeck, .fullScreen: return .close
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

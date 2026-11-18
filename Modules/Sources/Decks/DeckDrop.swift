import CoreGraphics
import Foundation
import Settings

/// What dropping a dragged window does to the decks.
enum DeckDrop {
    /// Where a window was picked up.
    enum Source: Equatable {
        /// An ungrouped window or a deck's window, from the grid.
        case grid
        /// A deck's window, from its tray.
        case tray(UUID)
        /// A desktop's window, from its tray in the Spaces view.
        case desktop
    }

    enum Outcome: Equatable {
        /// The decks after the drop, and the deck the tray should show.
        case changed(decks: [Deck], show: UUID?)
        case unchanged
    }

    /// Dropping `window`, picked up from `source`, on `target`.
    ///
    /// Onto another window it makes a deck of the two, or adds itself to that window's deck; onto a
    /// deck or the new deck tile it joins that deck or a new one. Dropped from the tray anywhere but
    /// the tray or a deck, it leaves its deck.
    static func drop(
        _ window: WindowInfo, from source: Source, on target: HoverTarget?, in arrangement: Arrangement, decks: [Deck]
    ) -> Outcome {
        switch target {
        case .deck(let id):
            if arrangement.decks.first(where: { $0.id == id })?.windows.contains(window) == true { return .unchanged }
            return .changed(decks: DeckMatching.adding(window, to: id, in: decks), show: id)
        case .window(let id) where id != window.id, .desktop(let id) where id != window.id:
            guard let other = arrangement.ungrouped.first(where: { $0.id == id }) else { return .unchanged }
            let grouped = DeckMatching.grouping([other, window], in: decks)
            return .changed(decks: grouped.decks, show: grouped.id)
        case .newDeck:
            let grouped = DeckMatching.grouping([window], in: decks)
            return .changed(decks: grouped.decks, show: grouped.id)
        case .tray, .trayWindow, .fullScreen:
            return .unchanged
        case .window, .desktop, .grid, nil:
            guard case .tray = source else { return .unchanged }
            return .changed(decks: DeckMatching.removing(window, from: decks), show: nil)
        }
    }
}

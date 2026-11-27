import CoreGraphics
import Settings

/// Letting go of a drag: a click, a reorder, a full screen change, or a change to the decks.
extension Overview {
    /// Drops the dragged window where the pointer is. A press that never moved is a click.
    func released(at point: CGPoint) {
        guard let drag else { return }
        let reorder = reorderTarget
        self.drag = nil
        if let deck = drag.deck {
            if !drag.isMoving, let live = arrangement.decks.first(where: { $0.id == deck }) { pick(deck: live) }
            if drag.isMoving, let reorder { apply(reorder, moving: drag) }
            return
        }
        guard drag.isMoving else { return pick([drag.window]) }
        if let reorder { return apply(reorder, moving: drag) }
        drop(drag, on: Hover.target(at: point, in: hoverFrames))
    }

    /// Drops a window: into full screen, or into or out of a deck.
    private func drop(_ drag: Drag, on target: HoverTarget?) {
        if target == .fullScreen {
            if let change = fullScreenDrop(of: drag) { onFullScreen?(drag.window, change == .enter) }
            return
        }
        // A desktop's windows are dragged out only to go full screen; the full screen Space's own card groups.
        if drag.source == .desktop { return }
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
        case .removeDesktop(let id):
            return .desktop(id)
        default:
            return target
        }
    }
}

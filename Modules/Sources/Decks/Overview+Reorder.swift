import CoreGraphics
import Foundation
import Settings

/// Where a card dragged among its own kind would land.
struct ReorderTarget: Equatable {
    enum Kind: Equatable {
        case decks
        /// The Spaces view's items in no deck.
        case spaces
        /// The cards in the tray of the deck.
        case members(UUID)
    }

    let kind: Kind
    /// Where among the cards shown it goes, as `Reorder.slot` counts.
    let slot: Int
    /// The line that marks the place, in the overview's coordinates.
    let marker: CGRect
}

/// Dragging a card among its own kind to reorder: decks among decks, Spaces in no deck among each other,
/// and a deck's cards in its tray.
extension Overview {
    /// Where the drag would reorder its card if let go now, or `nil` where it would group or do nothing.
    func currentReorderTarget() -> ReorderTarget? {
        guard let drag, drag.isMoving else { return nil }
        let arrangement = arrangement
        if let deck = drag.deck {
            let ids = arrangement.decks.map(\.id)
            return target(.decks, frames: ids.map { hoverFrames[.deck($0)] }, own: ids.firstIndex(of: deck),
                          at: drag.point, gap: Metrics.gap)
        }
        let over = Hover.target(at: drag.point, in: hoverFrames)
        switch drag.source {
        case .tray(let deck):
            guard trayDeck == deck, over == .tray || over.map(isTrayWindow) == true,
                  let live = arrangement.decks.first(where: { $0.id == deck })
            else { return nil }
            let frames = live.windows.map { hoverFrames[.trayWindow($0.id)] }
            let gap = Self.trayGap(frames)
            return target(.members(deck), frames: frames, own: live.windows.firstIndex(of: drag.window),
                          at: drag.point, gap: gap)
        case .grid where view == .spaces:
            switch over {
            case .window(let id), .desktop(let id):
                // The middle of another card groups with it.
                if id != drag.window.id, let frame = over.flatMap({ hoverFrames[$0] }),
                   Reorder.isMiddle(drag.point, of: frame) { return nil }
            case .grid, nil:
                break
            default:
                return nil
            }
            let shown = arrangement.ungrouped
            return target(.spaces, frames: shown.map { hoverFrames[cardTarget(of: $0)] },
                          own: shown.firstIndex(of: drag.window), at: drag.point, gap: Metrics.gap)
        default:
            return nil
        }
    }

    /// Moves the dragged card to `reorder`'s place.
    func apply(_ reorder: ReorderTarget, moving drag: Drag) {
        let arrangement = arrangement
        switch reorder.kind {
        case .decks:
            guard let deck = drag.deck else { return }
            let mine = decks.filter { $0.kind == view }
            let order = Reorder.moving(deck, to: reorder.slot, among: arrangement.decks.map(\.id), in: mine.map(\.id))
            let byID = Dictionary(mine.map { ($0.id, $0) }) { first, _ in first }
            decks = decks.filter { $0.kind != view } + order.compactMap { byID[$0] }
        case .spaces:
            let all = Reorder.ordered(spaceItems, by: spaceOrder) { $0.space.uuid }
            let uuid = Dictionary(all.map { ($0.item.id, $0.space.uuid) }) { first, _ in first }
            guard let moved = uuid[drag.window.id] else { return }
            let shown = arrangement.ungrouped.compactMap { uuid[$0.id] }
            spaceOrder = Reorder.moving(moved, to: reorder.slot, among: shown, in: all.map(\.space.uuid))
        case .members(let id):
            guard let index = decks.firstIndex(where: { $0.id == id }),
                  let live = arrangement.decks.first(where: { $0.id == id })
            else { return }
            let members = decks[index].members
            func member(_ window: WindowInfo) -> DeckMember? { members.first { $0.windowID == window.id } }
            guard let moved = member(drag.window) else { return }
            decks[index].members = Reorder.moving(
                moved, to: reorder.slot, among: live.windows.compactMap(member), in: members
            )
        }
    }

    /// Brings a deck's windows forward, the one in front most recently in front again.
    func pick(deck live: LiveDeck) {
        let natural = view == .windows ? windows : spaceItems.map(\.item)
        let rank = Dictionary(natural.enumerated().map { ($1.id, $0) }) { first, _ in first }
        pick(live.windows.sorted { rank[$0.id] ?? .max < rank[$1.id] ?? .max }.reversed())
    }

    private func target(
        _ kind: ReorderTarget.Kind, frames: [CGRect?], own: Int?, at point: CGPoint, gap: CGFloat
    ) -> ReorderTarget? {
        let frames = frames.compactMap(\.self)
        guard let slot = Reorder.slot(at: point, among: frames, reach: gap * 2),
              !Reorder.isNoMove(from: own, to: slot),
              let marker = Reorder.marker(for: slot, among: frames, gap: gap)
        else { return nil }
        return ReorderTarget(kind: kind, slot: slot, marker: marker)
    }

    /// The target a grid item's card reports itself as.
    private func cardTarget(of item: WindowInfo) -> HoverTarget {
        view == .spaces && SpaceItems.isDesktop(item) ? .desktop(item.id) : .window(item.id)
    }

    private func isTrayWindow(_ target: HoverTarget) -> Bool {
        if case .trayWindow = target { true } else { false }
    }

    /// The space between the tray's cards, which scales with the tray.
    private static func trayGap(_ frames: [CGRect?]) -> CGFloat {
        let frames = frames.compactMap(\.self)
        guard frames.count > 1 else { return Metrics.gap }
        return max(0, frames[1].minX - frames[0].maxX)
    }
}

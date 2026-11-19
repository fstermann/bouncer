import CoreGraphics

/// Where a card dragged among others lands, and the lists it reorders.
enum Reorder {
    /// The place a drop at `point` takes among `frames`, cards in the order shown: the index of the card it
    /// goes before, or `frames.count` for after the last. Decided by the nearest card's half the point is
    /// on. `nil` when the point is farther than `reach` from every card.
    static func slot(at point: CGPoint, among frames: [CGRect], reach: CGFloat) -> Int? {
        let distances = frames.map { distance(from: point, to: $0) }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }),
              distances[nearest] <= reach
        else { return nil }
        return point.x < frames[nearest].midX ? nearest : nearest + 1
    }

    /// Whether dropping the card at `from` into `slot` leaves it where it is.
    static func isNoMove(from: Int?, to slot: Int) -> Bool {
        guard let from else { return false }
        return slot == from || slot == from + 1
    }

    /// The upright line marking `slot`: halfway into the gap before the card it goes before, or after the
    /// card before it at the end of a row. `gap` is the space between cards in a row.
    static func marker(for slot: Int, among frames: [CGRect], gap: CGFloat) -> CGRect? {
        guard !frames.isEmpty, (0...frames.count).contains(slot) else { return nil }
        let lineX: CGFloat
        let card: CGRect
        if slot < frames.count, slot == 0 || !sameRow(frames[slot - 1], frames[slot]) {
            card = frames[slot]
            lineX = card.minX - gap / 2
        } else {
            card = frames[slot - 1]
            lineX = slot < frames.count ? (card.maxX + frames[slot].minX) / 2 : card.maxX + gap / 2
        }
        return CGRect(x: lineX - 1.5, y: card.minY, width: 3, height: card.height)
    }

    /// Whether `point` is over the middle half of `frame`, where a drop groups rather than reorders.
    static func isMiddle(_ point: CGPoint, of frame: CGRect) -> Bool {
        frame.contains(point) && abs(point.x - frame.midX) < frame.width / 4
    }

    /// `list` with `item` moved to `slot` among `shown`, the part of `list` on screen in the same order:
    /// before the shown one at `slot`, or right after the last shown one. Unchanged if either is missing.
    static func moving<Item: Equatable>(_ item: Item, to slot: Int, among shown: [Item], in list: [Item]) -> [Item] {
        guard list.contains(item), (0...shown.count).contains(slot) else { return list }
        let anchor = slot < shown.count ? shown[slot] : shown.last
        guard let anchor, anchor != item else { return list }
        var moved = list.filter { $0 != item }
        guard let index = moved.firstIndex(of: anchor) else { return list }
        moved.insert(item, at: slot < shown.count ? index : index + 1)
        return moved
    }

    /// `items` with those `order` names first, in its order, then the rest as they were.
    static func ordered<Item>(_ items: [Item], by order: [String], key: (Item) -> String) -> [Item] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        let known = items.filter { rank[key($0)] != nil }.sorted { rank[key($0)] ?? 0 < rank[key($1)] ?? 0 }
        return known + items.filter { rank[key($0)] == nil }
    }

    private static func sameRow(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.midY - second.midY) < min(first.height, second.height) / 2
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

import CoreGraphics

/// One status item, as the window server describes it.
///
/// Frames are in Core Graphics screen coordinates — top-left origin, y growing downwards —
/// because that is what `CGWindowListCopyWindowInfo` reports and what the capture APIs
/// take. Converting to AppKit's bottom-left origin is the window layer's job, not this
/// one's.
public struct MenuBarItem: Hashable, Sendable {
    public let windowID: UInt32
    public let frame: CGRect

    public init(windowID: UInt32, frame: CGRect) {
        self.windowID = windowID
        self.frame = frame
    }
}

/// Pure geometry for the standalone bar. No capture, no windows, no AppKit — so the
/// decisions can be tested without a running app, the same way `MenuBarVisibility` is.
///
/// The one thing worth stating up front, because it inverts the divider mechanism: an item
/// only has pixels while it is being drawn. Pushed past the edge of the display it has
/// none, so the standalone bar cannot replicate a section that is hidden the usual way. It
/// reveals the section instead and covers that stretch of menu bar, which is why the two
/// rectangles below matter.
public enum MenuBarItemGeometry {
    /// Items whose horizontal extent falls outside every display — the hidden section,
    /// identified without needing to know which divider put them there.
    ///
    /// Tested against the item's midpoint rather than its edges: an item straddling the
    /// edge of the display is partly drawn, and partly drawn is not hidden.
    public static func offScreen(_ items: [MenuBarItem], screens: [CGRect]) -> [MenuBarItem] {
        items.filter { item in
            !screens.contains { $0.minX...$0.maxX ~= item.frame.midX }
        }
    }

    /// A divider is a status item thousands of points wide; a real item never is. Used to
    /// keep Bouncer's own dividers out of the set being replicated.
    ///
    /// The threshold is deliberately far above any plausible item: the widest seen in
    /// practice is a clock at ~70 pt, and an expanded divider is clamped by the system to
    /// roughly the width of the bar.
    public static let dividerWidthThreshold: CGFloat = 300

    public static func excludingDividers(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.filter { $0.frame.width < dividerWidthThreshold }
    }

    /// The stretch of menu bar the cover has to hide, once the section is revealed.
    ///
    /// `nil` when there is nothing to cover, which is a real state — the section can be
    /// empty — and not an error.
    public static func coverRect(for items: [MenuBarItem]) -> CGRect? {
        guard let first = items.first else { return nil }
        return items.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Where each item's replica sits in the standalone bar.
    ///
    /// Replicas mirror their real horizontal positions rather than being packed together,
    /// and that is forced rather than chosen. A status item anchors its menu to its own
    /// window — measured at 4 pt off the item's own x — and we cannot move the real item.
    /// So a packed bar would open the third replica's menu under wherever the real item
    /// happens to sit, which is the detail that makes a replica bar feel fake. Mirroring
    /// costs the visual tidiness of packing and buys menus that land where they were asked
    /// for.
    ///
    /// Positions are relative to the bar's own origin, which is the section's leftmost
    /// item; widths are each item's own, because that width is the item's choice and a
    /// clock that reflows would be worse than one that does not.
    public static func layout(_ items: [MenuBarItem]) -> (positions: [MenuBarItem: CGRect], size: CGSize) {
        guard let bounds = coverRect(for: items) else { return ([:], .zero) }
        var positions: [MenuBarItem: CGRect] = [:]

        for item in items {
            positions[item] = CGRect(
                x: item.frame.minX - bounds.minX,
                y: 0,
                width: item.frame.width,
                height: item.frame.height
            )
        }
        return (positions, bounds.size)
    }

    /// Maps a point inside the standalone bar back to the point on the real item it
    /// replicates, so a click can be forwarded to where the item actually is.
    ///
    /// Returns `nil` when the point hits a gap rather than a replica — the bar should
    /// swallow that click rather than guess at a neighbour.
    public static func itemHit(
        at point: CGPoint,
        positions: [MenuBarItem: CGRect]
    ) -> (item: MenuBarItem, pointOnItem: CGPoint)? {
        guard let (item, rect) = positions.first(where: { $0.value.contains(point) }) else { return nil }
        // Same offset within the replica, applied to the real item's frame.
        let offset = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        return (item, CGPoint(x: item.frame.minX + offset.x, y: item.frame.minY + offset.y))
    }
}

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

    /// Where the section will land when it is revealed, before it has.
    ///
    /// The cover has to be over that stretch before the reveal — that is what keeps the items
    /// from being seen — so it cannot be measured, only worked out. Which it can be, exactly:
    /// macOS packs status items edge to edge, so the section is as wide as its items' own
    /// widths added up, and it lands immediately left of the run of items already on screen.
    ///
    /// The divider does not get out of the way, which is the one thing worth stating: it stops
    /// being thousands of points wide, but it stays in the bar between the section and the run
    /// and the section lands to the left of it, not against the run.
    ///
    /// One thing it does not account for: an always-hidden section that holds items has them
    /// in `parked` although they are not the ones coming back, so the strip comes out wider
    /// than the section by their width. Erring wide is the safe direction — the cover hides
    /// more bar than it needs to, never less.
    ///
    /// - Parameters:
    ///   - parked: the items about to be revealed, wherever they are now.
    ///   - all: every item in the bar, dividers excluded, used to find the run to land beside.
    public static func landingStrip(for parked: [MenuBarItem], leftOf all: [MenuBarItem]) -> CGRect {
        let width = parked.map(\.frame.width).reduce(0, +)
        let height = parked.map(\.frame.height).max() ?? 0
        let edge = leftEdgeOfTheRun(in: all) - collapsedDividerWidth
        return CGRect(x: edge - width, y: 0, width: width, height: height)
    }

    /// What the divider takes up in the bar once it is no longer expanded.
    ///
    /// Measured at 17 pt: the divider is set to a hairline while its section is revealed, and
    /// macOS pads every status item either side of the width it asks for. The section lands
    /// left of that, so leaving it out puts the whole strip 17 pt too far right.
    static let collapsedDividerWidth: CGFloat = 17

    /// The left edge of the run of items at the right of the bar.
    ///
    /// Not simply the leftmost item on screen: a collapsed divider sits alone at the far left,
    /// and anchoring on that puts the strip off the display, where it hides nothing at all.
    /// Walked from the right instead, stopping at the first gap too wide to be the space
    /// between two neighbours.
    private static func leftEdgeOfTheRun(in all: [MenuBarItem]) -> CGFloat {
        let onScreen = all.filter { $0.frame.minX >= 0 }.sorted { $0.frame.minX > $1.frame.minX }
        guard var edge = onScreen.first?.frame.minX else { return 0 }
        for item in onScreen.dropFirst() {
            guard edge - item.frame.maxX < widestGapInARun else { break }
            edge = item.frame.minX
        }
        return edge
    }

    /// More space than two neighbouring items ever leave between them. Measured at zero — they
    /// are packed edge to edge — so this only has to be under the width of a whole item.
    private static let widestGapInARun: CGFloat = 80

    /// The frames the section will have once it is revealed: its items packed edge to edge
    /// from the left of the strip it is going to land in.
    ///
    /// The order is given rather than read off the parked frames, because macOS does not
    /// always put a section back in the order it sits in while it is away — two items of the
    /// same width were measured trading places on the way back. Pass the order the section
    /// came back in last time; items it does not mention keep the order they are parked in,
    /// after the ones it does.
    public static func packed(
        _ items: [MenuBarItem], into strip: CGRect, like order: [UInt32]
    ) -> [MenuBarItem] {
        var edge = strip.minX
        return sorted(items, like: order).map { item in
            defer { edge += item.frame.width }
            return MenuBarItem(
                windowID: item.windowID,
                frame: CGRect(
                    x: edge, y: strip.minY, width: item.frame.width, height: item.frame.height
                )
            )
        }
    }

    private static func sorted(_ items: [MenuBarItem], like order: [UInt32]) -> [MenuBarItem] {
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
        return items.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.windowID] ?? .max
                let right = rank[rhs.element.windowID] ?? .max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
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

    /// The item whose replica contains `point`, so a click can be forwarded to it.
    ///
    /// Returns `nil` when the point hits a gap rather than a replica — the bar should
    /// swallow that click rather than guess at a neighbour.
    public static func item(at point: CGPoint, positions: [MenuBarItem: CGRect]) -> MenuBarItem? {
        positions.first { $0.value.contains(point) }?.key
    }
}

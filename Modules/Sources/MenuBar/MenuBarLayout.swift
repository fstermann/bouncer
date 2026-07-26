import CoreGraphics

/// Pure classification of scanned items into sections, given where the dividers sit.
///
/// Kept free of AppKit so it is directly testable.
public enum MenuBarLayout {
    /// Items are ordered right to left by macOS, so a divider's x-position is the
    /// boundary: anything to its right is in the section above it.
    ///
    /// - Parameter alwaysHiddenDividerMinX: `nil` when the always-hidden section is off.
    public static func classify(
        items: [MenuBarItem],
        hiddenDividerMinX: CGFloat,
        alwaysHiddenDividerMinX: CGFloat?
    ) -> [(item: MenuBarItem, section: MenuBarSection)] {
        items.map { item in
            if item.frame.minX > hiddenDividerMinX {
                (item, .visible)
            } else if let alwaysHiddenDividerMinX, item.frame.minX < alwaysHiddenDividerMinX {
                (item, .alwaysHidden)
            } else {
                (item, .hidden)
            }
        }
    }
}

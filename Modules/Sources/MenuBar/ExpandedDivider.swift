import CoreGraphics

/// How wide a divider is while it hides its section.
///
/// Up to macOS 26 a status item could be wider than the bar, and pushed everything left of it off
/// the display. From macOS 27 the menu bar evicts an item past a length limit (741 pt on a 14-inch
/// MacBook Pro), and leaves the rest where they were. Short of that, it moves the items it has no
/// room for behind a chevron, which shows them left of the notch, and drops what does not fit
/// there either, with everything left of it and the chevron too. So a divider wider than the bar
/// left of the notch hides everything left of it and stays. Measured in SPIKES.md.
enum ExpandedDivider {
    /// Wider than any conceivable menu bar.
    static let legacyLength: CGFloat = 10_000

    /// - Parameters:
    ///   - rightEdge: where the divider's right edge sits in the bar, `nil` before it has been placed.
    ///   - notch: the display's notch, `nil` where the bar still takes an item wider than itself.
    ///   - kept: the right edge of an item that must stay visible, Bouncer's own icon. macOS 27 keeps
    ///     an item where the user last dragged it, whatever its seed says, so the icon can sit left
    ///     of the divider, where hiding it would leave nothing to reveal the section with.
    /// - Returns: the bar's width left of the notch, which however short the front app's menus are
    ///   leaves the chevron no room to show the divider in, or `nil` while it cannot be worked out
    ///   yet or must not hide anything.
    static func length(rightEdge: CGFloat?, notch: ClosedRange<CGFloat>?, keeping kept: CGFloat? = nil) -> CGFloat? {
        guard let notch else { return legacyLength }
        guard let rightEdge else { return nil }
        if let kept, kept <= rightEdge { return nil }
        return rightEdge > notch.upperBound ? notch.lowerBound : 1
    }
}

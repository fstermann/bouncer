import CoreGraphics

/// How wide a divider is while it hides its section.
///
/// Up to macOS 26 a status item could be wider than the bar, and pushed everything left of it off
/// the display. From macOS 27 the menu bar evicts an item past a length limit (741 pt on a 14-inch
/// MacBook Pro), and leaves the rest where they were. Short of that, it moves the items it has no
/// room for behind a chevron, which shows them left of the notch, and drops what does not fit
/// there either, with everything left of it and the chevron too. So a divider wider than the bar
/// left of the notch hides everything left of it and stays. Without a notch the overflow has room up
/// to the app menus, more than the limit, so no length hides everything there. Measured in SPIKES.md.
enum ExpandedDivider {
    /// Wider than any conceivable menu bar.
    static let legacyLength: CGFloat = 10_000
    /// Under the eviction limit, measured at 741 to 760 pt on a 1512 pt display with and without a
    /// notch, with room to spare: past it nothing is hidden at all.
    static let notchlessLength: CGFloat = 730

    /// - Parameters:
    ///   - rightEdge: where the divider's right edge sits in the bar, `nil` before it has been placed.
    ///   - notch: the display's notch, `nil` without one.
    ///   - evicts: whether the bar evicts an item past a length limit, from macOS 27.
    ///   - kept: the right edge of an item that must stay visible, Bouncer's own icon. macOS 27 keeps
    ///     an item where the user last dragged it, whatever its seed says, so the icon can sit left
    ///     of the divider, where hiding it would leave nothing to reveal the section with.
    /// - Returns: the bar's width left of the notch, which however short the front app's menus are
    ///   leaves the chevron no room to show the divider in; without a notch, as long as the bar
    ///   allows, which leaves the chevron and the items nearest the divider in view. `nil` while it
    ///   cannot be worked out yet or must not hide anything.
    static func length(
        rightEdge: CGFloat?, notch: ClosedRange<CGFloat>?, evicts: Bool, keeping kept: CGFloat? = nil
    ) -> CGFloat? {
        guard evicts else { return legacyLength }
        guard let rightEdge else { return nil }
        if let kept, kept <= rightEdge { return nil }
        guard let notch else { return notchlessLength }
        return rightEdge > notch.upperBound ? notch.lowerBound : 1
    }
}

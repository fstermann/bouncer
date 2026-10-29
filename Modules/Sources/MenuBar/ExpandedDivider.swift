import CoreGraphics

/// How wide a divider is while it hides its section.
///
/// Up to macOS 26 a status item could be wider than the bar, and pushed everything left of it off
/// the display. From macOS 27 the menu bar evicts an item whose left edge would reach past the
/// notch into the app menus, and leaves the rest where they were. Short of that, it moves the
/// items it has no room for behind a chevron, and the chevron goes too once it lands under the
/// notch. So a divider reaching into the middle of the notch hides everything left of it and stays.
enum ExpandedDivider {
    /// Wider than any conceivable menu bar.
    static let legacyLength: CGFloat = 10_000

    /// - Parameters:
    ///   - rightEdge: where the divider's right edge sits in the bar, `nil` before it has been placed.
    ///   - notch: the display's notch, `nil` where the bar still takes an item wider than itself.
    ///   - kept: the right edge of an item that must stay visible, Bouncer's own icon. macOS 27 keeps
    ///     an item where the user last dragged it, whatever its seed says, so the icon can sit left
    ///     of the divider, where hiding it would leave nothing to reveal the section with.
    /// - Returns: the length that puts the divider's left edge in the middle of the notch, or `nil`
    ///   while it cannot be worked out yet or must not hide anything.
    static func length(rightEdge: CGFloat?, notch: ClosedRange<CGFloat>?, keeping kept: CGFloat? = nil) -> CGFloat? {
        guard let notch else { return legacyLength }
        guard let rightEdge else { return nil }
        if let kept, kept <= rightEdge { return nil }
        return max(rightEdge - (notch.lowerBound + notch.upperBound) / 2, 1)
    }
}

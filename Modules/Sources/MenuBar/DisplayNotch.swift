import CoreGraphics

/// The stretch of menu bar a display's notch takes up, or a notch-sized stand-in at the top
/// centre of a display without one.
///
/// Pure, so it can be tested without a display: callers pass in what `NSScreen` reports.
public enum DisplayNotch {
    /// The 14-inch MacBook Pro's notch, measured at 185 pt.
    static let standInWidth: CGFloat = 185

    /// - Parameters:
    ///   - left: `auxiliaryTopLeftArea`, the bar left of the notch, `nil` without one.
    ///   - right: `auxiliaryTopRightArea`, the bar right of it.
    ///   - screen: the display's frame.
    /// - Returns: the notch's horizontal extent, and whether it is real.
    public static func range(
        left: CGRect?, right: CGRect?, screen: CGRect
    ) -> (range: ClosedRange<CGFloat>, isReal: Bool) {
        if let left, let right, left.maxX < right.minX { return (left.maxX...right.minX, true) }
        return ((screen.midX - standInWidth / 2)...(screen.midX + standInWidth / 2), false)
    }

    /// Whether `point`, in AppKit screen coordinates, is close enough to the notch to reveal:
    /// in the menu bar, and over the notch or within `reach` of either side of it.
    public static func reveals(
        at point: CGPoint, notch: ClosedRange<CGFloat>, screen: CGRect, menuBarHeight: CGFloat
    ) -> Bool {
        isInMenuBar(point, screen: screen, menuBarHeight: menuBarHeight)
            && (notch.lowerBound - reach)...(notch.upperBound + reach) ~= point.x
    }

    /// Whether `point`, in AppKit screen coordinates, is in the menu bar of `screen`. A point past
    /// its top edge is on a display arranged above it.
    public static func isInMenuBar(_ point: CGPoint, screen: CGRect, menuBarHeight: CGFloat) -> Bool {
        (screen.maxY - menuBarHeight...screen.maxY) ~= point.y
    }

    /// How far either side of the notch still counts as reaching it.
    static let reach: CGFloat = 20
}

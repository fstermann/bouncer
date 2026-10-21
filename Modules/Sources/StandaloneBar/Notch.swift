import AppKit
import MenuBar

/// Where a notch-style bar grows from: the display's notch, or a notch-sized stand-in at the top
/// centre of a display without one.
struct Notch {
    /// The stretch of menu bar it takes up, in window-server x.
    let range: ClosedRange<CGFloat>
    /// False for the stand-in, which has no hardware to grow out of and so fades in as it grows.
    let isReal: Bool
    /// The middle of the display, which the notch is built into. Not the middle of `range`: the
    /// bar either side of the notch was measured at 663 and 664 pt, which puts that half a point
    /// left of the hardware.
    let centre: CGFloat

    /// Transparent margin a notch-style window keeps around its panel, so the spring's overshoot
    /// is drawn rather than clipped flat at the window's edge.
    static let springRoom = CGSize(width: 12, height: 4)
    /// How far a notch-style shelf reaches up over the cover's foot, so the spring overshooting the
    /// shelf's rest never opens a gap between them.
    static let seamOverlap: CGFloat = 4

    /// The notch on the display `frame` is on.
    @MainActor
    static func on(displayOf frame: CGRect) -> Notch? {
        let screen = NSScreen.screens.first { $0.frame.minX...$0.frame.maxX ~= frame.midX } ?? NSScreen.main
        guard let screen else { return nil }
        let notch = DisplayNotch.range(
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, screen: screen.frame
        )
        return Notch(range: notch.range, isReal: notch.isReal, centre: screen.frame.midX)
    }
}

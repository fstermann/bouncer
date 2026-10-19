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

/// The concave fillet joining a notch-style panel to the top edge of the display, the way the
/// notch itself meets it.
final class NotchShoulder: NSView {
    static let radius: CGFloat = 6

    /// - Parameter left: the one on the panel's left, curving into the panel's left edge.
    init(left: Bool) {
        let size = Self.radius
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        let shape = CAShapeLayer()
        let path = CGMutablePath()
        // The square minus a quarter disc centred on the corner away from the panel.
        let centre = CGPoint(x: left ? 0 : size, y: 0)
        path.move(to: CGPoint(x: left ? size : 0, y: size))
        path.addLine(to: CGPoint(x: left ? size : 0, y: 0))
        path.addArc(
            center: centre, radius: size,
            startAngle: left ? 0 : .pi, endAngle: .pi / 2, clockwise: !left
        )
        path.closeSubpath()
        shape.path = path
        shape.fillColor = NSColor.black.cgColor
        layer = shape
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

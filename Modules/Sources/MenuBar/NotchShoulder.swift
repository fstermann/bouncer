import AppKit

/// The concave fillet joining a notch-style panel to the top edge of the display, the way the
/// notch itself meets it.
public final class NotchShoulder: NSView {
    /// The notch's own, as Notchmeister traces it: 4 pt where it meets the top edge, 8 pt at its foot.
    public static let radius: CGFloat = 4

    /// The one on the panel's left, curving into the panel's left edge.
    public let isLeft: Bool

    /// - Parameter left: the one on the panel's left, curving into the panel's left edge.
    public init(left: Bool) {
        isLeft = left
        let size = Self.radius
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        let shape = CAShapeLayer()
        shape.path = Self.path(left: left)
        shape.fillColor = NSColor.black.cgColor
        layer = shape
        wantsLayer = true
    }

    /// The square minus a quarter disc centred on the corner away from the panel.
    public static func path(left: Bool) -> CGPath {
        let size = radius
        let path = CGMutablePath()
        let centre = CGPoint(x: left ? 0 : size, y: 0)
        path.move(to: CGPoint(x: left ? size : 0, y: size))
        path.addLine(to: CGPoint(x: left ? size : 0, y: 0))
        path.addArc(
            center: centre, radius: size,
            startAngle: left ? 0 : .pi, endAngle: .pi / 2, clockwise: !left
        )
        path.closeSubpath()
        return path
    }

    /// Where it sits beside a panel of frame `panel` hanging from the top of the display.
    public func frame(beside panel: CGRect) -> CGRect {
        let size = Self.radius
        return CGRect(x: isLeft ? panel.minX - size : panel.maxX, y: panel.maxY - size, width: size, height: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

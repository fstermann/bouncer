import AppKit

/// The notch grown a little taller, holding the switch to the todo page.
///
/// What the standalone bar is on macOS 27: the items stay in the menu bar either side of the
/// notch, so all the bar adds is this. It slides out of the notch the way the items do.
@MainActor
final class NotchTab {
    static let height: CGFloat = 28
    private static let cornerRadius: CGFloat = 10

    private var window: BarWindow?
    private let view = TabView()

    var onSwitch: (@MainActor () -> Void)? {
        get { view.onSwitch }
        set { view.onSwitch = newValue }
    }

    /// Its outline in AppKit coordinates, up to the top of the display: what the todo page grows from.
    var outline: CGRect? { window?.frame }

    /// Where the pointer counts as having left it, in AppKit coordinates.
    var bottomEdge: CGFloat { window?.frame.minY ?? .infinity }

    /// The frame it rests at under `notch`, in window-server coordinates.
    static func frame(under notch: ClosedRange<CGFloat>, barHeight: CGFloat) -> CGRect {
        CGRect(x: notch.lowerBound, y: 0, width: notch.upperBound - notch.lowerBound, height: barHeight + height)
    }

    func show(at frame: CGRect, over duration: TimeInterval?) async {
        let tab = window ?? make(frame)
        window = tab
        tab.setFrame(cgFrame: frame)
        view.frame = CGRect(origin: .zero, size: frame.size)
        view.setUpLayer()
        tab.orderFrontRegardless()
        await slide(from: Self.tucked, to: 0, over: duration)
    }

    func hide(over duration: TimeInterval?) async {
        guard window != nil else { return }
        await slide(from: 0, to: Self.tucked, over: duration)
        window?.orderOut(nil)
        window = nil
    }

    /// Up into the notch, where the hardware hides it.
    private static let tucked = height + cornerRadius

    private func slide(from start: CGFloat, to end: CGFloat, over duration: TimeInterval?) async {
        guard let layer = view.layer else { return }
        layer.transform = CATransform3DMakeTranslation(0, end, 0)
        guard let duration else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = start
        animation.toValue = end
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: end == 0 ? .easeOut : .easeIn)
        layer.add(animation, forKey: "slide")
        try? await Task.sleep(for: .seconds(duration))
    }

    private func make(_ frame: CGRect) -> BarWindow {
        let tab = BarWindow(frame: frame, level: CoverWindow.aboveItems)
        tab.contentView = view
        return tab
    }
}

private final class TabView: NSView {
    var onSwitch: (@MainActor () -> Void)?
    private let glyph = PageSwitchGlyph.make()

    func setUpLayer() {
        wantsLayer = true
        guard let layer else { return }
        let shape = CAShapeLayer()
        shape.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0, dy: -12).offsetBy(dx: 0, dy: 12),
            cornerWidth: 10, cornerHeight: 10, transform: nil
        )
        shape.fillColor = NSColor.black.cgColor
        layer.sublayers?.filter { $0 is CAShapeLayer }.forEach { $0.removeFromSuperlayer() }
        layer.insertSublayer(shape, at: 0)
        if glyph.superview == nil { addSubview(glyph) }
        glyph.isHidden = false
        let size = PageSwitchGlyph.size
        glyph.frame = CGRect(x: (bounds.width - size) / 2, y: (NotchTab.height - size) / 2, width: size, height: size)
    }

    override func mouseDown(with event: NSEvent) {
        onSwitch?()
    }
}

import AppKit

/// The notch grown sideways behind the section's items, and a little taller under the notch itself,
/// holding the switch to the todo page.
///
/// What the standalone bar is on macOS 27: the items stay in the menu bar either side of the notch,
/// so all the bar adds is this black. It sits at the menu bar's own level, which the window server
/// draws over the bar's backdrop and under its menus and items, so the items show on top of it.
@MainActor
final class NotchTab {
    static let height: CGFloat = 28
    private static let cornerRadius: CGFloat = 10

    private var window: BarWindow?
    private var shadeWindow: BarWindow?
    private let content = NSView()
    private let band = CALayer()
    private let view = TabView()

    var onSwitch: (@MainActor () -> Void)? {
        get { view.onSwitch }
        set { view.onSwitch = newValue }
    }

    /// The tab's outline in AppKit coordinates, up to the top of the display: what the todo page grows from.
    var outline: CGRect? { window?.convertToScreen(view.frame) }

    /// Where the pointer counts as having left it, in AppKit coordinates.
    var bottomEdge: CGFloat { window?.frame.minY ?? .infinity }

    /// The frame the tab rests at under `notch`, in window-server coordinates.
    static func frame(under notch: ClosedRange<CGFloat>, barHeight: CGFloat) -> CGRect {
        CGRect(x: notch.lowerBound, y: 0, width: notch.upperBound - notch.lowerBound, height: barHeight + height)
    }

    /// Slides the tab out at `frame` and grows the band out of the notch across `reach`, in window-server x.
    func show(at frame: CGRect, reaching reach: ClosedRange<CGFloat>, over duration: TimeInterval?) async {
        let whole = CGRect(
            x: min(reach.lowerBound, frame.minX), y: 0,
            width: max(reach.upperBound, frame.maxX) - min(reach.lowerBound, frame.minX), height: frame.height
        )
        let tab = window ?? make(whole)
        window = tab
        tab.setFrame(cgFrame: whole)
        content.frame = CGRect(origin: .zero, size: whole.size)
        view.frame = CGRect(x: frame.minX - whole.minX, y: 0, width: frame.width, height: frame.height)
        view.setUpLayer()
        tab.orderFrontRegardless()

        let barHeight = frame.height - Self.height
        let notch = CGRect(x: view.frame.minX, y: frame.height - barHeight, width: frame.width, height: barHeight)
        let reached = CGRect(
            x: reach.lowerBound - whole.minX, y: notch.minY,
            width: reach.upperBound - reach.lowerBound, height: barHeight
        )
        move(band, to: notch, over: nil)
        move(band, to: reached, over: duration)
        await slide(from: Self.tucked, to: 0, over: duration)
    }

    /// Covers `frame`, in window-server coordinates, above the items, taking its clicks. `nil` takes
    /// the cover away.
    func shade(_ frame: CGRect?) {
        guard let frame else {
            shadeWindow?.orderOut(nil)
            shadeWindow = nil
            return
        }
        let shade = shadeWindow ?? BarWindow(frame: frame, level: CoverWindow.aboveItems)
        shadeWindow = shade
        shade.backgroundColor = .black
        shade.setFrame(cgFrame: frame)
        shade.orderFrontRegardless()
    }

    func hide(over duration: TimeInterval?) async {
        guard window != nil else { return }
        let notch = CGRect(x: view.frame.minX, y: band.frame.minY, width: view.frame.width, height: band.frame.height)
        move(band, to: notch, over: duration)
        await slide(from: 0, to: Self.tucked, over: duration)
        window?.orderOut(nil)
        window = nil
    }

    /// Up into the notch, where the hardware hides it.
    private static let tucked = height + cornerRadius

    private func move(_ layer: CALayer, to frame: CGRect, over duration: TimeInterval?) {
        CATransaction.begin()
        CATransaction.setDisableActions(duration == nil)
        if let duration {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }
        layer.frame = frame
        CATransaction.commit()
    }

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
        let tab = BarWindow(frame: frame, level: .mainMenu)
        content.wantsLayer = true
        band.backgroundColor = NSColor.black.cgColor
        band.cornerRadius = Self.cornerRadius
        band.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        content.layer?.addSublayer(band)
        content.addSubview(view)
        tab.contentView = content
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

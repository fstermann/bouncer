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
    /// Where the tab rests and the window's frame, in window-server coordinates.
    private var tabFrame = CGRect.zero
    private var windowFrame = CGRect.zero
    /// The band's ends, in window-server x.
    private var span: ClosedRange<CGFloat> = 0...0

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
    ///
    /// - Parameter room: how far the band is to go later on, so the window is made that wide now: grown
    ///   while the band moves, it cuts the band's animation short.
    func show(
        at frame: CGRect, reaching reach: ClosedRange<CGFloat>, room: ClosedRange<CGFloat>? = nil,
        over duration: TimeInterval?
    ) async {
        tabFrame = frame
        let tab = window ?? make(frame)
        window = tab
        span = frame.minX...frame.maxX
        place(covering: room ?? reach)
        view.setUpLayer()
        tab.orderFrontRegardless()
        extend(to: reach, over: duration)
        await slide(from: Self.tucked, to: 0, over: duration)
    }

    /// Moves the band's ends to `reach`, in window-server x, once the items have landed somewhere other
    /// than expected.
    func extend(to reach: ClosedRange<CGFloat>, over duration: TimeInterval?) {
        guard window != nil, reach != span else { return }
        place(covering: reach)
        span = reach
        move(band, to: local(reach), over: duration)
    }

    /// Takes the band left of the notch away at once, with the overflow it was behind, which leaves
    /// in one go. Kept any longer, the app menus come back over it.
    func dropLeftHalf() {
        extend(to: tabFrame.minX...max(span.upperBound, tabFrame.maxX), over: nil)
    }

    /// Grows the window to take in `reach` as well, keeping everything in it where it is on screen.
    private func place(covering reach: ClosedRange<CGFloat>) {
        let lower = min(reach.lowerBound, span.lowerBound, tabFrame.minX)
        let upper = max(reach.upperBound, span.upperBound, tabFrame.maxX)
        let needed = CGRect(x: lower, y: 0, width: upper - lower, height: tabFrame.height)
        let whole = windowFrame.isEmpty ? needed : needed.union(windowFrame)
        guard whole != windowFrame else { return }
        windowFrame = whole
        window?.setFrame(cgFrame: whole)
        content.frame = CGRect(origin: .zero, size: whole.size)
        view.frame = CGRect(x: tabFrame.minX - whole.minX, y: 0, width: tabFrame.width, height: tabFrame.height)
        move(band, to: local(span), over: nil)
    }

    /// `reach` in the window's own coordinates, the bar's height tall.
    private func local(_ reach: ClosedRange<CGFloat>) -> CGRect {
        let barHeight = tabFrame.height - Self.height
        return CGRect(
            x: reach.lowerBound - windowFrame.minX, y: tabFrame.height - barHeight,
            width: reach.upperBound - reach.lowerBound, height: barHeight
        )
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
        span = tabFrame.minX...tabFrame.maxX
        move(band, to: local(span), over: duration)
        await slide(from: 0, to: Self.tucked, over: duration)
        window?.orderOut(nil)
        window = nil
        windowFrame = .zero
    }

    /// Up into the notch, where the hardware hides it.
    private static let tucked = height + cornerRadius

    /// Explicit, from where the layer is drawn right now: an implicit frame change was seen starting
    /// from somewhere else entirely, so one end of the band jumped.
    private func move(_ layer: CALayer, to frame: CGRect, over duration: TimeInterval?) {
        let start = layer.presentation()?.frame ?? layer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = frame
        CATransaction.commit()
        layer.removeAnimation(forKey: "move")
        guard let duration else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = start.width
        animation.toValue = frame.width
        let position = CABasicAnimation(keyPath: "position.x")
        position.fromValue = start.midX
        position.toValue = frame.midX
        let group = CAAnimationGroup()
        group.animations = [animation, position]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "move")
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

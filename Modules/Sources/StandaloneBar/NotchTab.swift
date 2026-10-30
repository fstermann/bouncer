import AppKit

/// The notch grown sideways behind the section's items, with the switch to the todo page where the
/// chevron sits.
///
/// What the standalone bar is on macOS 27: the items stay in the menu bar either side of the notch,
/// so all the bar adds is this black. It sits at the menu bar's own level, which the window server
/// draws over the bar's backdrop and under its menus and items, so the items show on top of it.
@MainActor
final class NotchTab {
    enum Side { case left, right }

    private static let cornerRadius: CGFloat = 10

    private var window: BarWindow?
    private var shadeWindow: BarWindow?
    private var coverWindow: BarWindow?
    private let content = NSView()
    private let band = CALayer()
    /// The band again, above the items, in halves that meet over the notch: each side comes and
    /// goes behind its own.
    private let leftCover = CALayer()
    private let rightCover = CALayer()
    private let switchView = SwitchView()
    /// The notch the band grows out of and the window's frame, in window-server coordinates.
    private var tabFrame = CGRect.zero
    private var windowFrame = CGRect.zero
    /// The band's ends, in window-server x.
    private var span: ClosedRange<CGFloat> = 0...0

    var onSwitch: (@MainActor () -> Void)? {
        get { switchView.onSwitch }
        set { switchView.onSwitch = newValue }
    }

    /// The notch in AppKit coordinates, the bar's height tall: what the todo page grows from.
    var outline: CGRect? { window.map { _ in BarWindow.appKitFrame(for: tabFrame) } }

    #if DEV
    /// The band's ends, in window-server x, `nil` while it is not shown.
    var devSpan: ClosedRange<CGFloat>? { window == nil ? nil : span }
    #endif

    /// Where the pointer counts as having left it, in AppKit coordinates.
    var bottomEdge: CGFloat { window?.frame.minY ?? .infinity }

    /// The notch the band grows out of, in window-server coordinates.
    static func frame(under notch: ClosedRange<CGFloat>, barHeight: CGFloat) -> CGRect {
        CGRect(x: notch.lowerBound, y: 0, width: notch.upperBound - notch.lowerBound, height: barHeight)
    }

    /// Grows the band out of the notch at `frame` across `reach`, in window-server x, and returns once it has.
    ///
    /// - Parameter room: how far the band is to go later on, so the window is made that wide now: grown
    ///   while the band moves, it cuts the band's animation short.
    /// - Parameter covered: whether the band also hides the items until `uncover`.
    func show(
        at frame: CGRect, reaching reach: ClosedRange<CGFloat>, room: ClosedRange<CGFloat>? = nil,
        covered: Bool = false, over duration: TimeInterval?
    ) async {
        tabFrame = frame
        let tab = window ?? make(frame)
        window = tab
        span = frame.minX...frame.maxX
        place(covering: room ?? reach)
        tab.orderFrontRegardless()
        if covered { self.cover(over: nil) }
        extend(to: reach, over: duration)
        if let duration { try? await Task.sleep(for: .seconds(duration)) }
    }

    /// Moves the band's ends to `reach`, in window-server x, once the items have landed somewhere other
    /// than expected.
    func extend(to reach: ClosedRange<CGFloat>, over duration: TimeInterval?) {
        guard window != nil, reach != span else { return }
        place(covering: reach)
        span = reach
        moveBand(over: duration)
    }

    /// Moves the band's right end out to `end`, in window-server x, if it falls short of it.
    func grow(rightTo end: CGFloat, over duration: TimeInterval?) {
        extend(to: span.lowerBound...max(end, span.upperBound), over: duration)
    }

    /// Fades black in over the items on both sides, which can then come and go unseen.
    func cover(over duration: TimeInterval?) {
        guard window != nil else { return }
        let covering = coverWindow ?? makeCover()
        coverWindow = covering
        covering.setFrame(cgFrame: windowFrame)
        moveCovers(over: nil)
        for side in [Side.left, .right] { fade(cover(on: side), to: 1, over: duration) }
        covering.orderFrontRegardless()
    }

    /// Fades the cover off `side`, showing its items.
    func uncover(_ side: Side, over duration: TimeInterval?) async {
        guard coverWindow != nil else { return }
        fade(cover(on: side), to: 0, over: duration)
        if let duration { try? await Task.sleep(for: .seconds(duration)) }
        // Still up on the other side, or covering again for a close.
        guard leftCover.opacity == 0, rightCover.opacity == 0 else { return }
        coverWindow?.orderOut(nil)
        coverWindow = nil
    }

    private func cover(on side: Side) -> CALayer {
        side == .left ? leftCover : rightCover
    }

    private func moveCovers(over duration: TimeInterval?) {
        move(leftCover, to: local(span.lowerBound...max(span.lowerBound, tabFrame.maxX)), over: duration)
        move(rightCover, to: local(min(span.upperBound, tabFrame.minX)...span.upperBound), over: duration)
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
        coverWindow?.setFrame(cgFrame: whole)
        content.frame = CGRect(origin: .zero, size: whole.size)
        moveBand(over: nil)
    }

    private func moveBand(over duration: TimeInterval?) {
        move(band, to: local(span), over: duration)
        if coverWindow != nil { moveCovers(over: duration) }
    }

    /// `reach` in the window's own coordinates, the bar's height tall.
    private func local(_ reach: ClosedRange<CGFloat>) -> CGRect {
        CGRect(
            x: reach.lowerBound - windowFrame.minX, y: 0,
            width: reach.upperBound - reach.lowerBound, height: tabFrame.height
        )
    }

    /// Covers `frame`, in window-server coordinates, above the items, with the switch to the todo
    /// page at its right end, which takes its clicks. `nil` takes the cover away.
    func shade(_ frame: CGRect?) {
        guard let frame else {
            shadeWindow?.orderOut(nil)
            shadeWindow = nil
            return
        }
        let shade = shadeWindow ?? BarWindow(frame: frame, level: CoverWindow.aboveItems)
        shadeWindow = shade
        shade.backgroundColor = .black
        shade.contentView = switchView
        shade.setFrame(cgFrame: frame)
        switchView.placeGlyph()
        // Under the cover, so the switch shows and goes with the items.
        if let coverWindow {
            shade.order(.below, relativeTo: coverWindow.windowNumber)
        } else {
            shade.orderFrontRegardless()
        }
    }

    func hide(over duration: TimeInterval?) async {
        guard window != nil else { return }
        span = tabFrame.minX...tabFrame.maxX
        moveBand(over: duration)
        if let duration { try? await Task.sleep(for: .seconds(duration)) }
        window?.orderOut(nil)
        window = nil
        coverWindow?.orderOut(nil)
        coverWindow = nil
        windowFrame = .zero
    }

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

    private func fade(_ layer: CALayer, to opacity: Float, over duration: TimeInterval?) {
        let start = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        guard let duration else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = opacity
        animation.duration = duration
        layer.add(animation, forKey: "fade")
    }

    private func make(_ frame: CGRect) -> BarWindow {
        let tab = BarWindow(frame: frame, level: .mainMenu)
        content.wantsLayer = true
        Self.shape(band)
        content.layer?.addSublayer(band)
        tab.contentView = content
        return tab
    }

    private func makeCover() -> BarWindow {
        let covering = BarWindow(frame: windowFrame, level: CoverWindow.aboveItems)
        covering.ignoresMouseEvents = true
        let content = NSView(frame: CGRect(origin: .zero, size: windowFrame.size))
        content.wantsLayer = true
        for side in [Side.left, .right] {
            Self.shape(cover(on: side))
            cover(on: side).opacity = 0
            content.layer?.addSublayer(cover(on: side))
        }
        covering.contentView = content
        return covering
    }

    private static func shape(_ layer: CALayer) {
        layer.backgroundColor = NSColor.black.cgColor
        layer.cornerRadius = cornerRadius
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
}

private final class SwitchView: NSView {
    var onSwitch: (@MainActor () -> Void)?
    private let glyph = PageSwitchGlyph.make()

    /// Over where the chevron sits, at the shade's right end.
    func placeGlyph() {
        if glyph.superview == nil { addSubview(glyph) }
        glyph.isHidden = onSwitch == nil
        let size = PageSwitchGlyph.size
        glyph.frame = CGRect(
            x: bounds.maxX - size - PageSwitchGlyph.inset, y: (bounds.height - size) / 2, width: size, height: size
        )
    }

    override func mouseDown(with event: NSEvent) {
        onSwitch?()
    }
}

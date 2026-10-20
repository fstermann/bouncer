import AppKit
import Settings

/// Hides the replicated items by covering them, without moving them.
///
/// The items have to stay on the display: pushed off it they stop being drawn, and an item
/// that is not drawn cannot be photographed. Covering costs nothing by comparison — a window
/// capture ignores whatever is on top of it — so the section is revealed into its normal
/// place and this is drawn over it.
///
/// Dressed by `BarSurface`, the same as the shelf below, and only over the stretch the
/// section occupies. It used to be a capture of the bar spanning the bar's whole width, which
/// matched the real thing for exactly as long as the real thing held still: swapping the
/// entire bar for a photograph and back was visible as the bar twitching, the still knew
/// nothing about shadows cast over it afterwards, and taking it was what put the recording
/// indicator in the bar to begin with.
///
/// It is also the trailing half of the panel that slides out of the menu bar, which is why the
/// surface is a view inside the window rather than the window itself: it arrives from above,
/// clipped to the strip until it gets there.
@MainActor
public final class CoverWindow {
    /// Read by `NotchSlide`, which fades it while a notch stand-in grows in or goes away.
    private(set) var window: BarWindow?
    private let surface = NSView()
    /// The dimming layer over the cover's glass, worn while the section underneath is
    /// moving. Faded through `BarSurface.fade`, together with the shelf's, so the dim never
    /// shows as a step at the seam between them.
    private(set) var veil: NSView?

    /// How the cover is painted. Set by the controller before each open, with the shelf's,
    /// so the two halves of the panel cannot disagree.
    var style: BarStyle = .automatic
    /// The notch a notch-style cover grows out of, found when it is shown. The cover reaches it
    /// from wherever the section sits, and wears shoulders where it meets the top of the display.
    private(set) var notch: Notch?

    public init() {
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
    }

    /// The part that moves. Parked and run by the controller, with the shelf's, so the two
    /// halves of the panel cannot come apart.
    var panel: NSView { surface }

    /// Shows the cover over `rect`, in window-server coordinates.
    ///
    /// Sits one level above the status items so it hides them, and well below the pop-up
    /// menu level, so an item's menu still opens over the top when its replica is clicked.
    public func show(over rect: CGRect) {
        if window == nil { notch = style == .notch ? Notch.on(displayOf: rect) : nil }
        let frame = windowFrame(over: rect)
        let cover = window ?? make(frame)
        window = cover
        cover.setFrame(cgFrame: frame)
        // Keeps its vertical origin, so a cover tightened onto the section it has just hidden is
        // not dragged back to where its descent started.
        let resting = restingSurface(in: frame.size)
        surface.frame = CGRect(x: resting.minX, y: surface.frame.minY, width: resting.width, height: resting.height)
        cover.orderFrontRegardless()
    }

    /// The surface where it rests: the whole window, less the shoulders and spring room either side.
    func restingSurface(in size: CGSize) -> CGRect {
        CGRect(x: margin, y: 0, width: size.width - margin * 2, height: size.height)
    }

    /// The surface drawn in to the notch, where a notch-style cover starts from and ends.
    func surfaceGathered(into notch: Notch) -> CGRect? {
        guard let window else { return nil }
        return CGRect(
            x: notch.range.lowerBound - window.frame.minX, y: 0,
            width: notch.range.upperBound - notch.range.lowerBound, height: window.frame.height
        )
    }

    private var margin: CGFloat { notch == nil ? 0 : NotchShoulder.radius + Notch.springRoom.width }

    private func windowFrame(over rect: CGRect) -> CGRect {
        MenuBarItemGeometry.span(of: rect, reaching: notch?.range).insetBy(dx: -margin, dy: 0)
    }

    private static let aboveItems = NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 1)

    /// Lifts the cover clear of its window, ready to be run back down into it.
    func park(by travel: CGFloat) {
        surface.setFrameOrigin(CGPoint(x: 0, y: travel))
    }

    /// Settles the cover onto the section as it now stands.
    ///
    /// On the way in that is a move of nothing at all: where the section would land was worked
    /// out while the cover was still parked, and the answer is exact to the point unless an
    /// always-hidden section is holding items. After a rearrangement it is a real change of
    /// width — the section is one item wider or narrower than it was. Given time to do it in,
    /// either glides rather than jumping. Not awaited: nothing is waiting on it.
    func settle(onto rect: CGRect, over duration: TimeInterval?) {
        guard let window, let duration else { show(over: rect); return }
        let frame = windowFrame(over: rect)
        // Resized at once rather than with the window. The surface is what is actually painted,
        // and a window that grows around a surface that did not shows the real items through the
        // stretch it has just gained; being briefly wider than the window costs nothing, because
        // it is clipped to it. A notch-style surface is left to follow the window instead, which
        // keeps its shoulders at the window's edges.
        if notch == nil { surface.setFrameSize(frame.size) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(BarWindow.appKitFrame(for: frame), display: true)
        }
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func make(_ rect: CGRect) -> BarWindow {
        let cover = BarWindow(frame: rect, level: Self.aboveItems)
        // Clicks belong to the items underneath, which are painted over rather than moved.
        // `ClickShield` is what stops one reaching an icon nobody can see.
        cover.ignoresMouseEvents = true
        surface.frame = restingSurface(in: rect.size)
        veil = BarSurface.dress(surface, in: style, coveringIcons: true)
        // Only a notch-style cover is ever rounded, and only while it stands alone in the bar.
        surface.layer?.cornerRadius = 0
        surface.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        dressShoulders()
        // The surface arrives from above the window, so it is clipped to it: the part still up
        // in the menu bar must not be drawn over the bar it has not reached yet.
        let clip = NSView(frame: CGRect(origin: .zero, size: rect.size))
        clip.autoresizingMask = [.width, .height]
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(surface)
        cover.contentView = clip
        return cover
    }

    /// Hung off the surface's top corners, outside it, so they travel with it as it grows. Taken
    /// off again for a style without them, since the surface outlives each open.
    private func dressShoulders() {
        surface.subviews.filter { $0 is NotchShoulder }.forEach { $0.removeFromSuperview() }
        guard notch != nil else { return }
        let size = NotchShoulder.radius
        let top = surface.bounds.height - size
        let left = NotchShoulder(left: true)
        left.frame.origin = CGPoint(x: -size, y: top)
        left.autoresizingMask = [.maxXMargin, .minYMargin]
        let right = NotchShoulder(left: false)
        right.frame.origin = CGPoint(x: surface.bounds.width, y: top)
        right.autoresizingMask = [.minXMargin, .minYMargin]
        surface.addSubview(left)
        surface.addSubview(right)
    }
}

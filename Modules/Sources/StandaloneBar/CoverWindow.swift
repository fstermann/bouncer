import AppKit

/// Hides the replicated items by covering them, without moving them.
///
/// The items have to stay on the display: pushed off it they stop being drawn, and an item
/// that is not drawn cannot be photographed. Covering costs nothing by comparison — a window
/// capture ignores whatever is on top of it — so the section is revealed into its normal
/// place and this is drawn over it.
///
/// Painted in `BarSurface.colour`, the same as the shelf below, and only over the stretch the
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
    private var window: BarWindow?
    private let surface = NSView()

    public init() {
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
        surface.layer?.backgroundColor = BarSurface.colour.cgColor
    }

    /// The part that moves. Parked and run by the controller, with the shelf's, so the two
    /// halves of the panel cannot come apart.
    var panel: NSView { surface }

    /// Shows the cover over `rect`, in window-server coordinates.
    ///
    /// Sits one level above the status items so it hides them, and well below the pop-up
    /// menu level, so an item's menu still opens over the top when its replica is clicked.
    public func show(over rect: CGRect) {
        let cover = window ?? make(rect)
        window = cover
        cover.setFrame(cgFrame: rect)
        // Size only, so a cover tightened onto the section it has just hidden is not dragged
        // back to where its descent started.
        surface.setFrameSize(rect.size)
        cover.orderFrontRegardless()
    }

    private static let aboveItems = NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 1)

    /// Lifts the cover clear of its window, ready to be run back down into it.
    func park(by travel: CGFloat) {
        surface.setFrameOrigin(CGPoint(x: 0, y: travel))
    }

    /// Settles the cover onto the section it has just hidden.
    ///
    /// Where the section would land was worked out while it was still parked, and the answer
    /// is exact to the point unless an always-hidden section is holding items — so this is
    /// usually a move of nothing at all. Given time to do it in, whatever is left glides
    /// rather than jumping. Not awaited: nothing is waiting on it.
    func settle(onto rect: CGRect, over duration: TimeInterval?) {
        guard let window, let duration else { show(over: rect); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(BarWindow.appKitFrame(for: rect), display: true)
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
        surface.frame = CGRect(origin: .zero, size: rect.size)
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
}

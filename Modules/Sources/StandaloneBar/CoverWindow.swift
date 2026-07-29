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
@MainActor
public final class CoverWindow {
    private var window: BarWindow?
    private let surface = NSView()

    public init() {
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
        surface.layer?.backgroundColor = BarSurface.colour.cgColor
    }

    /// Shows the cover over `rect`, in window-server coordinates.
    ///
    /// Sits one level above the status items so it hides them, and well below the pop-up
    /// menu level, so an item's menu still opens over the top when its replica is clicked.
    public func show(over rect: CGRect) {
        let cover = window ?? make(rect)
        window = cover
        cover.setFrame(cgFrame: rect)
        cover.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func make(_ rect: CGRect) -> BarWindow {
        let cover = BarWindow(
            frame: rect,
            level: NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 1)
        )
        // Clicks belong to the items underneath, which are painted over rather than moved.
        // `ClickShield` is what stops one reaching an icon nobody can see.
        cover.ignoresMouseEvents = true
        surface.frame = CGRect(origin: .zero, size: rect.size)
        cover.contentView = surface
        return cover
    }
}

import AppKit

/// Hides the replicated items by covering them, without moving them.
///
/// The items have to stay on the display: pushed off it they stop being drawn, and an item
/// that is not drawn cannot be captured. Covering costs nothing by comparison — a window
/// capture ignores whatever is on top of it — so the section is revealed into its normal
/// place and this is drawn over it.
///
/// What it paints is the menu bar itself, captured with the items excluded. Nothing else
/// matches: the bar is translucent over whatever is behind it, so every material AppKit
/// offers reads as a patch, while the real background reproduces exactly, shadows and all.
@MainActor
public final class CoverWindow {
    private var window: BarWindow?
    private let imageView = NSImageView()

    public init() {
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
    }

    /// Shows the cover over `rect`, in window-server coordinates.
    ///
    /// Sits one level above the status items so it hides them, and well below the pop-up
    /// menu level, so an item's menu still opens over the top when its replica is clicked.
    public func show(over rect: CGRect) {
        let cover = window ?? make(rect)
        cover.setFrame(cgFrame: rect)
        cover.orderFrontRegardless()
        window = cover
    }

    /// Repaints with a fresh capture of the background.
    ///
    /// Called for every frame the background stream delivers: window shadows stack under
    /// the menu bar and shift whenever anything moves, and a cover painted once drifts
    /// visibly out of step within seconds.
    public func update(_ image: CGImage?) {
        guard let image, let window else {
            imageView.image = nil
            return
        }
        imageView.image = NSImage(cgImage: image, size: window.frame.size)
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
        imageView.image = nil
    }

    private func make(_ rect: CGRect) -> BarWindow {
        let cover = BarWindow(
            frame: rect,
            level: NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 1)
        )
        // Clicks on the covered strip belong to the real items underneath: the user is
        // meant to reach them through their replicas, and swallowing the clicks here would
        // make the menu bar feel broken where the section used to be.
        cover.ignoresMouseEvents = true
        cover.isOpaque = true
        imageView.frame = CGRect(origin: .zero, size: rect.size)
        cover.contentView = imageView
        return cover
    }
}

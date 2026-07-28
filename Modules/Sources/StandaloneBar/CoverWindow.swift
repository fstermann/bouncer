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
    /// The last capture and the stretch of bar it is a picture of, so the cover can be moved
    /// without stretching a picture of one rect across another.
    private var capture: (image: CGImage, of: CGRect)?
    /// Where the cover currently sits.
    private var rect: CGRect = .zero

    public init() {
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
    }

    /// The cover's own window, so the capture that paints it can leave it out.
    public var windowID: UInt32? { window.map { UInt32($0.windowNumber) } }

    /// Shows the cover over `rect`, in window-server coordinates.
    ///
    /// Sits one level above the status items so it hides them, and well below the pop-up
    /// menu level, so an item's menu still opens over the top when its replica is clicked.
    public func show(over rect: CGRect) {
        let cover = window ?? make(rect)
        window = cover
        self.rect = rect
        // Painted before it is resized. A window resized while it still holds the picture of
        // where it used to be stretches that picture across the new frame — the whole menu
        // bar squeezed into one section, for as long as it takes to repaint.
        repaint()
        cover.setFrame(cgFrame: rect)
        cover.orderFrontRegardless()
    }

    /// Repaints with a fresh capture of the background.
    ///
    /// Called for every frame the background stream delivers: window shadows stack under
    /// the menu bar and shift whenever anything moves, and a cover painted once drifts
    /// visibly out of step within seconds.
    /// - Parameter capturedRect: the stretch of bar `image` is a picture of. The cover is
    ///   moved while a capture of the whole bar is still up — that is how the section is kept
    ///   from flashing as it is revealed — and a picture of the bar squeezed into the width
    ///   of one section is worse than no cover at all.
    public func update(_ image: CGImage?, of capturedRect: CGRect) {
        // Nothing to paint with is not a reason to stop painting. The stream drops its image
        // whenever it restarts, and a cover cleared in that gap stops covering: the items it
        // is hiding show through until the next frame arrives, which is long enough to see.
        guard let image else { return }
        capture = (image, capturedRect)
        repaint()
    }

    /// Paints the part of the capture that belongs where the cover now sits.
    private func repaint() {
        guard let capture, window != nil, rect.width > 0 else { return }
        guard capture.of != rect else {
            imageView.image = NSImage(cgImage: capture.image, size: rect.size)
            return
        }

        // The capture is at backing-store resolution, so its pixels are a scaled copy of the
        // rect it came from.
        let scale = CGFloat(capture.image.width) / capture.of.width
        let visible = CGRect(
            x: (rect.minX - capture.of.minX) * scale,
            y: (rect.minY - capture.of.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        // A capture that does not reach where the cover now sits leaves the last painting
        // alone. Clearing would uncover the very items the cover exists to hide, and a
        // picture of the bar a few points out is nobody's idea of a flash.
        let bounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        guard bounds.contains(visible), let cropped = capture.image.cropping(to: visible) else {
            return
        }
        imageView.image = NSImage(cgImage: cropped, size: rect.size)
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

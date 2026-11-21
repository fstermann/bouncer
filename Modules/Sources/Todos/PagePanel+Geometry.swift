import AppKit
import BouncerFoundation
import MenuBar

extension PagePanel {
    /// The panel and its fillets, which are drawn beside it rather than in it, since the panel cuts
    /// its content to its own shape.
    func body(_ surface: NSView) -> [NSView] {
        [surface] + (surface.superview?.subviews.filter { $0 is NotchShoulder } ?? [])
    }

    func local(_ rect: CGRect, in window: NSWindow) -> CGRect {
        rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
    }

    func fadeIn(_ view: NSView, on motion: Motion) {
        view.alphaValue = 0
        motion.fade(view, to: 1)
    }
}

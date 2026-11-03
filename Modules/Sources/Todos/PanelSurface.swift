import AppKit
import MenuBar

/// Reports the pointer leaving the panel and coming back. Its tracking area follows its bounds,
/// which are the panel's resting size from the moment it opens.
final class SurfaceView: NSView {
    var onExit: (@MainActor () -> Void)?
    var onEnter: (@MainActor () -> Void)?

    /// Pins the content to the top centre. Autoresizing cannot: it splits the change between two
    /// flexible margins by their size, and both are zero at rest.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        for view in subviews {
            view.setFrameOrigin(CGPoint(x: (bounds.width - view.frame.width) / 2, y: bounds.height - view.frame.height))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `assumeInside`: it opens under the pointer, which never entered it.
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .assumeInside],
            owner: self
        ))
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }
}

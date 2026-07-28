import AppKit

/// The standalone bar: the hidden section's items, drawn one row below the menu bar.
///
/// Replicas keep their real horizontal positions rather than being packed together. That
/// looks less tidy and is not a choice: a status item anchors its menu to its own window,
/// and we cannot move the real item, so a packed bar would open a menu nowhere near the
/// replica that was clicked.
@MainActor
public final class ReplicaBar {
    /// Called when a replica is clicked, with the point on the real item to forward to.
    public var onClick: (@MainActor (MenuBarItem, CGPoint, Bool, CGEventFlags) -> Void)?

    private var window: BarWindow?
    private let view = ReplicaBarView()

    public init() {
        view.onClick = { [weak self] item, point, right, modifiers in
            self?.onClick?(item, point, right, modifiers)
        }
    }

    /// Shows the bar for `items`, directly below the menu bar band they came from.
    ///
    /// - Parameter menuBarFrame: the stretch of menu bar the items occupy, in
    ///   window-server coordinates. The bar hangs immediately underneath it.
    public func show(_ items: [MenuBarItem], below menuBarFrame: CGRect) {
        let (positions, size) = MenuBarItemGeometry.layout(items)
        guard size.width > 0 else { hide(); return }

        let frame = CGRect(
            x: menuBarFrame.minX,
            y: menuBarFrame.maxY,
            width: size.width,
            height: size.height
        )
        let bar = window ?? make(frame)
        bar.setFrame(cgFrame: frame)
        view.frame = CGRect(origin: .zero, size: size)
        view.positions = positions
        view.needsDisplay = true
        bar.orderFrontRegardless()
        window = bar
    }

    /// Hands over the latest captured frames, keyed by window ID.
    public func update(images: [UInt32: CGImage]) {
        view.images = images
        view.needsDisplay = true
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
        view.images = [:]
        view.positions = [:]
    }

    private func make(_ frame: CGRect) -> BarWindow {
        // Below the status level: the bar hangs under the menu bar and has no business
        // competing with the items themselves.
        let bar = BarWindow(frame: frame, level: .floating)
        bar.contentView = view
        return bar
    }
}

/// Draws the replicas and turns clicks on them back into points on the real items.
@MainActor
final class ReplicaBarView: NSView {
    var images: [UInt32: CGImage] = [:]
    var positions: [MenuBarItem: CGRect] = [:]
    var onClick: (@MainActor (MenuBarItem, CGPoint, Bool, CGEventFlags) -> Void)?

    /// Positions come from the window server, which measures downwards.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for (item, rect) in positions {
            guard let image = images[item.windowID] else { continue }
            // Drawn through NSImage rather than CGContext.draw: the context ignores the
            // view's flippedness and would render every replica upside down.
            NSImage(cgImage: image, size: rect.size).draw(in: rect)
        }
    }

    override func mouseDown(with event: NSEvent) { forward(event, rightButton: false) }
    override func rightMouseDown(with event: NSEvent) { forward(event, rightButton: true) }

    private func forward(_ event: NSEvent, rightButton: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        // A click in a gap belongs to nobody. Guessing at the nearest replica would open
        // the wrong item's menu, which is worse than doing nothing.
        guard let hit = MenuBarItemGeometry.itemHit(at: point, positions: positions) else { return }
        onClick?(hit.item, hit.pointOnItem, rightButton, event.modifierFlags.cgEventFlags)
    }
}

extension NSEvent.ModifierFlags {
    /// The subset that changes what a status item does when clicked.
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

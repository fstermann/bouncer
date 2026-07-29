import AppKit

/// The standalone bar: the hidden section's items, drawn one row below the menu bar.
///
/// Replicas keep their real horizontal positions rather than being packed together. That
/// looks less tidy and is not a choice: a status item anchors its menu to its own window,
/// and we cannot move the real item, so a packed bar would open a menu nowhere near the
/// replica that was clicked.
@MainActor
public final class ReplicaBar {
    /// Called when a replica is clicked, with the item it replicates.
    public var onClick: (@MainActor (MenuBarItem) -> Void)?

    /// The shelf is wider than the replicas it holds, so the outermost icons are not flush
    /// against a rounded corner. The cover over the real section uses the same figure, so the
    /// two line up rather than the shelf hanging out past what is hiding its items.
    static let padding: CGFloat = 8
    /// Only the lower corners are rounded: the shelf hangs off the menu bar, and a gap above
    /// it would show it is a window of its own rather than part of the bar.
    private static let cornerRadius: CGFloat = 10

    private var window: BarWindow?
    private var shelf: NSView?
    private let view = ReplicaBarView()

    public init() {
        view.onClick = { [weak self] item in
            self?.onClick?(item)
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
            x: menuBarFrame.minX - Self.padding,
            y: menuBarFrame.maxY,
            width: size.width + Self.padding * 2,
            height: size.height
        )
        let bar = window ?? make(frame)
        bar.setFrame(cgFrame: frame)
        view.frame = CGRect(origin: CGPoint(x: Self.padding, y: 0), size: size)
        view.positions = positions
        view.needsDisplay = true
        bar.orderFrontRegardless()
        window = bar
    }

    /// The shelf's own window, so a capture of the bar can leave it out.
    public var windowID: UInt32? { window.map { UInt32($0.windowNumber) } }

    /// The bar's lower edge, in AppKit screen coordinates: below it, the pointer has left.
    var bottomEdge: CGFloat { window?.frame.minY ?? 0 }

    /// Fades the bar while a menu is open over it.
    ///
    /// The menu comes out of the real item a row above and covers the replicas, which cannot
    /// be clicked through it. Dimming says so, rather than leaving a bar that looks live
    /// underneath.
    public func setDimmed(_ dimmed: Bool) {
        window?.alphaValue = dimmed ? 0.4 : 1
    }

    /// Hands over the latest captured frames, keyed by window ID.
    public func update(images: [UInt32: CGImage]) {
        view.images = images
        view.needsDisplay = true
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
        shelf = nil
        view.images = [:]
        view.positions = [:]
    }

    private func make(_ frame: CGRect) -> BarWindow {
        // Below the status level: the bar hangs under the menu bar and has no business
        // competing with the items themselves.
        let bar = BarWindow(frame: frame, level: .floating)
        // Replicas are icons on nothing, so the bar has to bring its own surface or they sit
        // unreadable on whatever window is behind.
        //
        // Painted in `BarSurface.colour`, the same as the cover over the real section, so the
        // two read as one panel rather than as a strip and a patch that nearly agree.
        let backing = NSView(frame: CGRect(origin: .zero, size: frame.size))
        backing.autoresizingMask = [.width, .height]
        backing.wantsLayer = true
        // A shelf hanging off the menu bar: square where it meets it, rounded where it ends.
        backing.layer?.cornerRadius = Self.cornerRadius
        backing.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        backing.layer?.masksToBounds = true
        backing.layer?.backgroundColor = BarSurface.colour.cgColor
        backing.addSubview(view)
        bar.contentView = backing
        shelf = backing
        return bar
    }
}

/// Draws the replicas and turns clicks on them back into points on the real items.
@MainActor
final class ReplicaBarView: NSView {
    var images: [UInt32: CGImage] = [:]
    var positions: [MenuBarItem: CGRect] = [:]
    var onClick: (@MainActor (MenuBarItem) -> Void)?

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

    // Both buttons open the item, because pressing it through accessibility is all the
    // gesture there is: the tree exposes one action, and no way to say which button asked.
    override func mouseDown(with event: NSEvent) { forward(event) }
    override func rightMouseDown(with event: NSEvent) { forward(event) }

    private func forward(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // A click in a gap belongs to nobody. Guessing at the nearest replica would open
        // the wrong item's menu, which is worse than doing nothing.
        guard let item = MenuBarItemGeometry.item(at: point, positions: positions) else { return }
        onClick?(item)
    }
}

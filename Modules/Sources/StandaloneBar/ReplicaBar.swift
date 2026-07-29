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
    /// The window reaches up over that band as well, although the shelf only ever rests below
    /// it: the replicas slide down through the menu bar to get here, and a window that stopped
    /// at the bar's lower edge would have them wipe into existence there instead of arriving.
    ///
    /// - Parameter menuBarFrame: the stretch of menu bar the items occupy, in
    ///   window-server coordinates. The bar hangs immediately underneath it.
    public func show(_ items: [MenuBarItem], below menuBarFrame: CGRect) {
        let (positions, size) = MenuBarItemGeometry.layout(items)
        guard size.width > 0 else { takeDown(); return }

        let frame = CGRect(
            x: menuBarFrame.minX - Self.padding,
            y: menuBarFrame.minY,
            width: size.width + Self.padding * 2,
            height: menuBarFrame.height + size.height
        )
        let bar = window ?? make(frame, shelfHeight: size.height)
        bar.setFrame(cgFrame: frame)
        // Size only: a later show follows the items sideways and must not drag the shelf back
        // to where a descent that is still running started it.
        shelf?.setFrameSize(CGSize(width: frame.width, height: size.height))
        view.frame = CGRect(origin: CGPoint(x: Self.padding, y: 0), size: size)
        view.positions = positions
        bar.orderFrontRegardless()
        window = bar
    }

    /// The part that moves, and how far it has to move: from above the menu bar down to the
    /// shelf's own place. The cover's half of the panel is run the same distance.
    var panel: NSView? { shelf }
    var travel: CGFloat { window?.frame.height ?? 0 }

    /// Lifts the shelf clear of the menu bar, ready to be run back down out of it.
    func park(by travel: CGFloat) {
        shelf?.setFrameOrigin(CGPoint(x: 0, y: travel))
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
    }

    public func hide() {
        takeDown()
    }

    private func takeDown() {
        window?.orderOut(nil)
        window = nil
        shelf = nil
        view.images = [:]
        view.positions = [:]
    }

    private func make(_ frame: CGRect, shelfHeight: CGFloat) -> BarWindow {
        // Above the cover, which is itself above the items: the replicas cross the menu bar on
        // their way down, and behind the cover they would be crossing it unseen. The window
        // only draws where the shelf is, and a fully transparent stretch is click-through, so
        // the band it reaches over stays the shield's to swallow.
        let bar = BarWindow(
            frame: frame,
            level: NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 3)
        )
        // Replicas are icons on nothing, so the bar has to bring its own surface or they sit
        // unreadable on whatever window is behind.
        //
        // Painted in `BarSurface.colour`, the same as the cover over the real section, so the
        // two read as one panel rather than as a strip and a patch that nearly agree.
        // The shelf comes down from above the window, so it is clipped to it: while it is up
        // there it must not be drawn over the screen it has not reached yet.
        let clip = NSView(frame: CGRect(origin: .zero, size: frame.size))
        clip.autoresizingMask = [.width, .height]
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true

        // At the bottom of the window, which is the only part of it the shelf ever rests in.
        let backing = NSView(frame: CGRect(x: 0, y: 0, width: frame.width, height: shelfHeight))
        backing.wantsLayer = true
        // A shelf hanging off the menu bar: square where it meets it, rounded where it ends.
        backing.layer?.cornerRadius = Self.cornerRadius
        backing.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        backing.layer?.masksToBounds = true
        backing.layer?.backgroundColor = BarSurface.colour.cgColor
        view.wantsLayer = true
        backing.addSubview(view)
        clip.addSubview(backing)
        bar.contentView = clip
        shelf = backing
        return bar
    }
}

/// Holds the replicas and turns clicks on them back into points on the real items.
///
/// A replica is a layer with a picture in it rather than something drawn in `draw(_:)`. The
/// shelf slides, and AppKit stops re-rendering a view's drawn content once its layer is being
/// animated — the replicas emptied out of a shelf that kept its own background, which is a
/// layer property, all the way up. A picture that is also a layer property cannot come apart
/// from the shelf it is on.
@MainActor
final class ReplicaBarView: NSView {
    var images: [UInt32: CGImage] = [:] { didSet { rebuild() } }
    var positions: [MenuBarItem: CGRect] = [:] { didSet { rebuild() } }
    var onClick: (@MainActor (MenuBarItem) -> Void)?

    /// Positions come from the window server, which measures downwards.
    override var isFlipped: Bool { true }

    private func rebuild() {
        wantsLayer = true
        // Flipped to match the view, so a replica's layer sits where the item's frame says and
        // its picture is the right way up.
        layer?.isGeometryFlipped = true
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        for (item, rect) in positions {
            guard let image = images[item.windowID] else { continue }
            let replica = CALayer()
            replica.frame = rect
            replica.contents = image
            replica.contentsGravity = .resizeAspect
            layer?.addSublayer(replica)
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

import AppKit
import Settings

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
    /// Called when a replica is Cmd-pressed, with the item it stands for: the drag is to be
    /// handed over to that item in the real menu bar.
    public var onHandoff: (@MainActor (MenuBarItem) -> Void)?

    /// The shelf is wider than the replicas it holds, so the outermost icons are not flush
    /// against a rounded corner. The cover over the real section uses the same figure, so the
    /// two line up rather than the shelf hanging out past what is hiding its items.
    static let padding: CGFloat = 8
    /// Only the lower corners are rounded: the shelf hangs off the menu bar, and a gap above
    /// it would show it is a window of its own rather than part of the bar.
    private static let cornerRadius: CGFloat = 10

    /// How the shelf is painted. Set by the controller before each open, so the shelf leaves
    /// the way it arrived even if the preference changes while it is out.
    var style: BarStyle = .automatic
    /// The dimming layer over the shelf's glass, faded through `BarSurface.fade` together
    /// with the cover's, so the dim never shows as a step at the seam between them. The
    /// replicas sit above it: they slide in plain view, only their background dims.
    private(set) var veil: NSView?

    private var window: BarWindow?
    private var shelf: NSView?
    private let view = ReplicaBarView()

    public init() {
        view.onClick = { [weak self] item in
            self?.onClick?(item)
        }
        view.onHandoff = { [weak self] item in self?.onHandoff?(item) }
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

        // As wide as the stretch of bar it hangs under, not as wide as the replicas on it. The two
        // are the same at rest. Mid-drag they are not: the strip reaches to the divider, over the
        // hole macOS has opened for the item in hand, and the shelf has to reach with it or it
        // keeps its old width for the whole drag and jumps on the drop.
        let frame = CGRect(
            x: menuBarFrame.minX - Self.padding,
            y: menuBarFrame.minY,
            width: menuBarFrame.width + Self.padding * 2,
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
    ///
    /// No shelf reads as *everywhere* is below it, because a pointer cannot be inside a bar that
    /// is not there. Zero would read as nowhere: the watch asks whether the pointer is below this
    /// edge, and nothing is below zero — so a shelf that took itself down over an emptied section
    /// left a bar nothing could ever close.
    var bottomEdge: CGFloat { window?.frame.minY ?? .infinity }

    /// Fades the bar while a menu is open over it.
    ///
    /// The menu comes out of the real item a row above and covers the replicas, which cannot
    /// be clicked through it. Dimming says so, rather than leaving a bar that looks live
    /// underneath.
    public func setDimmed(_ dimmed: Bool) {
        window?.alphaValue = dimmed ? 0.4 : 1
    }

    /// The item the user has picked up, whose replica is not drawn while they hold it.
    public func setInHand(_ windowID: UInt32?) {
        view.inHand = windowID
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
        veil = nil
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
        // Dressed by `BarSurface`, the same as the cover over the real section, so the
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
        veil = BarSurface.dress(backing, in: style, coveringIcons: false)
        view.wantsLayer = true
        backing.addSubview(view)
        clip.addSubview(backing)
        bar.contentView = clip
        shelf = backing
        return bar
    }
}

/// Holds the replicas and turns a press on one into either a click or a handoff.
///
/// A replica is a layer with a picture in it rather than something drawn in `draw(_:)`. The
/// shelf slides, and AppKit stops re-rendering a view's drawn content once its layer is being
/// animated — the replicas emptied out of a shelf that kept its own background, which is a layer
/// property, all the way up. A picture that is also a layer property cannot come apart from the
/// shelf it is on.
///
/// Nothing here draws a drag, and nothing here ends one. A Cmd-press hands the gesture to the
/// real item a row above, and what the user then sees is the menu bar rearranging itself — the
/// genuine article rather than an imitation drawn on a shelf. The release is watched for globally
/// instead of waited for here: the pointer is warped out of this window as the gesture begins and
/// the window server takes the drag over, so a mouse-up finding its way back to the view that
/// started it is something to hope for, not to depend on.
@MainActor
final class ReplicaBarView: NSView {
    var images: [UInt32: CGImage] = [:] { didSet { rebuild() } }
    var positions: [MenuBarItem: CGRect] = [:] { didSet { rebuild() } }
    /// Drawn nowhere while the user is holding the real thing.
    var inHand: UInt32? { didSet { rebuild() } }
    var onClick: (@MainActor (MenuBarItem) -> Void)?
    var onHandoff: (@MainActor (MenuBarItem) -> Void)?

    /// Positions come from the window server, which measures downwards.
    override var isFlipped: Bool { true }

    /// The layers, kept between rebuilds rather than replaced.
    ///
    /// While the user is rearranging the bar this runs on every frame, and a replica torn down
    /// and built again each time flickers. Kept, it is a frame assignment — and one made with
    /// animation switched off, because the shelf is following something that has already moved
    /// rather than deciding to move itself.
    private var replicas: [UInt32: CALayer] = [:]

    private func rebuild() {
        wantsLayer = true
        // Flipped to match the view, so a replica's layer sits where the item's frame says and
        // its picture is the right way up.
        layer?.isGeometryFlipped = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var drawn: Set<UInt32> = []
        for (item, rect) in positions where item.windowID != inHand {
            guard let image = images[item.windowID] else { continue }
            drawn.insert(item.windowID)
            let replica = replicas[item.windowID] ?? CALayer()
            if replica.superlayer == nil {
                replica.contentsGravity = .resizeAspect
                layer?.addSublayer(replica)
                replicas[item.windowID] = replica
            }
            replica.contents = image
            replica.frame = rect
        }
        for (id, replica) in replicas where !drawn.contains(id) {
            replica.removeFromSuperlayer()
            replicas[id] = nil
        }
        CATransaction.commit()
    }

    // Both buttons open the item, because pressing it through accessibility is all the gesture
    // there is: the tree exposes one action, and no way to say which button asked.
    //
    // Cmd is what tells a rearrangement from a click, exactly as it does in the menu bar, and for
    // the same reason: without it every drag would also open a menu.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard event.modifierFlags.contains(.command) else { forward(point); return }
        guard let item = MenuBarItemGeometry.item(at: point, positions: positions) else { return }
        onHandoff?(item)
    }

    /// Deliberately empty. The window server has the drag now and is following the pointer for
    /// itself; anything drawn here would be a second, disagreeing answer to where the item is.
    override func mouseDragged(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {
        forward(convert(event.locationInWindow, from: nil))
    }

    private func forward(_ point: CGPoint) {
        // A click in a gap belongs to nobody. Guessing at the nearest replica would open
        // the wrong item's menu, which is worse than doing nothing.
        guard let item = MenuBarItemGeometry.item(at: point, positions: positions) else { return }
        onClick?(item)
    }
}

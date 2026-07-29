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
    /// against a rounded corner.
    private static let padding: CGFloat = 8
    /// Only the lower corners are rounded: the shelf hangs off the menu bar, and a gap above
    /// it would show it is a window of its own rather than part of the bar.
    private static let cornerRadius: CGFloat = 10

    private var window: BarWindow?
    private var shelf: NSView?
    /// Kept so a shade taken before the shelf exists is not lost: the colour is sampled from
    /// a capture of the menu bar, which is ready before there is anything to paint with it.
    private var shade: CGColor?
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

    /// Takes the shelf's colour from a capture of the menu bar.
    ///
    /// One colour for the whole shelf, averaged: the bar is translucent and so shades across
    /// its width, but a shelf that shaded differently from the bar directly above it would
    /// look like a mismatch rather than a continuation.
    public func matchShade(to menuBar: CGImage?) {
        guard let menuBar, let colour = Self.averageColour(of: menuBar) else { return }
        shade = colour
        shelf?.layer?.backgroundColor = colour
    }

    /// How many samples the strip is reduced to before the middle one is taken.
    private static let samples = 15

    private static func averageColour(of image: CGImage) -> CGColor? {
        // Only the bottom of the strip: the shelf meets the menu bar along that edge, and it
        // is the join that gives a mismatch away. The bar is not one flat colour from top to
        // bottom, so matching its middle leaves a seam.
        //
        // The middle sample of many rather than the average of all. Anything sitting in the
        // strip is averaged into the result otherwise, and the screen recording indicator —
        // which capturing puts there — is bright purple, enough to tint the whole shelf.
        //
        // Sampled in the capture's own colour space and handed back in it. Going through a
        // device space instead lands a visibly different shade next to the bar it continues.
        let depth = max(1, image.height / 8)
        let lowest = image.cropping(
            to: CGRect(x: 0, y: image.height - depth, width: image.width, height: depth)
        ) ?? image
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: samples * 4)
        guard let context = CGContext(
            data: &pixels,
            width: samples, height: 1,
            bitsPerComponent: 8, bytesPerRow: samples * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(lowest, in: CGRect(x: 0, y: 0, width: samples, height: 1))

        var colours: [[CGFloat]] = []
        for sample in 0..<samples {
            let start = sample * 4
            colours.append([
                CGFloat(pixels[start]) / 255,
                CGFloat(pixels[start + 1]) / 255,
                CGFloat(pixels[start + 2]) / 255
            ])
        }
        colours.sort { ($0[0] + $0[1] + $0[2]) < ($1[0] + $1[1] + $1[2]) }
        return CGColor(colorSpace: space, components: colours[samples / 2] + [1])
    }

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
        // Painted with the menu bar's own colour rather than given a material. A material
        // cannot match it: the menu bar is translucent over the desktop, while the shelf
        // hangs over whatever window happens to be beneath it, so the same recipe comes out
        // a different shade. `matchShade` fills it from the capture that feeds the cover.
        let backing = NSView(frame: CGRect(origin: .zero, size: frame.size))
        backing.autoresizingMask = [.width, .height]
        backing.wantsLayer = true
        // A shelf hanging off the menu bar: square where it meets it, rounded where it ends.
        backing.layer?.cornerRadius = Self.cornerRadius
        backing.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        backing.layer?.masksToBounds = true
        // Whatever shade has been measured so far, applied before the shelf is ever drawn.
        // A shelf that appears before its background does is a row of icons floating over
        // whatever window is behind it.
        backing.layer?.backgroundColor = shade
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

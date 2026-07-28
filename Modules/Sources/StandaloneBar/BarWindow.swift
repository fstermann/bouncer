import AppKit

/// A borderless window that can sit in the menu bar band.
///
/// Two things AppKit does by default make that impossible, and both are fixed here rather
/// than at each call site. It constrains windows out of the menu bar area — which silently
/// drops a window 33 pt lower than asked, the kind of bug that looks like a coordinate
/// mistake. And it works in bottom-left coordinates while every frame in this module comes
/// from the window server in top-left ones.
@MainActor
class BarWindow: NSWindow {
    /// Status items sit at this level. A cover has to beat it; a replica bar sits below the
    /// menu bar and does not, but both need the same coordinate handling.
    static var statusLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
    }

    /// - Parameter frame: in Core Graphics coordinates — top-left origin, as reported by
    ///   the window server.
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(
            contentRect: Self.appKitFrame(for: frame),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // The bar belongs to no space in particular and must not be cycled to.
        // Auxiliary rather than none: a window that does not participate in full screen is
        // kept out of a full screen space altogether, which leaves the section revealed and
        // uncovered there.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    /// AppKit would otherwise push the window out of the menu bar band.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Moves the window, in Core Graphics coordinates.
    func setFrame(cgFrame: CGRect) {
        setFrame(Self.appKitFrame(for: cgFrame), display: true)
    }

    /// Flips a window-server rect into AppKit's coordinate space.
    ///
    /// Anchored on the screen that contains the rect rather than `NSScreen.main`, which is
    /// the screen with keyboard focus and is not necessarily the one being drawn on.
    static func appKitFrame(for frame: CGRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(flippedProbe(for: frame)) }
            ?? NSScreen.main
        let height = screen?.frame.maxY ?? frame.maxY
        return NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// A rect can only be matched to a screen horizontally here: its y is still in the
    /// other coordinate space, so comparing it vertically would be meaningless.
    private static func flippedProbe(for frame: CGRect) -> CGRect {
        CGRect(x: frame.midX, y: 0, width: 1, height: 1)
    }
}

import AppKit

/// Sends a click to the real status item behind a replica.
///
/// The item is on screen the whole time — under the cover, at the coordinates the window
/// server reports — so this is an ordinary synthesised click at a known point rather than
/// anything clever.
///
/// It needs Accessibility. Without it every posted event is dropped silently, with no error
/// and no indication which is why `isPermitted` exists: the failure is otherwise invisible
/// and reads to the user as a replica that simply does nothing.
public enum ClickForwarder {
    /// Whether synthesised clicks will be delivered at all.
    public static var isPermitted: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility, showing the system prompt.
    ///
    /// Only ever call this in response to the user turning click forwarding on. Bouncer
    /// asks for no permissions by default, and this is the second one.
    @discardableResult
    public static func requestPermission() -> Bool {
        // The constant is exported as a mutable global, which Swift 6 will not read across
        // isolation; its value is fixed and documented.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Clicks `point`, in window-server coordinates.
    ///
    /// Posted to the session tap, which delivers; posting to the owning process does not
    /// work, because status items are hosted by Control Center rather than by the app the
    /// item belongs to.
    public static func click(
        at point: CGPoint,
        rightButton: Bool = false,
        modifiers: CGEventFlags = []
    ) {
        let button: CGMouseButton = rightButton ? .right : .left
        let downType: CGEventType = rightButton ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightButton ? .rightMouseUp : .leftMouseUp

        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                                 mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                               mouseCursorPosition: point, mouseButton: button)
        else { return }

        // A posted mouse event carries the position the window server hit-tests, so the
        // pointer is dragged to the real item whether we like it or not. Put it back where
        // the user left it: they clicked a replica a row below, and having the pointer jump
        // into the menu bar reads as the click having gone somewhere else.
        let origin = CGEvent(source: nil)?.location

        // Carried through so Option-click and right-click reach the item as themselves —
        // several items show a different menu for each.
        down.flags = modifiers
        up.flags = modifiers
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)

        // Warping generates no event, so the menu that just opened does not see a move and
        // stays put; only the drawn pointer returns.
        if let origin { CGWarpMouseCursorPosition(origin) }
    }
}

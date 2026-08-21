import AppKit
import CoreGraphics

/// Hands a drag that started on a replica over to the real item, and to the user's own hand.
///
/// The whole gesture used to be synthesised: press, move and release, reconstructed after the
/// fact from where the shelf said the item should end up. That needed timings, retries, a
/// verification pass and a bounded settle, because a reconstruction can be wrong in ways a real
/// gesture cannot. It also warped the pointer, which is what made it feel wrong.
///
/// Only the *press* has to be synthesised. Measured: a Cmd+mouse-down posted at a status item
/// starts a drag that then tracks the user's own pointer, and the user's own release finishes
/// it. So one event is posted, and from there the menu bar is doing what it does for anybody —
/// including the part no reconstruction could offer, which is dragging an item clear of the
/// section altogether.
///
/// The press does not move the pointer: it is routed to the item by its window ID, wherever the
/// pointer is, so the grab costs no flick and the pointer stays in the user's hand down in the
/// shelf. The window server tracks it there and the item follows — so what the user drags is the
/// real item, in Bouncer's own bar.
///
/// Cmd has to stay held, because the menu bar reads the modifier on every move rather than only
/// at the press. That costs nothing, since Cmd is what began the gesture.
@MainActor
enum ItemHandoff {
    /// Grabs the item, without moving the pointer onto it.
    ///
    /// The item is checked to still be in the bar here rather than trusted from the caller: the bar
    /// moves for reasons that have nothing to do with the user, and an item can be gone by the time
    /// the gesture reaches this. Costs one scan.
    ///
    /// Every item is grabbed the same way, and deliberately: the down is routed to it by its
    /// windowID, wherever the pointer is, so the pointer never leaves the user's hand and never
    /// flicks. The window server grabs the item by its corner rather than by a point under the
    /// pointer — there is none — which is the one grab it can give an item with no pixel drawn at
    /// all, the item behind the notch. Grabbing everything that way keeps the gesture consistent
    /// rather than centring most items and cornering the few the notch hides. This is also a hop out
    /// of AppKit's own mouse-down dispatch, which is what is running when the gesture starts.
    ///
    /// - Parameter ready: anything that has to be out of the press's way, awaited before the press.
    static func begin(on item: UInt32, once ready: @MainActor () async -> Void) async -> Bool {
        guard StatusItemScanner.scan().contains(where: { $0.windowID == item }) else {
            return false
        }
        await ready()
        picked = item

        // A Cmd-press can be let go before this runs. Pressing then starts a drag with no release
        // coming, and the item rides the pointer until the next click.
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return false }
        // Posted where the pointer already is, so the post does not move it; the windowID lands the
        // press on the item.
        let hand = CGEvent(source: nil)?.location ?? .zero
        post(.leftMouseDown, at: hand, forWindow: item)
        return true
    }

    /// The stretch of the menu bar the notch takes up on the display `frame` is on, if it has
    /// one. The two auxiliary areas are the bar either side of it, so the gap between them is it.
    static func notch(under frame: CGRect) -> ClosedRange<CGFloat>? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.minX...$0.frame.maxX ~= frame.midX }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.maxX < right.minX
        else { return nil }
        return left.maxX...right.minX
    }

    /// One frame, so a drag is taken before the release that lands on it is posted.
    private static let beatBeforeReleasing: Duration = .milliseconds(16)

    /// Lands the item where the user let go.
    ///
    /// Routed to the item by its window ID at the pointer's own position — no warp up to the bar
    /// and back, so no cursor trip on the drop. The user's own release has already landed the item
    /// on the bar (the windowID grab is not abandoned below the bar the way a warp-grab was); this
    /// release only settles it, which was measured landing more cleanly than leaving it to theirs
    /// alone.
    ///
    /// - Parameter carryingBack: whether the item belongs in the bar at all. False when the user
    ///   has pulled it below the panel, which is the system's own gesture for taking an item off
    ///   the menu bar — their release has already landed that, and there is nothing here to add.
    ///   Bringing it home would be undoing what they asked for.
    static func end(carryingBack: Bool) async {
        guard carryingBack else { return }
        let hand = CGEvent(source: nil)?.location ?? .zero
        // Landed by windowID where the pointer already is, so the pointer is not warped up to the
        // bar and back — no cursor trip on the drop. The release also settles the item more cleanly
        // than leaving it to the user's own release alone, which was measured jumping more often.
        post(.leftMouseDragged, at: hand, forWindow: picked)
        try? await Task.sleep(for: beatBeforeReleasing)
        post(.leftMouseUp, at: hand, forWindow: picked)
    }

    /// The item picked up, remembered so `end` can route its release to the same window.
    private static var picked: UInt32?

    private static func post(_ type: CGEventType, at point: CGPoint, forWindow windowID: UInt32? = nil) {
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type, mouseCursorPosition: point, mouseButton: .left
        ) else { return }
        event.flags = .maskCommand
        // The private field that routes a press to a specific status-item window regardless of the
        // event's cursor location — the only way to grab an item with no pixel under the pointer.
        if let windowID, let field = CGEventField(rawValue: 0x33) {
            event.setIntegerValueField(field, value: Int64(windowID))
        }
        event.post(tap: .cghidEventTap)
    }
}

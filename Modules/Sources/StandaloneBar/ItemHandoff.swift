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
/// it. So the pointer is put on the item, one event is posted, and from there the menu bar is
/// doing what it does for anybody — including the part no reconstruction could offer, which is
/// dragging an item clear of the section altogether.
///
/// The pointer goes up to the item, presses it, and comes straight back to the user's hand. Only
/// the grab happens in the menu bar; the dragging happens wherever the user's pointer already
/// was, which is the shelf. The window server carries on tracking the pointer down there, and the
/// item follows — so what the user drags is the real item, in Bouncer's own bar.
///
/// Cmd has to stay held, because the menu bar reads the modifier on every move rather than only
/// at the press. That costs nothing, since Cmd is what began the gesture.
@MainActor
enum ItemHandoff {
    /// Puts the pointer on the item and presses it.
    ///
    /// The frame is read here rather than taken from the caller. A press is aimed at a point, so
    /// it is only as good as the frame it is aimed with, and the bar moves for reasons that have
    /// nothing to do with the user — anything that changes a divider's width shifts every item to
    /// its left. Reading it at the last moment costs one scan.
    ///
    /// The two are a beat apart, and have to be. A warp is a request to the window server like
    /// any other, so a press posted in the same breath is judged against wherever the pointer
    /// still was — which is a row below, in the shelf, where there is no item to pick up. This is
    /// also a hop out of AppKit's own mouse-down dispatch, which is what is running when the
    /// gesture starts.
    ///
    /// The first beat is a condition rather than a duration, because the pointer is off the user's
    /// hand for the whole of this and a beat generous enough to be safe is long enough to feel. It
    /// waits for the thing it was standing in for and no longer, capped at the old fixed wait — so
    /// the worst case is what it always was and the usual case is a fraction of it. The second is
    /// still a duration, for want of a condition that is not a lie about it.
    ///
    /// - Parameter ready: anything that has to be out of the press's way, awaited before the
    ///   pointer leaves the user's hand rather than while it is away. Whatever it waits for is a
    ///   beat the user cannot see; a beat spent with the pointer up in the bar is one they can.
    static func begin(on item: UInt32, once ready: @MainActor () async -> Void) async -> Bool {
        guard let frame = StatusItemScanner.scan().first(where: { $0.windowID == item })?.frame else {
            return false
        }
        await ready()
        // Where the user has their pointer, to be given back to them the moment the item is in
        // hand. Read before the warp, or it is the item's own position.
        let hand = CGEvent(source: nil)?.location ?? .zero
        row = frame.midY
        picked = item

        let notch = notch(under: frame)
        // An item entirely behind the notch has no pixel to press: there is no bar drawn there,
        // so no warp can put the pointer on it. Stamp the down with the item's windowID instead,
        // which routes the press to that status-item window regardless of the cursor's location,
        // and let the user's own physical drag carry it out from under the notch.
        guard MenuBarItemGeometry.isGrabbable(in: frame, clearOf: notch) else {
            guard NSEvent.pressedMouseButtons & 1 == 1 else { return false }
            post(.leftMouseDown, at: hand, forWindow: item)
            return true
        }

        let grip = MenuBarItemGeometry.gripPoint(in: frame, clearOf: notch)
        CGWarpMouseCursorPosition(grip)
        await pointerArrives(at: grip)
        // A Cmd-click short enough is over before the pointer gets here. Pressing anyway starts
        // a drag with no release coming, and the item rides the pointer until the next click.
        guard NSEvent.pressedMouseButtons & 1 == 1 else {
            CGWarpMouseCursorPosition(hand)
            return false
        }
        post(.leftMouseDown, at: grip)
        // A duration, not a condition, because the obvious condition is a lie. An item in hand
        // stays on the status item layer and rides down out of the bar with the pointer, so the
        // scanner stops reporting it — it filters on `minY == 0`. "The scanner cannot see it" is
        // the pointer having left the bar, which is this warp's own doing, not the press landing.
        try? await Task.sleep(for: beatBeforeReturning)
        CGWarpMouseCursorPosition(hand)
        return true
    }

    /// Waits for the pointer to be where it was sent.
    ///
    /// The exact condition the beat after a warp was standing in for, and the window server will
    /// answer it for the cost of reading an event's location. A warp lands in a few milliseconds;
    /// waiting out a beat sized for the worst case spends the rest of it with the user's pointer
    /// somewhere they did not put it.
    /// Asked before it ever sleeps: the whole point is not to wait for something that has already
    /// happened. A pointer that cannot be read counts as arrived, since there is nothing better to
    /// wait for and the cap is what the fixed beat used to cost anyway.
    private static func pointerArrives(at point: CGPoint) async {
        let deadline = ContinuousClock.now + beatAfterWarping
        while let here = CGEvent(source: nil)?.location,
              abs(here.x - point.x) >= 1 || abs(here.y - point.y) >= 1 {
            guard ContinuousClock.now < deadline else { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
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

    /// Measured in the spike that established the handoff: it warped, waited this long, pressed,
    /// and the item came away in the user's hand. The first is now a cap rather than a wait, so a
    /// condition that never comes true costs exactly what the fixed beat used to.
    private static let beatAfterWarping: Duration = .milliseconds(50)
    private static let beatBeforeReturning: Duration = .milliseconds(50)
    /// One frame, so a drag is taken before the release that lands on it is posted.
    private static let beatBeforeReleasing: Duration = .milliseconds(16)

    /// Takes the pointer back up to the bar, releases there, and hands it back.
    ///
    /// The mirror of `begin`, for the same reason and with the same beats. A release is judged
    /// against where the pointer *is*, not where the event says it is — so posting one at the bar
    /// while the pointer is still down in the shelf leaves the drag live, and the item stays in
    /// hand until some later click ends it.
    ///
    /// The x is the user's, because it is what says where the item lands. The y is not: they let
    /// go in the shelf, and a status item released below the bar has its move abandoned — it goes
    /// back where it came from, which reads as a drag that did nothing.
    ///
    /// Their own release has already been delivered by the time this runs, and landed nothing for
    /// exactly that reason. This is the one that lands it.
    ///
    /// - Parameter carryingBack: whether the item belongs in the bar at all. False when the user
    ///   has pulled it below the panel, which is the system's own gesture for taking an item off
    ///   the menu bar — their release has already landed that, and there is nothing here to add.
    ///   Bringing it home would be undoing what they asked for.
    static func end(carryingBack: Bool) async {
        guard carryingBack else { return }
        let hand = CGEvent(source: nil)?.location ?? .zero
        let drop = CGPoint(x: hand.x, y: row)

        // Carried back into the bar by an *event*, not by moving the pointer. A warp moves the
        // cursor and tells nobody; a drag in flight is following the events it is sent, which is
        // why the user's own movement carries the item and a warp does not. Without this the drag
        // still believes it is down in the shelf, and a release there is a move abandoned.
        CGWarpMouseCursorPosition(drop)
        // Stamped with the item's windowID so the drag and the release reach it even when `drop` is
        // under the notch, where there is no pixel for an unstamped event to land on — the mirror of
        // how `begin` grabs a notch-occluded item.
        post(.leftMouseDragged, at: drop, forWindow: picked)
        await pointerArrives(at: drop)
        // The rest of the old beat here was waiting on the warp, which is asked about directly now.
        try? await Task.sleep(for: beatBeforeReleasing)
        post(.leftMouseUp, at: drop, forWindow: picked)
        // No condition to ask here: the item comes back to the bar over an animation, and the
        // pointer is wanted back long before that. The user has already let go by now.
        try? await Task.sleep(for: beatBeforeReturning)
        CGWarpMouseCursorPosition(hand)
    }

    /// The menu bar's own row, remembered from the item that was picked up.
    private static var row: CGFloat = 12
    /// The item picked up, remembered so `end` can stamp its release with the same windowID and
    /// land it under the notch, where there is no pixel to release on.
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

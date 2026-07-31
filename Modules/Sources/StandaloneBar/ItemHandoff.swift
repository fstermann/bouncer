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
    static func begin(on item: UInt32) async -> Bool {
        guard let frame = StatusItemScanner.scan().first(where: { $0.windowID == item })?.frame else {
            return false
        }
        // Where the user has their pointer, to be given back to them the moment the item is in
        // hand. Read before the warp, or it is the item's own position.
        let hand = CGEvent(source: nil)?.location ?? .zero
        row = frame.midY

        CGWarpMouseCursorPosition(gripPoint(in: frame))
        try? await Task.sleep(for: .milliseconds(beatAfterWarping))
        post(.leftMouseDown, at: gripPoint(in: frame))
        try? await Task.sleep(for: .milliseconds(beatBeforeReturning))
        CGWarpMouseCursorPosition(hand)
        return true
    }

    /// Where in the item to take hold of it.
    ///
    /// Its middle, unless its middle is behind the notch — there is no bar drawn there and
    /// nothing to press, so an item spanning it has to be taken by whichever side has more of it.
    private static func gripPoint(in frame: CGRect) -> CGPoint {
        guard let notch = notch(under: frame), notch.contains(frame.midX) else {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        let toTheLeft = notch.lowerBound - frame.minX
        let toTheRight = frame.maxX - notch.upperBound
        let grip = toTheLeft >= toTheRight
            ? frame.minX + toTheLeft / 2
            : frame.maxX - toTheRight / 2
        return CGPoint(x: grip, y: frame.midY)
    }

    /// The stretch of the menu bar the notch takes up on the display `frame` is on, if it has
    /// one. The two auxiliary areas are the bar either side of it, so the gap between them is it.
    private static func notch(under frame: CGRect) -> ClosedRange<CGFloat>? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.minX...$0.frame.maxX ~= frame.midX }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.maxX < right.minX
        else { return nil }
        return left.maxX...right.minX
    }

    /// Measured in the spike that established the handoff: it warped, waited this long, pressed,
    /// and the item came away in the user's hand. The second beat is the same wait on the way
    /// back — long enough for the press to have been taken, short enough to read as one movement.
    private static let beatAfterWarping = 50
    private static let beatBeforeReturning = 50

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
    static func end() async {
        let hand = CGEvent(source: nil)?.location ?? .zero
        let drop = CGPoint(x: hand.x, y: row)

        // Carried back into the bar by an *event*, not by moving the pointer. A warp moves the
        // cursor and tells nobody; a drag in flight is following the events it is sent, which is
        // why the user's own movement carries the item and a warp does not. Without this the drag
        // still believes it is down in the shelf, and a release there is a move abandoned.
        CGWarpMouseCursorPosition(drop)
        post(.leftMouseDragged, at: drop)
        try? await Task.sleep(for: .milliseconds(beatAfterWarping))
        post(.leftMouseUp, at: drop)
        try? await Task.sleep(for: .milliseconds(beatBeforeReturning))
        CGWarpMouseCursorPosition(hand)
    }

    /// The menu bar's own row, remembered from the item that was picked up.
    private static var row: CGFloat = 12

    private static func post(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type, mouseCursorPosition: point, mouseButton: .left
        ) else { return }
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
    }
}

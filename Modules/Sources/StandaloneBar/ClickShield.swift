import AppKit

/// Swallows clicks on the stretch of bar the section was revealed into.
///
/// The items are not moved to hide them, only painted over, so they stay exactly as
/// clickable as they were. Without this, a click where one of them used to sit opens its menu
/// out of what reads as empty menu bar — the item invisible, its menu not.
///
/// The cover cannot do this itself. It spans the whole bar, so a cover that took clicks would
/// swallow them for every visible item and the app menus with them; it has to let everything
/// through, and this takes back the one stretch that should not.
///
/// Nothing is drawn. The window exists to be hit first and do nothing about it.
@MainActor
final class ClickShield {
    private var window: BarWindow?

    /// The shield's own window, so a capture of the bar can leave it out.
    var windowID: UInt32? { window.map { UInt32($0.windowNumber) } }

    /// Covers `rect`, in window-server coordinates.
    func show(over rect: CGRect) {
        let shield = window ?? make(rect)
        window = shield
        shield.ignoresMouseEvents = false
        stoodDown = nil
        shield.setFrame(cgFrame: rect)
        shield.orderFrontRegardless()
    }

    /// Stops swallowing clicks, without going away.
    ///
    /// For a handoff: the synthesised press that puts a real item in the user's hand has to reach
    /// that item, and this is the one window above it that would otherwise eat the press. Told to
    /// ignore events rather than ordered out because it is very much quicker — `orderOut` was
    /// measured taking between 150 and 300 ms to stop a window hit-testing, and a press posted
    /// inside that window is swallowed with nothing to show for it. This lands within 30 ms.
    ///
    /// It stays up and stays invisible while it is not swallowing. `show(over:)` puts it back to
    /// work.
    func standDown() {
        guard let window else { return }
        window.ignoresMouseEvents = true
        // Not restarted if it is already down: the clock is started as early as the Cmd-press, so
        // its beat overlaps the user's own reaction and the first of their movement, and a second
        // stand-down at the handoff must not throw that head start away.
        if stoodDown == nil { stoodDown = .now }
    }

    /// Goes back to swallowing, in place — the counterpart to a `standDown` that no handoff
    /// followed, such as a Cmd-press let go without a drag.
    func standUp() {
        window?.ignoresMouseEvents = false
        stoodDown = nil
    }

    /// Waits out whatever is left of that beat, having spent the rest of it doing something else.
    ///
    /// Only the *press* has to find the shield already ignoring events, and reading the item's
    /// frame and taking the pointer up to it both happen first. Waited out serially — which it was
    /// — the beat is 120 ms nobody is doing anything with; overlapped, most gestures have used it
    /// up by the time this is called.
    func settled() async {
        guard let stoodDown else { return }
        let left = Self.beatBeforeItTakesEffect - stoodDown.duration(to: .now)
        if left > .zero { try? await Task.sleep(for: left) }
    }

    private var stoodDown: ContinuousClock.Instant?

    /// Well past the 30 ms the change was measured taking, and paid once per gesture. Generous on
    /// purpose: a beat that is too short costs the whole gesture, and the margin costs nothing
    /// anybody can feel.
    private static let beatBeforeItTakesEffect: Duration = .milliseconds(120)

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func make(_ rect: CGRect) -> BarWindow {
        // Above the cover, which is itself a level above the items. Order only decides which
        // window is hit; there is nothing here to see in front of anything.
        let shield = BarWindow(
            frame: rect,
            level: NSWindow.Level(rawValue: BarWindow.statusLevel.rawValue + 2)
        )
        // Not `.clear`, which would defeat the whole point: the window server hit-tests
        // against the alpha in a window's backing store, so a fully transparent window is
        // click-through and the items underneath keep taking the clicks. One step off
        // transparent is a target; at 1/255 over a strip that is already a picture of empty
        // bar, there is nothing to see.
        shield.backgroundColor = NSColor.black.withAlphaComponent(1.0 / 255.0)
        return shield
    }
}

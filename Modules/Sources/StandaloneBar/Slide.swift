import AppKit

/// Grows the bar's panels out of the notch and back, and returns when they have arrived.
///
/// The bar is one panel made of two windows, because only one of them may take clicks: the shelf
/// of replicas, and the cover over the real section. `NotchSlide` moves both as one.
@MainActor
enum Slide {
    /// Grows the panel out of the notch, and returns once it is out. Awaited, because the cover
    /// being over the section is what makes it safe to reveal.
    ///
    /// Without a `duration` the panel is already where it rests, and whatever stands in for its
    /// arrival meanwhile runs instead (`CoverWindow.arrival`).
    static func panelOut(_ bar: ReplicaBar, _ cover: CoverWindow, over duration: TimeInterval?) async {
        guard let duration, let notch = cover.notch else { return await cover.arrive() }
        await NotchSlide.panelOut(bar, cover, from: notch, over: duration)
    }

    /// Runs `putAway`, which takes the section off the display, then takes the panel back into
    /// the notch, and returns once it has gone. Without a `duration` it only puts away.
    ///
    /// The section has to be gone before the panel goes: the cover leaves with the panel, so
    /// anything it was hiding has to have stopped being there first.
    static func panelIn(
        _ bar: ReplicaBar, _ cover: CoverWindow, over duration: TimeInterval?, after putAway: () async -> Void
    ) async {
        // A pointer moving over a window of Bouncer's own is invisible to the hover watch, which
        // has to see one coming back into the menu bar to reveal again once this has gone.
        bar.window?.ignoresMouseEvents = true
        bar.setCrossing(true)
        guard let duration, let notch = cover.notch else { return await putAway() }
        await NotchSlide.panelIn(bar, cover, into: notch, over: duration, after: putAway)
    }
}

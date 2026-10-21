import AppKit
import BouncerFoundation

/// Grows the bar's panel out of the notch and takes it back in, the way the iPhone's Dynamic
/// Island grows: on one spring, wider and taller at once, with the replicas coming into focus as
/// the shelf arrives.
///
/// The same two windows as `Slide`. The panel starts as the notch, black on black, and its lower
/// corners travel diagonally out to where it rests: the shelf and cover widen over the section
/// while the shelf's hanger lowers it, all in one animation so the path stays straight. Going away
/// blurs the replicas out while the section leaves, then tucks the shelf up and draws it in on one
/// spring without bounce: overshooting on the way in would show the panel narrower than the notch.
///
/// While the shelf is still tucked up behind the bar, its rounded foot is what gives the panel the
/// notch's rounded corners; the cover behind it wears the same corners, and squares them off in
/// step with the shelf dropping, so they are always behind the shelf's body and never show.
@MainActor
enum NotchSlide {
    /// Grows the panel out of the notch, and returns once it is out.
    static func panelOut(
        _ bar: ReplicaBar, _ cover: CoverWindow, from notch: Notch, over duration: TimeInterval
    ) async {
        guard let shelf = bar.panel, let hanger = bar.hanger, let resting = bar.restingShelf,
              let gatheredShelf = bar.shelfGathered(into: notch),
              let gatheredCover = cover.surfaceGathered(into: notch),
              let coverSize = cover.window?.frame.size
        else { return }
        let replicas = bar.replicas
        let restingReplicas = replicas.frame
        let windows = notch.isReal ? [] : [bar.window?.contentView, cover.window?.contentView]
        shelf.frame = gatheredShelf
        replicas.setFrameOrigin(centred(replicas, in: gatheredShelf))
        hanger.setFrameOrigin(CGPoint(x: 0, y: bar.tuck))
        cover.shape(to: gatheredCover)
        cover.panel.layer?.cornerRadius = ReplicaBar.cornerRadius
        for window in windows { window?.alphaValue = 0 }

        // One spring for the drop and the sides alike, so the lower corners travel a straight line.
        let grow = Motion(duration: duration * 2.4, bounce: 0.1)
        grow.move(hanger, to: CGPoint.zero)
        grow.move(shelf, to: resting)
        grow.move(replicas, to: restingReplicas)
        cover.shape(to: cover.restingSurface(in: coverSize), on: grow)
        grow.round(cover.panel, to: 0)
        for window in windows { grow.fade(window, to: 1) }
        let focusing = Motion(duration: duration * 1.6, bounce: 0, delay: duration * 0.6)
        focusing.focusIn([replicas, cover.pageSwitch])
        await grow.finished()
        await focusing.finished()
        Motion.unfocus([replicas, cover.pageSwitch])
    }

    /// Blurs the replicas out while `putAway` takes the section off the display, then takes the
    /// panel back in to the notch, and returns once it has gone.
    ///
    /// The replicas start going at once, the way the Dock starts hiding the moment the pointer
    /// leaves. The panel waits for the section to have gone, which usually takes milliseconds but
    /// can take a good part of the close after a quick open, and then lifts and draws in on one
    /// spring, so it always goes back diagonally, the way it came.
    static func panelIn(
        _ bar: ReplicaBar, _ cover: CoverWindow, into notch: Notch, over duration: TimeInterval,
        after putAway: () async -> Void
    ) async {
        guard let shelf = bar.panel, let hanger = bar.hanger,
              let gatheredShelf = bar.shelfGathered(into: notch),
              let gatheredCover = cover.surfaceGathered(into: notch)
        else { return await putAway() }
        let replicas = bar.replicas
        Motion(duration: duration * 0.6, bounce: 0).focusOut([replicas, cover.pageSwitch])
        await putAway()
        let gather = Motion(duration: duration * 1.6, bounce: 0)
        gather.move(hanger, to: CGPoint(x: 0, y: bar.tuck))
        gather.round(cover.panel, to: ReplicaBar.cornerRadius)
        gather.move(shelf, to: gatheredShelf)
        gather.move(replicas, to: CGRect(origin: centred(replicas, in: gatheredShelf), size: replicas.frame.size))
        cover.shape(to: gatheredCover, on: gather)
        if !notch.isReal {
            for window in [bar.window?.contentView, cover.window?.contentView] { gather.fade(window, to: 0) }
        }
        await gather.finished()
    }

    /// Where the replicas sit centred in a shelf of `shelf`'s size. Moved on the shelf's own spring,
    /// so they grow out of the middle with it rather than riding its left edge.
    private static func centred(_ replicas: NSView, in shelf: CGRect) -> CGPoint {
        CGPoint(x: ((shelf.width - replicas.frame.width) / 2).rounded(), y: replicas.frame.minY)
    }
}

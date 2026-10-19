import AppKit

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
        cover.panel.frame = gatheredCover
        cover.panel.layer?.cornerRadius = ReplicaBar.cornerRadius
        replicas.alphaValue = 0
        focus(replicas, blurredBy: focusBlur)
        for window in windows { window?.alphaValue = 0 }

        let grow = Motion(duration: duration * 2.4, bounce: 0.1)
        // Bouncier than the sides, which overshoot by a share of a far longer way: on the same
        // spring the drop's overshoot is a point, too little to see.
        let drop = Motion(duration: grow.duration, bounce: 0.4, startingWith: grow)
        drop.move(hanger, to: CGPoint.zero)
        grow.move(shelf, to: resting)
        grow.move(replicas, to: restingReplicas)
        // The drop carries the replicas; taking its bounce back out lets them settle without it.
        drop.offset(replicas, from: -bar.tuck)
        Motion(duration: grow.duration, bounce: 0, startingWith: grow).offset(replicas, from: bar.tuck)
        grow.move(cover.panel, to: cover.restingSurface(in: coverSize))
        grow.round(cover.panel, to: 0)
        for window in windows { grow.fade(window, to: 1) }
        let focusing = Motion(duration: duration * 1.6, bounce: 0, delay: duration * 0.6)
        focusing.fade(replicas, to: 1)
        focusing.blur(replicas, to: 0)
        await grow.finished()
        await focusing.finished()
        // A blur of nothing still renders the replicas offscreen on every capture.
        replicas.contentFilters = []
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
        focus(replicas, blurredBy: 0)
        let fade = Motion(duration: duration * 0.6, bounce: 0)
        fade.fade(replicas, to: 0)
        fade.blur(replicas, to: focusBlur)
        await putAway()
        let gather = Motion(duration: duration * 1.6, bounce: 0)
        gather.move(hanger, to: CGPoint(x: 0, y: bar.tuck))
        gather.round(cover.panel, to: ReplicaBar.cornerRadius)
        gather.move(shelf, to: gatheredShelf)
        gather.move(replicas, to: CGRect(origin: centred(replicas, in: gatheredShelf), size: replicas.frame.size))
        gather.move(cover.panel, to: gatheredCover)
        if !notch.isReal {
            for window in [bar.window?.contentView, cover.window?.contentView] { gather.fade(window, to: 0) }
        }
        await gather.finished()
        await fade.finished()
    }

    /// Where the replicas sit centred in a shelf of `shelf`'s size. Moved on the shelf's own spring,
    /// so they grow out of the middle with it rather than riding its left edge.
    private static func centred(_ replicas: NSView, in shelf: CGRect) -> CGPoint {
        CGPoint(x: ((shelf.width - replicas.frame.width) / 2).rounded(), y: replicas.frame.minY)
    }

    /// How out of focus the replicas are while the panel is still taking shape.
    private static let focusBlur: CGFloat = 8

    /// One spring, started after `delay`, that every property it moves rides as a Core Animation
    /// spring from the same start time. Not AppKit's spring: that steps each view's frame from the
    /// main thread, so the two windows and the layer properties it cannot reach each kept their own
    /// clock, and the halves of the panel visibly came apart.
    @MainActor
    private struct Motion {
        let duration: TimeInterval
        let bounce: CGFloat
        let delay: TimeInterval
        private let start: CFTimeInterval

        /// - Parameter other: a motion to start at exactly the same moment as.
        init(duration: TimeInterval, bounce: CGFloat, delay: TimeInterval = 0, startingWith other: Motion? = nil) {
            self.duration = duration
            self.bounce = bounce
            self.delay = delay
            start = other?.start ?? CACurrentMediaTime()
        }

        func move(_ view: NSView, to frame: CGRect) {
            guard let layer = view.layer else { return view.frame = frame }
            let position = shown(layer, "position")
            let bounds = shown(layer, "bounds")
            for key in layer.animationKeys() ?? [] where key.hasPrefix(Self.offsetKey) {
                layer.removeAnimation(forKey: key)
            }
            change { view.frame = frame }
            spring(layer, "position", from: position, to: layer.position)
            spring(layer, "bounds", from: bounds, to: layer.bounds)
        }

        func move(_ view: NSView, to origin: CGPoint) {
            move(view, to: CGRect(origin: origin, size: view.frame.size))
        }

        /// Moves `view` up by `distance` and back on top of whatever else moves it.
        func offset(_ view: NSView, from distance: CGFloat) {
            guard let layer = view.layer else { return }
            spring(layer, "position.y", from: distance, to: 0, additiveAs: Self.offsetKey + "\(bounce)")
        }

        func fade(_ view: NSView?, to alpha: CGFloat) {
            guard let view, let layer = view.layer else { return }
            let opacity = shown(layer, "opacity")
            change { view.alphaValue = alpha }
            spring(layer, "opacity", from: opacity, to: layer.opacity)
        }

        func round(_ view: NSView, to radius: CGFloat) {
            guard let layer = view.layer else { return }
            let from = shown(layer, "cornerRadius")
            change { layer.cornerRadius = radius }
            spring(layer, "cornerRadius", from: from, to: radius)
        }

        /// Needs the filter `focus(_:blurredBy:)` puts on the view.
        func blur(_ view: NSView, to radius: CGFloat) {
            guard let layer = view.layer else { return }
            let from = shown(layer, blurRadius)
            change { layer.setValue(radius, forKeyPath: blurRadius) }
            spring(layer, blurRadius, from: from, to: radius)
        }

        /// Returns once the motion has run its course, which is before the spring has finished
        /// settling: the tail of it is too small to see.
        func finished() async {
            let remaining = start + delay + duration - CACurrentMediaTime()
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
        }

        private static let offsetKey = "offset"

        /// Where the property is on screen: mid-flight if a spring is still carrying it.
        private func shown(_ layer: CALayer, _ keyPath: String) -> Any? {
            let moving = !(layer.animationKeys() ?? []).isEmpty
            return (moving ? layer.presentation() ?? layer : layer).value(forKeyPath: keyPath)
        }

        private func change(_ apply: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        }

        private func spring(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any?, additiveAs key: String? = nil) {
            let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            animation.beginTime = layer.convertTime(start + delay, from: nil)
            animation.fillMode = .backwards
            animation.isAdditive = key != nil
            layer.add(animation, forKey: key ?? keyPath)
        }
    }

    private static let blurRadius = "filters.blur.inputRadius"

    /// Puts the blur the replicas come into focus from, and go out of focus to, on `view`.
    private static func focus(_ view: NSView, blurredBy radius: CGFloat) {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.name = "blur"
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        view.layerUsesCoreImageFilters = true
        view.contentFilters = [filter]
    }
}

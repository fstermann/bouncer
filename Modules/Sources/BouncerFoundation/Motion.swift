import AppKit

/// One spring, started after `delay`, that every property it moves rides as a Core Animation
/// spring from the same start time. Not AppKit's spring: that steps each view's frame from the
/// main thread, so the two windows and the layer properties it cannot reach each kept their own
/// clock, and the halves of the panel visibly came apart.
///
/// Shared by both pages of the notch panel, so they grow, focus and gather alike.
@MainActor
public struct Motion {
    public let duration: TimeInterval
    public let bounce: CGFloat
    public let delay: TimeInterval
    private let start: CFTimeInterval

    /// - Parameter other: a motion to start at exactly the same moment as.
    public init(duration: TimeInterval, bounce: CGFloat, delay: TimeInterval = 0, startingWith other: Motion? = nil) {
        self.duration = duration
        self.bounce = bounce
        self.delay = delay
        start = other?.start ?? CACurrentMediaTime()
    }

    /// Springs `view` into `frame`. Subviews its autoresizing carries along ride the same spring, so
    /// whatever is pinned to an edge travels with that edge instead of jumping to where it ends up.
    public func move(_ view: NSView, to frame: CGRect) {
        guard let layer = view.layer else { return view.frame = frame }
        let position = shown(layer, "position")
        let bounds = shown(layer, "bounds")
        let carried = view.subviews.compactMap(\.layer).map {
            (layer: $0, frame: $0.frame, position: shown($0, "position"), bounds: shown($0, "bounds"))
        }
        change { view.frame = frame }
        spring(layer, "position", from: position, to: layer.position)
        spring(layer, "bounds", from: bounds, to: layer.bounds)
        for sub in carried where sub.layer.frame != sub.frame {
            spring(sub.layer, "position", from: sub.position, to: sub.layer.position)
            spring(sub.layer, "bounds", from: sub.bounds, to: sub.layer.bounds)
        }
    }

    public func move(_ view: NSView, to origin: CGPoint) {
        move(view, to: CGRect(origin: origin, size: view.frame.size))
    }

    public func fade(_ view: NSView?, to alpha: CGFloat) {
        guard let view, let layer = view.layer else { return }
        let opacity = shown(layer, "opacity")
        change { view.alphaValue = alpha }
        spring(layer, "opacity", from: opacity, to: layer.opacity)
    }

    public func round(_ view: NSView, to radius: CGFloat) {
        guard let layer = view.layer else { return }
        let from = shown(layer, "cornerRadius")
        change { layer.cornerRadius = radius }
        spring(layer, "cornerRadius", from: from, to: radius)
    }

    /// Needs the filter `focus(_:blurredBy:)` puts on the view.
    public func blur(_ view: NSView, to radius: CGFloat) {
        guard let layer = view.layer else { return }
        let from = shownBlur(view)
        change { layer.setValue(radius, forKeyPath: Self.blurRadius) }
        spring(layer, Self.blurRadius, from: from, to: radius)
    }

    /// Brings `views` into focus: faded in from nothing and sharpened from `focusBlur`.
    public func focusIn(_ views: [NSView]) {
        for view in views {
            view.alphaValue = 0
            Self.focus(view, blurredBy: Self.focusBlur)
            fade(view, to: 1)
            blur(view, to: 0)
        }
    }

    /// Takes `views` out of focus: faded out and blurred to `focusBlur`.
    public func focusOut(_ views: [NSView]) {
        for view in views {
            Self.focus(view, blurredBy: 0)
            fade(view, to: 0)
            blur(view, to: Self.focusBlur)
        }
    }

    /// Returns once the motion has run its course, which is before the spring has finished
    /// settling: the tail of it is too small to see.
    public func finished() async {
        let remaining = start + delay + duration - CACurrentMediaTime()
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }

    /// Takes the blur off once a view is in focus: a blur of nothing still renders the view
    /// offscreen on every frame.
    public static func unfocus(_ views: [NSView]) {
        for view in views { view.contentFilters = [] }
    }

    /// How out of focus content is while the panel around it is still taking shape.
    private static let focusBlur: CGFloat = 8
    private static let blurName = "blur"
    private static let blurRadius = "filters.blur.inputRadius"

    /// Puts the blur a view comes into focus from, and goes out of focus to, on `view`.
    private static func focus(_ view: NSView, blurredBy radius: CGFloat) {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.name = blurName
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        view.layerUsesCoreImageFilters = true
        view.contentFilters = [filter]
    }

    /// Where the property is on screen: mid-flight if a spring is still carrying it.
    private func shown(_ layer: CALayer, _ keyPath: String) -> Any? {
        let moving = !(layer.animationKeys() ?? []).isEmpty
        return (moving ? layer.presentation() ?? layer : layer).value(forKeyPath: keyPath)
    }

    /// Read off the filter itself, the view's until a spring carries the layer's: the key path a
    /// spring animates it by reads back nothing, and the view hands its filters to the layer late.
    private func shownBlur(_ view: NSView) -> Any? {
        let moving = view.layer?.animation(forKey: Self.blurRadius) != nil
        let filters = moving ? view.layer?.presentation()?.filters as? [CIFilter] : view.contentFilters
        return filters?.first { $0.name == Self.blurName }?.value(forKey: kCIInputRadiusKey)
    }

    private func change(_ apply: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply()
        CATransaction.commit()
    }

    private func spring(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any?) {
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        animation.beginTime = layer.convertTime(start + delay, from: nil)
        animation.fillMode = .backwards
        layer.add(animation, forKey: keyPath)
    }
}

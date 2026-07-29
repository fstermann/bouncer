import AppKit

/// Moves the bar's panels and returns when they have arrived.
///
/// The bar comes out of the menu bar as one panel: the replicas lead, the cover follows behind
/// them and stops over the section. They are two windows because only one of them may take
/// clicks, so they are animated in a single group — separate groups can start a frame apart,
/// and a frame apart is a seam opening up between two halves of the same panel.
///
/// Each window stays where it belongs and its contents slide inside it. A window travelling
/// into the menu bar band instead would be seen through a bar that is only partly opaque.
@MainActor
enum Slide {
    static func run(
        _ views: [NSView],
        to origin: CGPoint,
        over duration: TimeInterval,
        easing: CAMediaTimingFunctionName
    ) async {
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: easing)
                for view in views { view.animator().setFrameOrigin(origin) }
            } completionHandler: {
                continuation.resume()
            }
        }
    }
}

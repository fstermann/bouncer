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
    /// Runs the panel down out of the menu bar, and returns once it is out.
    ///
    /// Both halves travel the height of the shelf's window — its own height plus the band it comes
    /// through — in one animation group, which is what keeps them a single panel. Awaited, because
    /// the cover being over the section is what makes it safe to reveal, and eased out so the
    /// panel settles rather than stopping dead.
    static func panelOut(_ bar: ReplicaBar, _ cover: CoverWindow, over duration: TimeInterval) async {
        guard let shelf = bar.panel else { return }
        cover.park(by: bar.travel)
        bar.park(by: bar.travel)
        await run([shelf, cover.panel], to: .zero, over: duration, easing: .easeOut)
    }

    /// Takes the panel back into the menu bar, and returns once it has gone.
    ///
    /// Only ever called with the section already put away: the cover leaves with the panel, so
    /// anything it was hiding has to have stopped being there first.
    ///
    /// Eased at both ends rather than mirroring the way in. The reverse of an ease out is an ease
    /// in, which spends its slow half creeping and then throws the panel out of sight in the last
    /// few frames — the leaving is the part being watched, and it read as the bar vanishing rather
    /// than going.
    static func panelIn(_ bar: ReplicaBar, _ cover: CoverWindow, over duration: TimeInterval) async {
        guard let shelf = bar.panel else { return }
        let parked = CGPoint(x: 0, y: bar.travel)
        await run([shelf, cover.panel], to: parked, over: duration, easing: .easeInEaseOut)
    }

    private static func run(
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

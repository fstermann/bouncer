#if DEV
import CoreGraphics

/// When the bar has settled after an action, from frames read one after another: what the harness's
/// `still` waits on, so a shell check reads the bar once it has stopped moving instead of after a guessed
/// sleep. Frames only: a fade that moves nothing is not seen.
struct DevStillness {
    enum Verdict: Equatable {
        case still, neverMoved, stillMoving
    }

    /// How long the frames must agree, how long a move is waited for to start, and the most waited for
    /// in all, in seconds.
    static let hold = 0.2
    static let startDeadline = 0.6
    static let limit = 10.0

    private let start: Double
    private let before: [CGRect]?
    private var previous: [CGRect]?
    private var unchangedSince: Double
    private var hasMoved: Bool

    /// `before` is the reading from before the action, or `nil` with no action, when holding still is enough.
    init(before: [CGRect]?, at start: Double) {
        self.start = start
        self.before = before
        previous = before
        unchangedSince = start
        hasMoved = before == nil
    }

    /// Takes the next reading; the verdict once there is one.
    mutating func read(_ frames: [CGRect], at time: Double) -> Verdict? {
        if frames != previous {
            previous = frames
            unchangedSince = time
        }
        if let before, frames != before { hasMoved = true }
        if hasMoved, time - unchangedSince >= Self.hold { return .still }
        if !hasMoved, time - start >= Self.startDeadline { return .neverMoved }
        if time - start >= Self.limit { return .stillMoving }
        return nil
    }
}
#endif

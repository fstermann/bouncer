import BouncerFoundation
import CoreGraphics

/// Bounded waits on the window server placing status items.
///
/// The divider moves nothing synchronously: expanding or collapsing it lands over a few
/// frames, and frames read before it has are the old ones. Each wait here returns the
/// moment the state it is after arrives, and none runs outside an open or close the user
/// just asked for — they are waits inside an interaction, not polls.
enum PlacementWait {
    /// Waits for the window server to place the items the divider just released.
    ///
    /// Yielding once is not enough; the move takes a few frames.
    static func placement(of ids: Set<UInt32>) async {
        for _ in 0..<attemptLimit {
            let placed = StatusItemScanner.scan()
                .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
            if placed.count == ids.count { return }
            try? await Task.sleep(for: .milliseconds(8))
        }
        Log.menuBar.error("Standalone bar: revealed items never landed on screen")
    }

    /// Waits for the divider to push the items back off the display.
    ///
    /// The mirror of `placement`: the cover has to stay up until they have gone.
    static func removal(of ids: Set<UInt32>) async {
        for _ in 0..<attemptLimit {
            let onScreen = StatusItemScanner.scan()
                .filter { ids.contains($0.windowID) && $0.frame.minX >= 0 }
            if onScreen.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(8))
        }
        Log.menuBar.error("Standalone bar: the section never went back off screen")
    }

    /// The frames of `ids`, as the window server currently reports them.
    static func frames(of ids: Set<UInt32>) -> [UInt32: CGRect] {
        Dictionary(
            StatusItemScanner.scan()
                .filter { ids.contains($0.windowID) }
                .map { ($0.windowID, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Waits until the items have held still for a while, or gives up.
    ///
    /// The recording indicator does not arrive with the first captured frame — it takes a
    /// few hundred milliseconds, and shifts the whole bar when it lands. Two readings in a
    /// row agreeing proves nothing at that distance, so stillness has to be held.
    ///
    /// The hold is short, and the wait ends early once the shift has come and gone: what is
    /// being waited for is a single event, so a run of agreeing readings after it has landed
    /// is the answer, not evidence towards it. `movedFrom` is where the items sat before the
    /// capture, which is what makes the shift recognisable rather than merely absent.
    static func stillness(of ids: Set<UInt32>, movedFrom before: [UInt32: CGRect]) async {
        var previous = before
        var still = 0
        var hasMoved = false
        for reading in 0..<stillnessLimit {
            // Nothing has stirred in the time the indicator takes to land, so nothing is
            // going to: it was already in the bar before this open, and shifted it then.
            if !hasMoved, reading >= shiftDeadline { return }

            try? await Task.sleep(for: .milliseconds(16))
            let current = frames(of: ids)
            still = current == previous ? still + 1 : 0
            hasMoved = hasMoved || current != before
            previous = current
            if hasMoved, still >= stillnessRequired { return }
        }
    }

    private static let attemptLimit = 30

    /// Readings that must agree in a row once the bar has shifted, how long a shift is
    /// waited for before concluding there will not be one, and the most that will be waited
    /// for either way — about a tenth, a quarter and half a second.
    private static let stillnessRequired = 6
    private static let shiftDeadline = 16
    private static let stillnessLimit = 30
}

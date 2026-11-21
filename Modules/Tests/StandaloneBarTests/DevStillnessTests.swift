#if DEV
import CoreGraphics
@testable import StandaloneBar
import Testing

struct DevStillnessTests {
    private let rest = [CGRect(x: 100, y: 0, width: 20, height: 24)]
    private let moved = [CGRect(x: 140, y: 0, width: 20, height: 24)]

    @Test func settlesOnceAMoveHasHeld() {
        var stillness = DevStillness(before: rest, at: 0)
        #expect(stillness.read(rest, at: 0.1) == nil)
        #expect(stillness.read(moved, at: 0.3) == nil)
        #expect(stillness.read(moved, at: 0.4) == nil)
        #expect(stillness.read(moved, at: 0.5) == .still)
    }

    @Test func waitsOutAMoveThatKeepsGoing() {
        var stillness = DevStillness(before: rest, at: 0)
        #expect(stillness.read(moved, at: 0.1) == nil)
        #expect(stillness.read(rest, at: 0.25) == nil)
        #expect(stillness.read(moved, at: 0.4) == nil)
        #expect(stillness.read(moved, at: 0.65) == .still)
    }

    @Test func givesUpWhenNothingMoves() {
        var stillness = DevStillness(before: rest, at: 0)
        #expect(stillness.read(rest, at: 0.5) == nil)
        #expect(stillness.read(rest, at: 0.6) == .neverMoved)
    }

    @Test func reportsAMoveThatNeverStops() {
        var stillness = DevStillness(before: rest, at: 0)
        var verdict: DevStillness.Verdict?
        var time = 0.0
        for step in 1...200 where verdict == nil {
            time = Double(step) / 10
            verdict = stillness.read(step.isMultiple(of: 2) ? rest : moved, at: time)
        }
        #expect(verdict == .stillMoving)
        #expect(time >= DevStillness.limit)
    }

    @Test func withNoActionHoldingStillIsEnough() {
        var stillness = DevStillness(before: nil, at: 0)
        #expect(stillness.read(rest, at: 0.1) == nil)
        #expect(stillness.read(rest, at: 0.35) == .still)
    }
}
#endif

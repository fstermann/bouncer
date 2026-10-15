import CoreGraphics
import Testing

@testable import StandaloneBar

@Suite("Stable status-item placement")
struct PlacementWaitTests {
    @Test("A privacy-indicator shift restarts the stable-reading count")
    func shiftRestartsStillness() {
        var stability = PlacementStability(ids: [1, 2], readingsRequired: 3)
        let before = frames(firstX: 20)
        let after = frames(firstX: 50)

        #expect(stability.observe(before) == nil)
        #expect(stability.observe(before) == nil)
        #expect(stability.observe(after) == nil)
        #expect(stability.observe(after) == nil)
        #expect(stability.observe(after) == after)
    }

    @Test("A missing drag target can never be called stable")
    func missingTargetIsUnstable() {
        var stability = PlacementStability(ids: [1, 2], readingsRequired: 2)
        let incomplete: [UInt32: CGRect] = [1: CGRect(x: 20, y: 0, width: 20, height: 24)]

        #expect(stability.observe(incomplete) == nil)
        #expect(stability.observe(incomplete) == nil)
    }

    private func frames(firstX: CGFloat) -> [UInt32: CGRect] {
        [
            1: CGRect(x: firstX, y: 0, width: 20, height: 24),
            2: CGRect(x: firstX + 20, y: 0, width: 20, height: 24)
        ]
    }
}

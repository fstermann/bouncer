import CoreGraphics
import Testing

@testable import StandaloneBar

@Suite("Settings item arrangement")
@MainActor
struct StandaloneItemArrangementTests {
    private func item(_ id: UInt32) -> MenuBarItem {
        MenuBarItem(windowID: id, frame: CGRect(x: Int(id) * 20, y: 0, width: 20, height: 24))
    }

    @Test("An item uses its right-hand neighbour as the exact insertion point")
    func moveBeforeNextItem() {
        let order = [item(2), item(1), item(3)]
        #expect(StandaloneItemArrangement.destination(for: 1, in: order) == .before(3))
    }

    @Test("The last item lands to the right of its left-hand neighbour")
    func moveAfterPreviousItem() {
        let order = [item(2), item(3), item(1)]
        #expect(StandaloneItemArrangement.destination(for: 1, in: order) == .after(3))
    }

    @Test("A bar with one item needs no system move")
    func onlyItemHasNoDestination() {
        #expect(StandaloneItemArrangement.destination(for: 1, in: [item(1)]) == nil)
    }

    @Test("Items are found against the hidden divider while the standalone bar is open")
    func findsRevealedItems() {
        let divider = MenuBarItem(windowID: 90, frame: CGRect(x: 80, y: 0, width: 17, height: 24))
        let visible = MenuBarItem(windowID: 4, frame: CGRect(x: 120, y: 0, width: 20, height: 24))
        let all = [item(1), item(2), divider, visible]
        let own = [divider.windowID: "bouncer.divider.hidden"]

        let result = StandaloneItemArrangement.previewItems(
            from: all,
            own: own,
            screens: [CGRect(x: 0, y: 0, width: 200, height: 100)]
        )

        #expect(result?.map(\.windowID) == [1, 2])
    }

    @Test("Off-screen items are kept while the hidden divider is expanded")
    func findsCollapsedItems() {
        let hidden = MenuBarItem(windowID: 1, frame: CGRect(x: -430, y: 0, width: 20, height: 24))
        let divider = MenuBarItem(windowID: 90, frame: CGRect(x: -400, y: 0, width: 500, height: 24))
        let visible = MenuBarItem(windowID: 4, frame: CGRect(x: 120, y: 0, width: 20, height: 24))

        let result = StandaloneItemArrangement.previewItems(
            from: [hidden, divider, visible],
            own: [divider.windowID: "bouncer.divider.hidden"],
            screens: [CGRect(x: 0, y: 0, width: 200, height: 100)]
        )

        #expect(result?.map(\.windowID) == [hidden.windowID])
    }

    @Test("A scan before Bouncer's divider appears is not mistaken for an empty section")
    func waitsForDivider() {
        let result = StandaloneItemArrangement.previewItems(
            from: [item(1), item(2)],
            own: [:],
            screens: [CGRect(x: 0, y: 0, width: 200, height: 100)]
        )

        #expect(result == nil)
    }

    @Test("Parked items are revealed before they are photographed")
    func revealsParkedItemsForCapture() {
        let parked = [
            MenuBarItem(windowID: 1, frame: CGRect(x: -40, y: 0, width: 20, height: 24)),
            MenuBarItem(windowID: 2, frame: CGRect(x: -20, y: 0, width: 20, height: 24))
        ]

        let plan = StandaloneItemArrangement.capturePlan(
            for: parked,
            existingImageIDs: [],
            screens: [CGRect(x: 0, y: 0, width: 200, height: 100)]
        )

        #expect(plan == .revealThenCapture)
    }

    @Test("Revealed items are accepted when WindowServer renumbers them")
    func acceptsRenumberedItemsAfterReveal() {
        let divider = MenuBarItem(windowID: 90, frame: CGRect(x: 80, y: 0, width: 17, height: 24))
        let revealed = [
            MenuBarItem(windowID: 11, frame: CGRect(x: 40, y: 0, width: 20, height: 24)),
            MenuBarItem(windowID: 12, frame: CGRect(x: 60, y: 0, width: 20, height: 24))
        ]

        let result = StandaloneItemArrangement.captureCandidates(
            from: revealed + [divider],
            own: [divider.windowID: "bouncer.divider.hidden"],
            expectedCount: 2,
            screens: [CGRect(x: 0, y: 0, width: 200, height: 100)]
        )

        #expect(result?.map(\.windowID) == [11, 12])
    }

    @Test("A picked-up item may leave the status-item layer while its destination stays anchored")
    func onlyDestinationMustRemainAfterMouseDown() {
        #expect(
            StatusItemMover.idsThatMustRemainAfterMouseDown(1, destination: .before(2)) == [2]
        )
    }

    @Test("Parked items are revealed before a real menu-bar move")
    func revealsParkedItemsForMove() {
        let parked = [MenuBarItem(windowID: 1, frame: CGRect(x: -20, y: 0, width: 20, height: 24))]

        #expect(
            StandaloneItemArrangement.requiresRevealForMove(
                parked, screens: [CGRect(x: 0, y: 0, width: 200, height: 100)]
            )
        )
    }

    @Test("A settled old-ID order must match the settings preview")
    func rejectsARevertedMove() {
        let desired = [item(2), item(1), item(3)]
        let reverted = [item(1), item(2), item(3)]

        #expect(StandaloneItemArrangement.verified(reverted, matches: desired) == nil)
        #expect(StandaloneItemArrangement.verified(desired, matches: desired) == desired)
    }
}

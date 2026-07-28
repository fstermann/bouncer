import CoreGraphics
import Testing

@testable import StandaloneBar

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

private func item(_ originX: CGFloat, _ width: CGFloat, id: UInt32 = 1) -> MenuBarItem {
    MenuBarItem(windowID: id, frame: CGRect(x: originX, y: 0, width: width, height: 33))
}

@Suite("Off-screen classification")
struct OffScreenTests {
    @Test("Items pushed past the left edge are off screen")
    func hiddenSection() {
        // Real frames from a collapsed bar: the divider parks its section far to the left.
        let items = [item(-4079, 40, id: 1), item(-3856, 31, id: 2), item(1191, 38, id: 3)]
        let hidden = MenuBarItemGeometry.offScreen(items, screens: [screen])
        #expect(hidden.map(\.windowID) == [1, 2])
    }

    @Test("An item straddling the edge counts as visible, because it is partly drawn")
    func straddling() {
        let straddler = item(-10, 40)
        #expect(MenuBarItemGeometry.offScreen([straddler], screens: [screen]).isEmpty)
    }

    @Test("With no screens, everything is off screen")
    func noScreens() {
        #expect(MenuBarItemGeometry.offScreen([item(100, 40)], screens: []).count == 1)
    }
}

@Suite("Divider filtering")
struct DividerTests {
    @Test("An expanded divider is excluded, real items are kept")
    func excludesDividers() {
        let items = [item(-3825, 5016, id: 1), item(1191, 38, id: 2), item(1229, 67, id: 3)]
        let real = MenuBarItemGeometry.excludingDividers(items)
        #expect(real.map(\.windowID) == [2, 3])
    }

    @Test("The widest plausible real item is not mistaken for a divider")
    func keepsWideItems() {
        #expect(MenuBarItemGeometry.excludingDividers([item(1000, 254)]).count == 1)
    }
}

@Suite("Cover rectangle")
struct CoverTests {
    @Test("Spans from the first item to the last")
    func spansSection() {
        // The hidden section as measured once revealed: seven items over 254 pt.
        let items = [item(904, 40), item(944, 33), item(1127, 31)]
        let rect = MenuBarItemGeometry.coverRect(for: items)
        #expect(rect == CGRect(x: 904, y: 0, width: 254, height: 33))
    }

    @Test("An empty section has nothing to cover")
    func emptySection() {
        #expect(MenuBarItemGeometry.coverRect(for: []) == nil)
    }
}

@Suite("Replica layout")
struct LayoutTests {
    @Test("Replicas mirror the real horizontal positions, so menus open under them")
    func mirrorsRealPositions() {
        // Menus anchor to the real item's own x, and the real item cannot be moved — so a
        // replica has to sit at the same offset or its menu opens somewhere else.
        let left = item(904, 40, id: 1)
        let right = item(1127, 31, id: 2)
        let (positions, size) = MenuBarItemGeometry.layout([right, left])

        #expect(positions[left] == CGRect(x: 0, y: 0, width: 40, height: 33))
        #expect(positions[right] == CGRect(x: 223, y: 0, width: 31, height: 33))
        // The bar spans the section: 1127 + 31 - 904.
        #expect(size == CGSize(width: 254, height: 33))
    }

    @Test("Gaps between items are preserved, not collapsed")
    func preservesGaps() {
        let (positions, _) = MenuBarItemGeometry.layout([item(904, 40, id: 1), item(1000, 40, id: 2)])
        let first = positions[item(904, 40, id: 1)]
        let second = positions[item(1000, 40, id: 2)]
        // 96 pt apart in the menu bar, 96 pt apart in the replica.
        #expect((second?.minX ?? 0) - (first?.minX ?? 0) == 96)
    }

    @Test("An empty bar has no width")
    func empty() {
        let (positions, size) = MenuBarItemGeometry.layout([])
        #expect(positions.isEmpty)
        #expect(size == .zero)
    }
}

@Suite("Click mapping")
struct HitTests {
    @Test("A click on a replica maps to the same offset on the real item")
    func mapsToRealItem() {
        let target = item(904, 40, id: 1)
        let (positions, _) = MenuBarItemGeometry.layout([target])
        // 12 pt into the replica, 16 pt down.
        let hit = MenuBarItemGeometry.itemHit(at: CGPoint(x: 12, y: 16), positions: positions)
        #expect(hit?.item == target)
        #expect(hit?.pointOnItem == CGPoint(x: 916, y: 16))
    }

    @Test("A click in a gap hits nothing rather than the nearest item")
    func gapsAreNotItems() {
        let (positions, _) = MenuBarItemGeometry.layout(
            [item(904, 40, id: 1), item(1000, 40, id: 2)])
        // x = 60 falls in the gap between the two replicas.
        #expect(MenuBarItemGeometry.itemHit(at: CGPoint(x: 60, y: 16), positions: positions) == nil)
    }
}

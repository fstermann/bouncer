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

@Suite("Landing strip")
struct LandingStripTests {
    /// Frames measured off a real bar: the parked section, and the run it comes back beside.
    private let parked = [item(-4237, 45, id: 1), item(-4192, 36, id: 2), item(-4156, 38, id: 3)]
    private let run = [item(1154, 32, id: 4), item(1186, 38, id: 5), item(1224, 44, id: 6)]

    @Test("Predicts where the section lands, to the point")
    func matchesWhereTheItemsActuallyLand() {
        let predicted = MenuBarItemGeometry.landingStrip(for: parked, leftOf: run + parked)
        // Where they actually landed: packed edge to edge, ending 17 pt short of the run
        // because the divider is still between the two.
        let landed = [item(1018, 45, id: 1), item(1063, 36, id: 2), item(1099, 38, id: 3)]
        #expect(predicted == MenuBarItemGeometry.coverRect(for: landed))
    }

    @Test("Leaves room for the divider, which stays in the bar between the two")
    func allowsForTheDivider() {
        let predicted = MenuBarItemGeometry.landingStrip(for: parked, leftOf: run + parked)
        #expect(predicted.maxX == 1154 - MenuBarItemGeometry.collapsedDividerWidth)
    }

    @Test("Lands beside the run, not beside a lone item further left")
    func ignoresAnItemAcrossAGap() {
        let stray = item(400, 33, id: 7)
        let predicted = MenuBarItemGeometry.landingStrip(for: parked, leftOf: [stray] + run)
        #expect(predicted.maxX == 1137)
    }

    @Test("Nothing parked is nothing to cover")
    func nothingParked() {
        #expect(MenuBarItemGeometry.landingStrip(for: [], leftOf: run).width == 0)
    }
}

@Suite("Packing the section into its landing strip")
struct PackingTests {
    private let parked = [item(-4237, 45, id: 1), item(-4192, 36, id: 2), item(-4156, 38, id: 3)]
    private let strip = CGRect(x: 1000, y: 0, width: 119, height: 33)

    @Test("Packs edge to edge from the left of the strip")
    func packsEdgeToEdge() {
        let packed = MenuBarItemGeometry.packed(parked, into: strip, like: [])
        #expect(packed.map(\.frame.minX) == [1000, 1045, 1081])
        #expect(MenuBarItemGeometry.coverRect(for: packed) == strip)
    }

    @Test("Follows the order the section came back in last time")
    func followsTheRememberedOrder() {
        // Measured: two items of the same width traded places on the way back on screen.
        let packed = MenuBarItemGeometry.packed(parked, into: strip, like: [1, 3, 2])
        #expect(packed.map(\.windowID) == [1, 3, 2])
        #expect(packed.map(\.frame.minX) == [1000, 1045, 1083])
    }

    @Test("An item the remembered order has never seen keeps its parked place, at the end")
    func unknownItemsGoLast() {
        let packed = MenuBarItemGeometry.packed(parked, into: strip, like: [3])
        #expect(packed.map(\.windowID) == [3, 1, 2])
    }
}

@Suite("What the section contains after a drag")
struct SectionTests {
    /// The hidden divider's left edge. Bouncer's own items are named out by the scanner before
    /// this is asked, so the divider is a gap rather than an item, 17 pt wide.
    private let divider: CGFloat = 1120
    /// A revealed section of three ending flush against the divider, then the visible run.
    private let section = [item(1000, 40, id: 1), item(1040, 30, id: 2), item(1070, 50, id: 3)]
    private let visible = [item(1137, 40, id: 8), item(1177, 65, id: 9)]

    @Test("The section is everything left of the divider")
    func findsTheSection() {
        let run = MenuBarItemGeometry.section(section + visible, leftOf: divider)
        #expect(run.map(\.windowID) == [1, 2, 3])
    }

    @Test("An item dragged out across the divider is not in it any more")
    func followsAnItemOut() {
        // Item 3 crossed the divider; the two left behind slid right to close the gap.
        let bar = [item(1030, 40, id: 1), item(1070, 30, id: 2), item(1137, 50, id: 3)] + visible
        #expect(MenuBarItemGeometry.section(bar, leftOf: divider).map(\.windowID) == [1, 2])
    }

    @Test("An item dragged in from the visible side is in it")
    func followsAnItemIn() {
        let bar = [item(960, 40, id: 8)] + section + visible
        #expect(MenuBarItemGeometry.section(bar, leftOf: divider).map(\.windowID) == [8, 1, 2, 3])
    }

    @Test("A hole opened for an item in flight does not cut the section short")
    func survivesTheHole() {
        // Mid-drag: the item being pulled in has left the status item layer, and macOS has opened
        // a 40 pt hole against the divider for it. Every rule that read gaps stopped here.
        let bar = [item(960, 40, id: 1), item(1000, 30, id: 2), item(1030, 50, id: 3)] + visible
        #expect(MenuBarItemGeometry.section(bar, leftOf: divider).map(\.windowID) == [1, 2, 3])
    }

    @Test("The icon sorting between the divider and the visible run changes nothing")
    func ignoresTheIcon() {
        // Bouncer's icon is seeded at the right end, so the gap it leaves when it is named out
        // falls inside the visible run — on the far side of the divider, where nothing is read.
        let bar = section + [item(1137, 40, id: 8)] + [item(1230, 65, id: 9)]
        #expect(MenuBarItemGeometry.section(bar, leftOf: divider).map(\.windowID) == [1, 2, 3])
    }

    @Test("Everything dragged out is an empty section")
    func nothingLeft() {
        #expect(MenuBarItemGeometry.section(visible, leftOf: divider).isEmpty)
    }

    @Test("An empty bar is an empty section")
    func nothingAtAll() {
        #expect(MenuBarItemGeometry.section([], leftOf: divider).isEmpty)
    }
}

@Suite("The stretch of bar the panel covers")
struct CoverToDividerTests {
    private let divider: CGFloat = 1120

    @Test("At rest it is the items, which are flush against the divider")
    func matchesTheUnionAtRest() {
        let section = [item(1000, 40, id: 1), item(1040, 80, id: 2)]
        let strip = MenuBarItemGeometry.coverRect(for: section, upTo: divider)
        #expect(strip == MenuBarItemGeometry.coverRect(for: section))
        #expect(strip?.width == 120)
    }

    @Test("Mid-drag it reaches over the hole to the divider")
    func reachesTheDivider() {
        // The item in hand has left the layer and its 40 pt hole is against the divider, so the
        // items alone stop 40 pt short of it.
        let section = [item(960, 40, id: 1), item(1000, 80, id: 2)]
        #expect(MenuBarItemGeometry.coverRect(for: section, upTo: divider)?.width == 160)
    }

    @Test("Nothing in the section is nothing to cover")
    func nothingToCover() {
        #expect(MenuBarItemGeometry.coverRect(for: [], upTo: divider) == nil)
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
    @Test("A click on a replica names the item it replicates")
    func mapsToRealItem() {
        let target = item(904, 40, id: 1)
        let (positions, _) = MenuBarItemGeometry.layout([target])
        // 12 pt into the replica, 16 pt down.
        #expect(MenuBarItemGeometry.item(at: CGPoint(x: 12, y: 16), positions: positions) == target)
    }

    @Test("A click in a gap hits nothing rather than the nearest item")
    func gapsAreNotItems() {
        let (positions, _) = MenuBarItemGeometry.layout(
            [item(904, 40, id: 1), item(1000, 40, id: 2)])
        // x = 60 falls in the gap between the two replicas.
        #expect(MenuBarItemGeometry.item(at: CGPoint(x: 60, y: 16), positions: positions) == nil)
    }
}

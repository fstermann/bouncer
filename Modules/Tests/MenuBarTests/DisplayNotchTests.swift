import CoreGraphics
import Testing

@testable import MenuBar

@Suite struct DisplayNotchTests {
    /// The 14-inch MacBook Pro, as `NSScreen` reports it.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let left = CGRect(x: 0, y: 950, width: 663, height: 32)
    private let right = CGRect(x: 848, y: 950, width: 664, height: 32)

    @Test func notchIsTheGapBetweenTheBarEitherSide() {
        let notch = DisplayNotch.range(left: left, right: right, screen: screen)
        #expect(notch.range == 663...848)
        #expect(notch.isReal)
    }

    @Test func displayWithoutOneGetsAStandInAtTheTopCentre() {
        let notch = DisplayNotch.range(left: nil, right: nil, screen: screen)
        #expect(notch.range == 663.5...848.5)
        #expect(!notch.isReal)
    }

    @Test func pointerOverOrBesideTheNotchReveals() {
        let notch: ClosedRange<CGFloat> = 663...848
        let reveals = { (across: CGFloat, up: CGFloat) in
            DisplayNotch.reveals(
                at: CGPoint(x: across, y: up), notch: notch, isReal: true, screen: screen, menuBarHeight: 32
            )
        }
        #expect(reveals(755, 981))
        #expect(reveals(650, 960))
        #expect(!reveals(600, 981), "too far to the side")
        #expect(!reveals(755, 900), "below the menu bar")
        #expect(!reveals(755, 1000), "on a display above")
    }

    @Test func aStandInRevealsOnlyAtTheTopEdge() {
        let reveals = { (up: CGFloat) in
            DisplayNotch.reveals(
                at: CGPoint(x: 755, y: up), notch: 663...848, isReal: false, screen: screen, menuBarHeight: 24
            )
        }
        #expect(reveals(982))
        #expect(reveals(981.5))
        #expect(!reveals(970), "in the menu bar, but below the edge")
    }

    @Test func menuBarEndsAtTheTopEdge() {
        #expect(DisplayNotch.isInMenuBar(CGPoint(x: 100, y: 982), screen: screen, menuBarHeight: 32))
        #expect(!DisplayNotch.isInMenuBar(CGPoint(x: 100, y: 1200), screen: screen, menuBarHeight: 32))
    }
}

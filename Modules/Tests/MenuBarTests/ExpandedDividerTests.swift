import CoreGraphics
import Testing

@testable import MenuBar

@Suite struct ExpandedDividerTests {
    /// The 14-inch MacBook Pro's notch, as `DisplayNotch` reports it.
    private let notch: ClosedRange<CGFloat> = 663.5...848.5

    @Test func reachesIntoTheMiddleOfTheNotch() {
        let length = ExpandedDivider.length(rightEdge: 1376, notch: notch)
        #expect(length == 620)
    }

    @Test func waitsUntilItHasBeenPlaced() {
        #expect(ExpandedDivider.length(rightEdge: nil, notch: notch) == nil)
    }

    @Test func runsOffTheDisplayWhereTheBarAllowsIt() {
        #expect(ExpandedDivider.length(rightEdge: nil, notch: nil) == ExpandedDivider.legacyLength)
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: nil) == ExpandedDivider.legacyLength)
    }

    @Test func hidesNothingWhileTheIconIsLeftOfIt() {
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: notch, keeping: 1163) == nil)
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: notch, keeping: 1420) == 620)
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: nil, keeping: 1163) == ExpandedDivider.legacyLength)
    }

    @Test func neverCollapsesToNothingLeftOfTheNotch() {
        #expect(ExpandedDivider.length(rightEdge: 600, notch: notch) == 1)
    }
}

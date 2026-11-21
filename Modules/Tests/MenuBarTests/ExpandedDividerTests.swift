import CoreGraphics
import Testing

@testable import MenuBar

@Suite struct ExpandedDividerTests {
    /// The 14-inch MacBook Pro's notch, as `DisplayNotch` reports it.
    private let notch: ClosedRange<CGFloat> = 663.5...848.5

    @Test func isAsWideAsTheBarLeftOfTheNotch() {
        // Measured: 528 to 740 pt hid everything with the section ending at 1266, whatever its end.
        #expect(ExpandedDivider.length(rightEdge: 1266, notch: notch, evicts: true) == 663.5)
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: notch, evicts: true) == 663.5)
    }

    @Test func waitsUntilItHasBeenPlaced() {
        #expect(ExpandedDivider.length(rightEdge: nil, notch: notch, evicts: true) == nil)
    }

    @Test func runsOffTheDisplayWhereTheBarAllowsIt() {
        #expect(ExpandedDivider.length(rightEdge: nil, notch: nil, evicts: false) == ExpandedDivider.legacyLength)
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: notch, evicts: false) == ExpandedDivider.legacyLength)
    }

    @Test func hidesNothingWhileTheIconIsLeftOfIt() {
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: notch, evicts: true, keeping: 1163) == nil)
        #expect(ExpandedDivider.length(rightEdge: 1376, notch: notch, evicts: true, keeping: 1420) == 663.5)
        #expect(
            ExpandedDivider.length(rightEdge: 1376, notch: nil, evicts: false, keeping: 1163)
                == ExpandedDivider.legacyLength
        )
        #expect(ExpandedDivider.length(rightEdge: 1311, notch: nil, evicts: true, keeping: 1279) == nil)
    }

    @Test func neverCollapsesToNothingLeftOfTheNotch() {
        #expect(ExpandedDivider.length(rightEdge: 600, notch: notch, evicts: true) == 1)
    }

    @Test func staysUnderTheEvictionLimitWithoutANotch() {
        #expect(ExpandedDivider.length(rightEdge: 1311, notch: nil, evicts: true) == ExpandedDivider.notchlessLength)
        #expect(ExpandedDivider.length(rightEdge: nil, notch: nil, evicts: true) == nil)
    }
}

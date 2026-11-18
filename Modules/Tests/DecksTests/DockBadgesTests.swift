@testable import Decks
import Testing

@Suite struct DockBadgesTests {
    @Test func sumsCounts() {
        #expect(DockBadges.combined(["3", "12"]) == "15")
    }

    @Test func countsOutweighMarks() {
        #expect(DockBadges.combined(["•", "2"]) == "2")
    }

    @Test func marksAloneMakeADot() {
        #expect(DockBadges.combined(["!"]) == "•")
    }

    @Test func noBadgeWithoutLabels() {
        #expect(DockBadges.combined([]) == nil)
    }
}

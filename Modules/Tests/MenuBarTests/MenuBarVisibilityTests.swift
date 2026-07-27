import Testing

@testable import MenuBar

@Suite struct MenuBarVisibilityTests {
    @Test(arguments: MenuBarVisibility.allCases)
    func visibleSectionIsAlwaysShown(_ visibility: MenuBarVisibility) {
        #expect(visibility.shows(.visible))
    }

    @Test func collapsedShowsNothingElse() {
        #expect(!MenuBarVisibility.collapsed.shows(.hidden))
        #expect(!MenuBarVisibility.collapsed.shows(.alwaysHidden))
    }

    @Test func revealedShowsHiddenButNotAlwaysHidden() {
        #expect(MenuBarVisibility.revealed.shows(.hidden))
        #expect(!MenuBarVisibility.revealed.shows(.alwaysHidden))
    }
}

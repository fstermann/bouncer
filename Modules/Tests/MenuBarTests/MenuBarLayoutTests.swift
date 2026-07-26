import CoreGraphics
import Testing

@testable import MenuBar

private func item(id: CGWindowID, minX: CGFloat) -> MenuBarItem {
    MenuBarItem(
        windowID: id,
        ownerPID: 1,
        ownerName: "App\(id)",
        title: nil,
        frame: CGRect(x: minX, y: 0, width: 24, height: 24),
        isOnScreen: true
    )
}

@Suite struct MenuBarLayoutTests {
    @Test func itemsRightOfTheDividerAreVisible() {
        let result = MenuBarLayout.classify(
            items: [item(id: 1, minX: 900), item(id: 2, minX: 500)],
            hiddenDividerMinX: 700,
            alwaysHiddenDividerMinX: nil
        )
        #expect(result.map(\.section) == [.visible, .hidden])
    }

    @Test func itemsLeftOfTheSecondDividerAreAlwaysHidden() {
        let result = MenuBarLayout.classify(
            items: [item(id: 1, minX: 900), item(id: 2, minX: 500), item(id: 3, minX: 100)],
            hiddenDividerMinX: 700,
            alwaysHiddenDividerMinX: 300
        )
        #expect(result.map(\.section) == [.visible, .hidden, .alwaysHidden])
    }

    @Test func alwaysHiddenCollapsesIntoHiddenWhenTheSectionIsOff() {
        let result = MenuBarLayout.classify(
            items: [item(id: 1, minX: 100)],
            hiddenDividerMinX: 700,
            alwaysHiddenDividerMinX: nil
        )
        #expect(result.map(\.section) == [.hidden])
    }

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

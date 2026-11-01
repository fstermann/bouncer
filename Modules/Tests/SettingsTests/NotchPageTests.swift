import Testing

@testable import Settings

@Suite struct NotchPageTests {
    @Test func pagesKeepOneOrderWhicheverAreOn() {
        let all = Preferences(enableNotes: true, showItemsInBar: true)
        #expect(all.notchPages == [.items, .todos, .notes])
        let noItemsBar = Preferences(enableNotes: true, showItemsInBar: false)
        #expect(noItemsBar.notchPages == [.todos, .notes])
        let notesOnly = Preferences(enableMenuBarItems: false, enableTodos: false, enableNotes: true)
        #expect(notesOnly.notchPages == [.notes])
    }

    @Test func steppingGoesRoundPastEitherEnd() {
        let pages: [NotchPage] = [.items, .todos, .notes]
        #expect(NotchPage.items.stepped(by: 1, in: pages) == .todos)
        #expect(NotchPage.notes.stepped(by: 1, in: pages) == .items)
        #expect(NotchPage.items.stepped(by: -1, in: pages) == .notes)
        #expect(NotchPage.todos.stepped(by: -1, in: pages) == .items)
    }

    @Test func steppingFromAPageThatIsOffLandsOnTheFirst() {
        #expect(NotchPage.items.stepped(by: 1, in: [.todos, .notes]) == .todos)
        #expect(NotchPage.items.stepped(by: 1, in: []) == nil)
    }

    @Test func aSinglePageStepsOntoItself() {
        #expect(NotchPage.notes.stepped(by: 1, in: [.notes]) == .notes)
    }
}

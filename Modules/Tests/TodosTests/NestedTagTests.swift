import Testing

@testable import Todos

@Suite @MainActor struct NestedTagTests {
    @Test func aFilterFindsTheTagsNestedUnderIt() {
        let page = TodoPage()
        let general = Todo(line: 0, text: "A #work", isDone: false)
        let nested = Todo(line: 1, text: "B #work/bouncer", isDone: false)
        page.todos = [general, nested, Todo(line: 2, text: "C #workshop", isDone: false)]
        page.filters = ["work"]
        #expect(page.rows == [general, nested])
        #expect(page.count(of: "work") == 2)
        page.filters = ["work", "work/bouncer"]
        #expect(page.rows == [nested])
    }

    @Test func nestedTagsAreOfferedOnceTheTagAboveThemIsSelected() {
        let page = TodoPage()
        page.categories = ["home"]
        page.todos = [
            Todo(line: 0, text: "A #work/bouncer", isDone: false),
            Todo(line: 1, text: "B #work/infra #home", isDone: false)
        ]
        #expect(page.tags == ["home", "work", "work/bouncer", "work/infra"])
        #expect(page.chipTags == ["home", "work"])
        page.toggleFilter("work")
        #expect(page.chipTags == ["work", "work/bouncer", "work/infra", "home"])
        page.toggleFilter("work/bouncer")
        #expect(page.chipTags == ["work", "work/bouncer"])
        page.toggleFilter("work")
        #expect(page.filters.isEmpty)
    }

    @Test func aNestedCategoryNoTodoCarriesIsOfferedUnderItsTag() {
        let page = TodoPage()
        page.categories = ["tag/some"]
        #expect(page.chipTags == ["tag"])
        page.toggleFilter("tag")
        #expect(page.chipTags == ["tag", "tag/some"])
    }

    @Test func anAddedTodoTakesOnlyTheDeepestFilter() {
        let page = TodoPage()
        var added: [String] = []
        page.onAdd = { added.append($0) }
        page.filters = ["work", "work/bouncer"]
        page.draft = "Ship"
        page.add()
        page.filters = ["work"]
        page.draft = "Plan #work/infra"
        page.add()
        #expect(added == ["Ship #work/bouncer", "Plan #work/infra"])
    }

    @Test func deletingATagsChipDeletesTheCategoriesNestedUnderIt() {
        let page = TodoPage()
        page.categories = ["work/bouncer", "work/infra", "workshop"]
        #expect(page.categories(under: "work") == ["work/bouncer", "work/infra"])
        #expect(page.categories(under: "work/infra") == ["work/infra"])
        #expect(page.categories(under: "home").isEmpty)
    }

    @Test func aNestedTagTakesTheColourAboveItUnlessItHasItsOwn() {
        let page = TodoPage()
        page.tagColors = ["work": TagColor.blue.rawValue, "work/infra": TagColor.red.rawValue]
        #expect(page.color(of: "work/bouncer/ui") == TagColor.blue.color)
        #expect(page.color(of: "work/infra") == TagColor.red.color)
    }

    @Test func movingAChipReordersTheTags() {
        let page = TodoPage()
        page.categories = ["a", "b", "c"]
        page.moveTag("a", onto: "c")
        #expect(page.tags == ["b", "c", "a"])
    }
}

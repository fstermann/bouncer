import CoreGraphics
import Testing

@testable import Todos

@Suite @MainActor struct TodoPageTests {
    private let todos = [
        Todo(line: 0, text: "A", isDone: false),
        Todo(line: 1, text: "B", isDone: true),
        Todo(line: 2, text: "C", isDone: true)
    ]

    @Test func justTickedTodosStayInPlaceUntilTheyStopLingering() {
        let page = TodoPage()
        page.todos = todos
        page.lingering = [todos[1]]
        #expect(page.open == [todos[0], todos[1]])
        #expect(page.done == [todos[2]])
        page.lingering = []
        #expect(page.open == [todos[0]])
    }

    @Test func aDoneTodoBeingEditedStaysUntilTheEditEnds() {
        let page = TodoPage()
        page.todos = todos
        page.startEditing(todos[1])
        #expect(page.open == [todos[0], todos[1]])
        #expect(page.done == [todos[2]])
        page.editing = nil
        #expect(page.open == [todos[0]])
    }

    @Test func doneTodosAreListedOnlyOnRequest() {
        let page = TodoPage()
        page.todos = todos
        #expect(page.rows == [todos[0]])
        page.showsDone = true
        #expect(page.rows == todos)
    }

    @Test func tagsOnlyDoneTodosCarryShowWithThem() {
        let page = TodoPage()
        page.categories = ["work"]
        page.todos = [Todo(line: 0, text: "A #home", isDone: false), Todo(line: 1, text: "B #old", isDone: true)]
        #expect(page.tags == ["work", "home"])
        page.showsDone = true
        #expect(page.tags == ["work", "home", "old"])
    }

    @Test func filtersShowTodosCarryingAllOfThem() {
        let page = TodoPage()
        let both = Todo(line: 0, text: "A #work #urgent", isDone: false)
        let work = Todo(line: 1, text: "B #work", isDone: false)
        page.todos = [both, work, Todo(line: 2, text: "C", isDone: false)]
        page.filters = ["work"]
        #expect(page.rows == [both, work])
        page.filters = ["work", "urgent"]
        #expect(page.rows == [both])
    }

    @Test func selectedFiltersLeadTheChips() {
        let page = TodoPage()
        page.categories = ["a", "b", "c", "d"]
        page.filters = ["c", "b"]
        #expect(page.chipTags == ["b", "c", "a", "d"])
    }

    @Test func anAddedTodoTakesTheFiltersItLacks() {
        let page = TodoPage()
        var added: String?
        page.onAdd = { added = $0 }
        page.filters = ["work", "urgent"]
        page.draft = "Call bank #work\nfee"
        page.add()
        #expect(added == "Call bank #work #urgent\nfee")
        #expect(page.draft.isEmpty)
    }

    @Test func tagCountsCoverListedTodosWhateverTheFilters() {
        let page = TodoPage()
        page.todos = [
            Todo(line: 0, text: "A #work #urgent", isDone: false),
            Todo(line: 1, text: "B #work", isDone: false),
            Todo(line: 2, text: "C", isDone: false),
            Todo(line: 3, text: "D #work", isDone: true)
        ]
        page.filters = ["urgent"]
        #expect(page.count(of: "work") == 2)
        #expect(page.untaggedCount == 1)
        page.showsDone = true
        #expect(page.count(of: "work") == 3)
    }

    @Test func theUntaggedFilterExcludesTagFilters() {
        let page = TodoPage()
        let untagged = Todo(line: 1, text: "B", isDone: false)
        page.todos = [Todo(line: 0, text: "A #work", isDone: false), untagged]
        page.toggleFilter("work")
        page.toggleUntagged()
        #expect(page.filters.isEmpty)
        #expect(page.rows == [untagged])
        page.toggleFilter("work")
        #expect(!page.showsUntagged)
        #expect(page.filters == ["work"])
    }

    @Test func untaggedIsOfferedOnlyBesideTagsWhileATodoHasNone() {
        let page = TodoPage()
        page.todos = [Todo(line: 0, text: "A", isDone: false)]
        #expect(!page.offersUntagged)
        page.categories = ["work"]
        #expect(page.offersUntagged)
        page.todos = [Todo(line: 0, text: "A #work", isDone: false)]
        #expect(!page.offersUntagged)
    }

    @Test func editingAnotherTodoSavesTheFirst() {
        let page = TodoPage()
        var saved: String?
        page.onEdit = { _, text, _ in saved = text }
        page.startEditing(Todo(line: 0, text: "A", isDone: false))
        page.editDraft = "A changed"
        let other = Todo(line: 1, text: "B", isDone: false)
        page.startEditing(other)
        #expect(saved == "A changed")
        #expect(page.editing == other)
    }

    @Test func tickingTheTodoBeingEditedSavesItFirst() {
        let page = TodoPage()
        var toggled: Todo?
        page.onEdit = { todo, text, note in
            page.todos = [Todo(line: todo.line, text: text, isDone: false, note: note)]
        }
        page.onToggle = { toggled = $0 }
        let todo = Todo(line: 3, text: "A", isDone: false)
        page.todos = [todo]
        page.startEditing(todo)
        page.editDraft = "A changed"
        page.toggleEditing()
        #expect(toggled?.text == "A changed")
        #expect(page.editing == nil)
    }

    @Test func settingTheDueDayKeepsTheRestOfTheTodo() {
        let page = TodoPage()
        var saved: (String, String)?
        page.onEdit = { _, text, note in saved = (text, note) }
        let todo = Todo(line: 0, text: "Call bank #work 📅 2026-10-20", isDone: false, note: "fee")
        page.setDue(of: todo, to: "2026-10-24")
        #expect(saved?.0 == "Call bank #work 📅 2026-10-24")
        #expect(saved?.1 == "fee")
    }

    @Test func togglingATagAddsOrRemovesItAlone() {
        let page = TodoPage()
        var saved: String?
        page.onEdit = { _, text, _ in saved = text }
        let todo = Todo(line: 0, text: "Call bank #work 📅 2026-10-20", isDone: false)
        page.toggleTag("home", of: todo)
        #expect(saved == "Call bank #work #home 📅 2026-10-20")
        page.toggleTag("work", of: todo)
        #expect(saved == "Call bank 📅 2026-10-20")
    }

    @Test func savingAnEditKeepsTheDoneDayAndTakesTypedTags() {
        let page = TodoPage()
        var saved: (String, String)?
        page.onEdit = { _, text, note in saved = (text, note) }
        page.startEditing(Todo(line: 0, text: "Call bank #work ✅ 2026-10-20", isDone: true, note: "fee"))
        #expect(page.editDraft == "Call bank #work\nfee")
        page.editDraft = "Call the bank #home\nfee\ncard"
        page.editDue = "2026-10-24"
        page.saveEdit()
        #expect(saved?.0 == "Call the bank #home 📅 2026-10-24 ✅ 2026-10-20")
        #expect(saved?.1 == "fee\ncard")
        #expect(page.editing == nil)
    }

    @Test func tagsTypedIntoTheTitleBeingEditedAreCompleted() {
        let page = TodoPage()
        page.categories = ["work", "home"]
        page.startEditing(Todo(line: 0, text: "Call bank #home", isDone: false, note: "fee"))
        page.editDraft = "Call bank #home #wo\nfee"
        #expect(page.suggestions == ["work"])
        page.complete(with: "work")
        #expect(page.editDraft == "Call bank #home #work \nfee")
    }

    @Test func aRowMenuHangsUnderItsIconAndStaysOnThePanel() {
        let panel = CGRect(x: 100, y: 500, width: 380, height: 200)
        let size = CGSize(width: 120, height: 150)
        let row = RowMenu(line: 0, kind: .due)
        let menu = row.frame(size: size, under: CGRect(x: 330, y: 160, width: 16, height: 16), in: panel)
        #expect(menu == CGRect(x: 100 + 346 - 120, y: 700 - 180 - 150, width: 120, height: 150))
        let nearLeft = row.frame(size: size, under: CGRect(x: 20, y: 0, width: 16, height: 16), in: panel)
        #expect(nearLeft.minX == 108)
        let field = CGRect(x: 14, y: 160, width: 300, height: 16)
        #expect(RowMenu(line: nil, kind: .suggestions).frame(size: size, under: field, in: panel).minX == 114)
    }
}

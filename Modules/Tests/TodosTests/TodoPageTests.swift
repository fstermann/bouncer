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

    @Test func doneTodosAreListedOnlyOnRequest() {
        let page = TodoPage()
        page.todos = todos
        #expect(page.rows == [todos[0]])
        page.showsDone = true
        #expect(page.rows == todos)
    }

    @Test func savingAnEditKeepsTheDoneDayAndAddsTypedTags() {
        let page = TodoPage()
        var saved: (String, String)?
        page.onEdit = { _, text, note in saved = (text, note) }
        page.startEditing(Todo(line: 0, text: "Call bank #work ✅ 2026-10-20", isDone: true, note: "fee"))
        #expect(page.editDraft == "Call bank\nfee")
        page.editDraft = "Call the bank #home\nfee\ncard"
        page.editTags = []
        page.editDue = "2026-10-24"
        page.saveEdit()
        #expect(saved?.0 == "Call the bank #home 📅 2026-10-24 ✅ 2026-10-20")
        #expect(saved?.1 == "fee\ncard")
        #expect(page.editing == nil)
    }
}

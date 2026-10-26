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

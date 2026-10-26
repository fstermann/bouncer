import Foundation
import Testing

@testable import Todos

@Suite struct TodoListTests {
    private let file = """
        # Inbox
        - [ ] Buy milk
        Some note
          - [x] Call Anna ✅ 2026-10-20
        * [X] Pay rent
        - [] not a task
        """

    @Test func parsesTaskLinesOnly() {
        let todos = TodoList.parse(file)
        #expect(todos == [
            Todo(line: 1, text: "Buy milk", isDone: false),
            Todo(line: 3, text: "Call Anna ✅ 2026-10-20", isDone: true),
            Todo(line: 4, text: "Pay rent", isDone: true)
        ])
    }

    @Test func indentedLinesUnderATaskAreItsNote() {
        let todos = TodoList.parse("""
            - [ ] Call bank
                ask about the fee
                and the card
            - [ ] Next
            \t- [ ] Subtask, not a note
            """)
        #expect(todos[0].note == "ask about the fee\nand the card")
        #expect(todos[1].note.isEmpty)
        #expect(todos[2].text == "Subtask, not a note")
    }

    @Test func tickingStampsTheDayAndUntickingRemovesIt() throws {
        let todos = TodoList.parse(file)
        let ticked = try #require(TodoList.toggling(todos[0], in: file, today: "2026-10-21"))
        #expect(ticked.contains("- [x] Buy milk ✅ 2026-10-21"))
        let unticked = try #require(TodoList.toggling(todos[1], in: file, today: "2026-10-21"))
        #expect(unticked.contains("  - [ ] Call Anna\n"))
        #expect(unticked.components(separatedBy: "\n").count == file.components(separatedBy: "\n").count)
    }

    @Test func togglingRefusesALineThatChanged() {
        let stale = Todo(line: 1, text: "Buy oat milk", isDone: false)
        #expect(TodoList.toggling(stale, in: file, today: "2026-10-21") == nil)
        #expect(TodoList.toggling(Todo(line: 40, text: "Gone", isDone: false), in: file, today: "2026-10-21") == nil)
    }

    @Test func replacingRewritesTheTextAndNoteAndKeepsTheBox() throws {
        let markdown = "# Inbox\n  - [x] Call bank\n      old note\n      more\n- [ ] Next\n"
        let todo = try #require(TodoList.parse(markdown).first)
        let edited = try #require(TodoList.replacing(todo, with: "Call the bank #work", note: "new", in: markdown))
        #expect(edited == "# Inbox\n  - [x] Call the bank #work\n      new\n- [ ] Next\n")
        let cleared = try #require(TodoList.replacing(todo, with: "Call bank", note: "", in: markdown))
        #expect(cleared == "# Inbox\n  - [x] Call bank\n- [ ] Next\n")
    }

    @Test func replacingRefusesALineThatChanged() {
        let stale = Todo(line: 1, text: "Buy oat milk", isDone: false)
        #expect(TodoList.replacing(stale, with: "Buy milk", note: "", in: file) == nil)
    }

    @Test func removingTakesTheTasksAndTheirNotesOut() {
        let markdown = "# Inbox\n- [ ] Call bank\n    fee\n- [ ] Next\n- [x] Old\n"
        let todos = TodoList.parse(markdown)
        #expect(TodoList.removing([todos[0], todos[2]], from: markdown) == "# Inbox\n- [ ] Next\n")
    }

    @Test func removingLeavesALineThatChanged() {
        let markdown = "- [ ] Call bank\n"
        #expect(TodoList.removing([Todo(line: 0, text: "Call the bank", isDone: false)], from: markdown) == markdown)
    }

    @Test func appendingAddsAnOpenTaskOnItsOwnLine() {
        #expect(TodoList.appending("Water plants", to: "- [ ] A") == "- [ ] A\n- [ ] Water plants\n")
        #expect(TodoList.appending("Water plants", to: "- [ ] A\n") == "- [ ] A\n- [ ] Water plants\n")
        #expect(TodoList.appending("Water plants", to: "") == "- [ ] Water plants\n")
    }

    @Test func appendingWritesLaterLinesAsTheNote() {
        let added = TodoList.appending("Call bank\nask about the fee\n\n", to: "")
        #expect(added == "- [ ] Call bank\n    ask about the fee\n")
        #expect(TodoList.parse(added).first?.note == "ask about the fee")
    }

    @Test func appendingNothingChangesNothing() {
        #expect(TodoList.appending("   ", to: "- [ ] A\n") == "- [ ] A\n")
    }

    @Test func taskFromADraftDatesItsFirstLine() {
        #expect(TodoList.task(from: "Call bank #work\nnote", due: "2026-10-24") == "Call bank #work 📅 2026-10-24\nnote")
        #expect(TodoList.task(from: "Call bank #work ", due: nil) == "Call bank #work")
    }
}

@Suite struct TaskTextTests {
    @Test func writesItselfBackWithTagsAndDatesLast() {
        var text = TaskText("Call #work bank ✅ 2026-10-21")
        #expect(text.done == "2026-10-21")
        text.due = "2026-10-24"
        text.tags.append("home")
        #expect(text.text == "Call bank #work #home 📅 2026-10-24 ✅ 2026-10-21")
    }

    @Test func takesTagsAndDatesOutOfTheTitle() {
        let text = TaskText("Call #work bank 📅 2026-10-24 ✅ 2026-10-21 ## heading")
        #expect(text.title == "Call bank ## heading")
        #expect(text.tags == ["work"])
        #expect(text.due == "2026-10-24")
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// 2026-10-21 is a Wednesday.
    private func day(_ string: String) -> Date {
        TaskDay.date(from: string, calendar: calendar) ?? .distantPast
    }

    @Test func thisWeekIsFriday() {
        #expect(TaskDay.string(for: .thisWeek, today: day("2026-10-21"), calendar: calendar) == "2026-10-23")
        #expect(TaskDay.string(for: .thisWeek, today: day("2026-10-23"), calendar: calendar) == "2026-10-23")
        #expect(TaskDay.string(for: .thisWeek, today: day("2026-10-24"), calendar: calendar) == "2026-10-30")
        #expect(TaskDay.string(for: .tomorrow, today: day("2026-10-31"), calendar: calendar) == "2026-11-01")
    }

    @Test func labelsNameNearDaysAndFlagThePast() {
        let today = day("2026-10-21")
        #expect(TaskDay.label(for: "2026-10-21", today: today, calendar: calendar) == ("Today", false))
        #expect(TaskDay.label(for: "2026-10-22", today: today, calendar: calendar) == ("Tomorrow", false))
        #expect(TaskDay.label(for: "2026-10-23", today: today, calendar: calendar) == ("Fri", false))
        #expect(TaskDay.label(for: "2026-11-30", today: today, calendar: calendar) == ("Nov 30", false))
        #expect(TaskDay.label(for: "2026-10-20", today: today, calendar: calendar) == ("Yesterday", true))
    }
}

@Suite struct CategoriesTests {
    @Test func readsABlockOrInlineList() {
        let block = "---\ntitle: Inbox\ncategories:\n  - work\n  - \"home\"\n---\n- [ ] A"
        #expect(Categories.parse(block) == ["work", "home"])
        #expect(Categories.parse("---\ncategories: [work, #home]\n---\n") == ["work", "home"])
        #expect(Categories.parse("- [ ] A\n---\ncategories: [work]\n---").isEmpty)
    }

    @Test func addingCreatesTheFrontmatterOrExtendsTheList() {
        #expect(Categories.adding("work", to: "- [ ] A\n") == "---\ncategories:\n  - work\n---\n- [ ] A\n")
        #expect(Categories.adding("home", to: "---\ncategories:\n  - work\n---\n- [ ] A")
                == "---\ncategories:\n  - work\n  - home\n---\n- [ ] A")
        #expect(Categories.adding("home", to: "---\ntitle: x\n---\n") == "---\ntitle: x\ncategories:\n  - home\n---\n")
        #expect(Categories.adding("home", to: "---\ncategories: [work]\n---\n")
                == "---\ncategories: [work, home]\n---\n")
    }

    @Test func addingAnExistingCategoryChangesNothing() {
        let file = "---\ncategories:\n  - work\n---\n"
        #expect(Categories.adding("#work", to: file) == file)
    }
}

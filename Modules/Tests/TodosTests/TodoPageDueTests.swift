import Foundation
import Testing

@testable import Todos

@Suite @MainActor struct TodoPageDueTests {
    @Test func typingTwoSlashesOpensTheDueChoicesWithNothingTaken() {
        let page = TodoPage()
        page.draft = "Call bank //"
        page.followDueQuery()
        #expect(page.menu == RowMenu(line: nil, kind: .due))
        #expect(page.dueQuery == "")
        #expect(page.highlightedDue == nil)
        #expect(page.draft == "Call bank //")
    }

    @Test func aDayTypedAfterTwoSlashesIsTakenAndTheSlashesGo() {
        let page = TodoPage()
        page.draft = "Call bank //tom"
        page.followDueQuery()
        let tomorrow = TaskDay.string(for: .tomorrow, today: Date())
        #expect(page.highlightedDue == tomorrow)
        page.chooseDue(tomorrow, closing: true)
        #expect(page.draft == "Call bank ")
        #expect(page.draftDue == tomorrow)
        #expect(page.menu == nil)
    }

    @Test func theArrowsStepFromTheTypedDay() {
        let page = TodoPage()
        page.draft = "Call bank //"
        page.followDueQuery()
        page.stepDue(by: 1)
        #expect(page.highlightedDue == TaskDay.string(for: .today, today: Date()))
        page.stepDue(by: -1)
        #expect(page.highlightedDue == TaskDay.string(for: .thisWeek, today: Date()))
    }

    @Test func leavingTheSlashesClosesTheChoices() {
        let page = TodoPage()
        page.draft = "Call bank //14"
        page.followDueQuery()
        page.draft = "Call bank //14 "
        page.followDueQuery()
        #expect(page.menu == nil)
        #expect(page.dueQuery == nil)
    }
}

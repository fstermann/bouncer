import Foundation
import Testing

@testable import Todos

@Suite struct ReminderTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test func aTimedOpenTodoIsRemindedOfAtItsTime() {
        let todos = [
            Todo(line: 0, text: "Call Anna 📅 2026-11-08 ⏰ 14:00", isDone: false),
            Todo(line: 1, text: "Pay rent 📅 2026-11-08", isDone: false),
            Todo(line: 2, text: "Done 📅 2026-11-08 ⏰ 09:00 ✅ 2026-11-08", isDone: true)
        ]
        let reminders = Reminder.todos(todos, calendar: calendar)
        #expect(reminders.map(\.title) == ["Call Anna"])
        #expect(reminders.first?.shows == at(14))
        #expect(ReminderSchedule.showing(reminders, at: at(13, 59), dismissed: []).isEmpty)
        #expect(ReminderSchedule.showing(reminders, at: at(14), dismissed: []).count == 1)
    }

    @Test func aPlannedMeetingIsRemindedOfFiveMinutesAheadUntilFiveMinutesIn() {
        let note = Note(name: "2026-11-08 1400 Sync.md", markdown: "", created: at(9), calendar: calendar)
        let reminders = Reminder.meetings([note], calendar: calendar)
        #expect(reminders.first?.title == "Sync")
        #expect(reminders.first?.detail == "14:00")
        #expect(ReminderSchedule.showing(reminders, at: at(13, 54), dismissed: []).isEmpty)
        #expect(ReminderSchedule.showing(reminders, at: at(13, 55), dismissed: []).count == 1)
        #expect(ReminderSchedule.showing(reminders, at: at(14, 5), dismissed: []).isEmpty)
    }

    @Test func aMeetingNotedAsItBeginsIsNoPlan() {
        let note = Note(name: "2026-11-08 1400 Sync.md", markdown: "", created: at(14), calendar: calendar)
        #expect(Reminder.meetings([note], calendar: calendar).isEmpty)
    }

    @Test func aDismissedReminderStaysAwayAndNoLongerSchedules() {
        let todos = [Todo(line: 0, text: "Call 📅 2026-11-08 ⏰ 14:00", isDone: false)]
        let reminders = Reminder.todos(todos, calendar: calendar)
        let id = reminders[0].id
        #expect(ReminderSchedule.showing(reminders, at: at(15), dismissed: [id]).isEmpty)
        #expect(ReminderSchedule.nextChange(reminders, after: at(13), dismissed: [id]) == nil)
    }

    @Test func theNextChangeIsTheSoonestStartOrEnd() {
        let todos = [
            Todo(line: 0, text: "A 📅 2026-11-08 ⏰ 14:00", isDone: false),
            Todo(line: 1, text: "B 📅 2026-11-08 ⏰ 11:00", isDone: false)
        ]
        let reminders = Reminder.todos(todos, calendar: calendar)
        #expect(ReminderSchedule.nextChange(reminders, after: at(10), dismissed: []) == at(11))
        #expect(ReminderSchedule.nextChange(reminders, after: at(11), dismissed: []) == at(14))
        #expect(ReminderSchedule.showing(reminders, at: at(15), dismissed: []).map(\.title) == ["B", "A"])
    }

    @Test func movingATodoToAnotherTimeRemindsOfItAgain() {
        let before = Reminder.todos([Todo(line: 0, text: "A 📅 2026-11-08 ⏰ 14:00", isDone: false)], calendar: calendar)
        let after = Reminder.todos([Todo(line: 0, text: "A 📅 2026-11-08 ⏰ 16:00", isDone: false)], calendar: calendar)
        #expect(before[0].id != after[0].id)
    }
}

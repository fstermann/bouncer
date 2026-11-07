import Foundation
import Settings

/// Something to bring up beside the notch at a time: a timed todo, a planned meeting about to start,
/// or Claude's answer having arrived.
public struct Reminder: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case todo, meeting, claude }

    /// What it is about, and when for, so a todo moved to another time is reminded of again.
    public let id: String
    public let kind: Kind
    public let title: String
    /// A time, or what happened.
    public let detail: String
    public let shows: Date
    /// When it goes by itself; `nil` for not until it is dismissed.
    public let ends: Date?
    /// The note a meeting's reminder opens.
    public let note: String?

    public var page: NotchPage {
        switch kind {
        case .todo: .todos
        case .meeting: .notes
        case .claude: .claude
        }
    }

    /// How long before a planned meeting it is reminded of, and how long after its start it still is.
    static let meetingLead: TimeInterval = 5 * 60
    static let meetingGrace: TimeInterval = 5 * 60
    /// A todo's reminder missed while the Mac was off still shows, up to a day late.
    static let todoGrace: TimeInterval = 24 * 60 * 60

    /// The open todos with a time, each shown from that time.
    static func todos(_ todos: [Todo], calendar: Calendar = .current) -> [Reminder] {
        todos.filter { !$0.isDone }.compactMap { todo in
            let text = TaskText(todo.text)
            guard let due = text.due, let time = text.time,
                  let at = TaskTime.date(day: due, time: time, calendar: calendar)
            else { return nil }
            return Reminder(
                id: "todo:\(todo.text)", kind: .todo, title: text.title, detail: time, shows: at,
                ends: at.addingTimeInterval(todoGrace), note: nil
            )
        }
    }

    /// Meetings planned ahead, shown a few minutes before they start. A note created after that point,
    /// such as one started as its meeting begins, is not a plan and is not reminded of.
    static func meetings(_ notes: [Note], calendar: Calendar = .current) -> [Reminder] {
        notes.compactMap { note in
            guard let start = note.start else { return nil }
            let shows = start.addingTimeInterval(-meetingLead)
            guard note.created.map({ $0 < shows }) ?? true else { return nil }
            let time = TaskTime.string(for: start, calendar: calendar)
            return Reminder(
                id: "meeting:\(note.name)@\(start.timeIntervalSince1970)", kind: .meeting,
                title: note.title.isEmpty ? "Meeting" : note.title, detail: time, shows: shows,
                ends: start.addingTimeInterval(meetingGrace), note: note.name
            )
        }
    }

    static func claude(chat title: String, at now: Date) -> Reminder {
        Reminder(
            id: "claude:\(title)@\(now.timeIntervalSince1970)", kind: .claude, title: title,
            detail: "Claude answered", shows: now, ends: nil, note: nil
        )
    }
}

/// Which reminders show at a moment, and when that next changes. Pure, so it is tested without a clock.
enum ReminderSchedule {
    /// The soonest first.
    static func showing(_ reminders: [Reminder], at now: Date, dismissed: Set<String>) -> [Reminder] {
        reminders
            .filter { !dismissed.contains($0.id) && $0.shows <= now && $0.ends.map { now < $0 } ?? true }
            .sorted { ($0.shows, $0.id) < ($1.shows, $1.id) }
    }

    /// The next moment a reminder starts or stops showing, after `now`.
    static func nextChange(_ reminders: [Reminder], after now: Date, dismissed: Set<String>) -> Date? {
        reminders.filter { !dismissed.contains($0.id) }
            .flatMap { [$0.shows, $0.ends].compactMap(\.self) }
            .filter { $0 > now }
            .min()
    }
}

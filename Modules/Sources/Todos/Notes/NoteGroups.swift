import Foundation

/// The notes under headings by when they took place, latest first: today, yesterday, the other days
/// of this week by name, then by month.
enum NoteGroups {
    struct Group: Equatable {
        let title: String
        let notes: [Note]
    }

    static func grouped(_ notes: [Note], now: Date, calendar: Calendar = .current) -> [Group] {
        let sorted = notes.sorted { ($0.day ?? .distantPast, $1.name) > ($1.day ?? .distantPast, $0.name) }
        let titles = Titles(now: now, calendar: calendar)
        var groups: [(title: String, notes: [Note])] = []
        for note in sorted {
            let title = titles.title(for: note.day)
            if groups.last?.title == title {
                groups[groups.count - 1].notes.append(note)
            } else {
                groups.append((title, [note]))
            }
        }
        return groups.map { Group(title: $0.title, notes: $0.notes) }
    }

    static func title(for day: Date?, now: Date, calendar: Calendar = .current) -> String {
        Titles(now: now, calendar: calendar).title(for: day)
    }

    /// Its formatters made once for a whole list: one for every note made a long list slow.
    private struct Titles {
        let now: Date
        let calendar: Calendar
        let weekday: DateFormatter
        let month: DateFormatter
        let monthAndYear: DateFormatter

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
            let formatter = { (template: String) in
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = calendar.locale ?? .current
                formatter.timeZone = calendar.timeZone
                formatter.setLocalizedDateFormatFromTemplate(template)
                return formatter
            }
            weekday = formatter("EEEE")
            month = formatter("MMMM")
            monthAndYear = formatter("MMMMyyyy")
        }

        func title(for day: Date?) -> String {
            guard let day else { return "Undated" }
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)
            ).day ?? 0
            if days == 0 { return "Today" }
            if days == 1 { return "Yesterday" }
            let formatter = if days > 1, calendar.isDate(day, equalTo: now, toGranularity: .weekOfYear) {
                weekday
            } else if calendar.isDate(day, equalTo: now, toGranularity: .year) {
                month
            } else {
                monthAndYear
            }
            return formatter.string(from: day)
        }
    }
}

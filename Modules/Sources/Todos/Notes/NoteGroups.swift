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
        var groups: [Group] = []
        for note in sorted {
            let title = title(for: note.day, now: now, calendar: calendar)
            if groups.last?.title == title {
                groups[groups.count - 1] = Group(title: title, notes: groups[groups.count - 1].notes + [note])
            } else {
                groups.append(Group(title: title, notes: [note]))
            }
        }
        return groups
    }

    static func title(for day: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let day else { return "Undated" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days > 1, calendar.isDate(day, equalTo: now, toGranularity: .weekOfYear) {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("MMMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        }
        return formatter.string(from: day)
    }
}

import Foundation

/// `//` typed into a todo, which opens its due choices, and what is typed after it: a date such as
/// `14.10`, or the start of a quick choice such as `tom`.
enum QuickDue {
    /// What follows the `//` the text ends in, `""` straight after it, or `nil` when it does not end in
    /// one: a `//` starts a word, so a link's `https://` is left alone.
    static func query(in text: String) -> String? {
        let word = text.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        guard !text.contains("\n"), word.hasPrefix("//") else { return nil }
        return String(word.dropFirst(2))
    }

    /// `text` without the `//` it ends in and what was typed after it.
    static func removingQuery(from text: String) -> String {
        guard let query = query(in: text) else { return text }
        return String(text.dropLast(query.count + 2))
    }

    /// The quick choice `query` starts the name of, such as `tom` for tomorrow.
    static func choice(for query: String) -> DueChoice? {
        let query = query.lowercased()
        guard !query.isEmpty else { return nil }
        return DueChoices.quick.first { $0.title.lowercased().hasPrefix(query) }?.choice
    }

    /// The day `query` names, `yyyy-MM-dd`: `14.10` or `14.10.26` day first, `2026-10-14`, or `14` for
    /// the day of the month. Without a year or month, the next such day from `today` on.
    static func day(from query: String, today: Date, calendar: Calendar = .current) -> String? {
        let start = calendar.startOfDay(for: today)
        let now = calendar.dateComponents([.year, .month], from: start)
        guard let year = now.year, let month = now.month else { return nil }
        let parts: [Int]
        if query.wholeMatch(of: /\d{4}-\d{1,2}-\d{1,2}/) != nil {
            let numbers = query.split(separator: "-").compactMap { Int($0) }
            parts = [numbers[2], numbers[1], numbers[0]]
        } else if query.wholeMatch(of: /\d{1,2}(\.\d{1,2}(\.(\d{2}|\d{4})?)?)?\.?/) != nil {
            parts = query.split(separator: ".").compactMap { Int($0) }
        } else {
            return nil
        }
        let candidates: [DateComponents] = switch parts.count {
        case 1: [DateComponents(year: year, month: month, day: parts[0]),
                 DateComponents(year: year, month: month + 1, day: parts[0])]
        case 2: [DateComponents(year: year, month: parts[1], day: parts[0]),
                 DateComponents(year: year + 1, month: parts[1], day: parts[0])]
        default: [DateComponents(year: parts[2] < 100 ? 2000 + parts[2] : parts[2], month: parts[1], day: parts[0])]
        }
        let date = candidates.compactMap { components -> Date? in
            // A day the month does not have, such as the 31st of November, would roll into the next.
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == components.day
            else { return nil }
            return date
        }.first { parts.count == 3 || $0 >= start }
        return date.map { TaskDay.string(for: $0, calendar: calendar) }
    }
}

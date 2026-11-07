import Foundation

/// A todo's text taken apart the way the Tasks plugin reads it: the words, its `#tags`, and the
/// dates written after `📅` (due) and `✅` (done), with the time of day it is due after `⏰`.
public struct TaskText: Equatable, Sendable {
    public var title: String
    public var tags: [String]
    /// `yyyy-MM-dd`, which sorts the same as the days it names.
    public var due: String?
    /// `HH:mm` on the due day, which a reminder shows at.
    public var time: String?
    public var done: String?

    public init(_ text: String) {
        var words: [String] = []
        var tags: [String] = []
        var due: String?
        var time: String?
        var done: String?
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)[...]
        while let token = tokens.popFirst() {
            if token == "📅" || token == "✅", let date = tokens.first, Self.isDay(date) {
                tokens.removeFirst()
                if token == "📅" { due = date } else { done = date }
            } else if token == "⏰", let next = tokens.first, let clock = TaskTime.normalized(next) {
                tokens.removeFirst()
                time = clock
            } else if token.count > 1, token.hasPrefix("#"), !token.dropFirst().hasPrefix("#") {
                tags.append(String(token.dropFirst()))
            } else {
                words.append(token)
            }
        }
        title = words.joined(separator: " ")
        self.tags = tags
        self.due = due
        self.time = time
        self.done = done
    }

    /// Back as a todo's text: the words, then the tags and the dates, as a todo added here writes them.
    public var text: String {
        let dates = [due.map { "📅 \($0)" }, time.map { "⏰ \($0)" }, done.map { "✅ \($0)" }].compactMap(\.self)
        return ([title] + tags.map { "#\($0)" } + dates).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func isDay(_ token: String) -> Bool {
        token.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
    }
}

/// When a todo is due, as offered when adding one.
public enum DueChoice: Hashable, Sendable {
    case today
    case tomorrow
    /// This week's Friday, the end of the work week; next week's once this one's has passed.
    case thisWeek
    case day(Date)
}

/// Days as the todo file writes them, `yyyy-MM-dd`, and as the page shows them.
public enum TaskDay {
    public static func string(for choice: DueChoice, today: Date, calendar: Calendar = .current) -> String {
        let day: Date = switch choice {
        case .today: today
        case .tomorrow: calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .thisWeek: calendar.date(byAdding: .day, value: daysToFriday(from: today, calendar: calendar), to: today)
            ?? today
        case .day(let date): date
        }
        return string(for: day, calendar: calendar)
    }

    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "Today", "Tomorrow", a weekday within the coming week, or a date, then the time if there is one;
    /// and whether it has passed.
    public static func label(
        for due: String, time: String? = nil, today: Date, calendar: Calendar = .current
    ) -> (text: String, isOverdue: Bool) {
        let day = dayLabel(for: due, today: today, calendar: calendar)
        guard let time else { return day }
        let isPast = day.isOverdue
            || due == string(for: today, calendar: calendar) && time <= TaskTime.string(for: today, calendar: calendar)
        return ("\(day.text) \(time)", isPast)
    }

    private static func dayLabel(
        for due: String, today: Date, calendar: Calendar
    ) -> (text: String, isOverdue: Bool) {
        let todayString = string(for: today, calendar: calendar)
        guard let date = date(from: due, calendar: calendar),
              let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: date).day
        else { return (due, false) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        let text: String
        switch days {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case -1: text = "Yesterday"
        case 2...6: formatter.setLocalizedDateFormatFromTemplate("EEE"); text = formatter.string(from: date)
        default: formatter.setLocalizedDateFormatFromTemplate("MMMd"); text = formatter.string(from: date)
        }
        return (text, due < todayString)
    }

    static func date(from day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Friday is weekday 6 in the Gregorian numbering, whatever day the locale starts the week on.
    private static func daysToFriday(from today: Date, calendar: Calendar) -> Int {
        (6 - calendar.component(.weekday, from: today) + 7) % 7
    }
}

/// Times of day as the todo file writes them, `HH:mm`.
public enum TaskTime {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// `9:05` as `09:05`; `nil` for anything that is not a time of day.
    static func normalized(_ token: String) -> String? {
        guard let match = token.wholeMatch(of: /(\d{1,2}):(\d{2})/),
              let hour = Int(match.1), let minute = Int(match.2), hour < 24, minute < 60
        else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// The moment `time` names on `day`, both as the file writes them.
    static func date(day: String, time: String, calendar: Calendar = .current) -> Date? {
        guard let start = TaskDay.date(from: day, calendar: calendar), let clock = normalized(time) else { return nil }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: start)
    }

    /// `time` on `day` as a `Date`, for a picker to show; `day` itself while there is no time.
    static func date(for time: String?, on day: Date, calendar: Calendar = .current) -> Date {
        time.flatMap { date(day: TaskDay.string(for: day, calendar: calendar), time: $0, calendar: calendar) } ?? day
    }
}

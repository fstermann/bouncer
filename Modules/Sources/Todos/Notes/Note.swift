import Foundation

/// A meeting note: one Markdown file in the notes folder, what the meeting was in its properties,
/// which Obsidian shows and Dataview queries, and the note itself under them.
///
/// The title is the file's name, after the day and time it starts with, as Obsidian takes a note's
/// title from its name. A note with a project is kept in the project's folder, nested as `Work/Bouncer`
/// is. People and the project are written as links too, so a vault's graph and backlinks join each
/// meeting to them; plain names read just as well.
struct Note: Hashable, Identifiable {
    /// The file's path in the notes folder, `Project/2026-10-29 1400 Sync.md`, which is what knows the note.
    var name: String
    var title: String
    var start: Date?
    var end: Date?
    var attendees: [String] = []
    var project: String?
    /// A room, or the call's link.
    var location: String?
    var tags: [String] = []
    var body: String = ""
    /// When the file last changed, which places a note without a start.
    var modified: Date?

    var id: String { name }

    /// When it took place, for ordering and grouping.
    var day: Date? { start ?? modified }
}

extension Note {
    enum Key {
        static let start = "date"
        static let end = "end"
        static let attendees = "attendees"
        static let project = "project"
        static let location = "location"
        static let tags = "tags"
    }

    /// The sections a new note starts with.
    static let template = "## Agenda\n\n\n## Notes\n\n\n## Action items\n\n"

    init(name: String, markdown: String, modified: Date? = nil, calendar: Calendar = .current) {
        let (frontmatter, body) = Frontmatter.split(markdown)
        self.name = name
        title = NoteName.title(of: name)
        start = frontmatter[Key.start]?.value.flatMap { NoteTime.date(from: $0, calendar: calendar) }
            ?? NoteName.start(of: name, calendar: calendar)
        end = frontmatter[Key.end]?.value.flatMap { NoteTime.date(from: $0, calendar: calendar) }
        attendees = frontmatter[Key.attendees]?.values.map(Link.target) ?? []
        project = NoteName.folder(of: name) ?? frontmatter[Key.project]?.value.map(Link.target)
        location = frontmatter[Key.location]?.value
        tags = (frontmatter[Key.tags]?.values ?? [])
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == " " }) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        self.body = body
        self.modified = modified
    }

    /// The file `existing` with this note's properties and text in it. Properties Bouncer does not
    /// know are kept as they are; one of its own is added only once it has a value, and kept empty
    /// rather than dropped once the file has it.
    func markdown(over existing: String, calendar: Calendar = .current) -> String {
        var frontmatter = Frontmatter.split(existing).frontmatter
        let set = { (key: String, values: [String], isList: Bool) in
            guard !values.isEmpty || frontmatter[key] != nil else { return }
            frontmatter.set(Frontmatter.Property(key: key, values: values, isList: isList))
        }
        set(Key.start, [start.map { NoteTime.string(for: $0, calendar: calendar) }].compactMap(\.self), false)
        set(Key.end, [end.map { NoteTime.string(for: $0, calendar: calendar) }].compactMap(\.self), false)
        set(Key.attendees, attendees.map(Link.make), true)
        set(Key.project, [project.map { Link.make(TagPath.leaf(of: $0)) }].compactMap(\.self), false)
        set(Key.location, [location].compactMap(\.self), false)
        set(Key.tags, tags, true)
        return frontmatter.joined(with: body)
    }

    /// Whether it mentions `query` anywhere a meeting would be looked for by: its title, people,
    /// project, place or text.
    func mentions(_ query: String) -> Bool {
        ([title, project, location, body].compactMap(\.self) + attendees)
            .contains { !TextSearch.ranges(of: query, in: $0).isEmpty }
    }
}

/// Obsidian's `[[Note]]` links, and `[[Note|shown as]]`.
enum Link {
    static func target(_ value: String) -> String {
        guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
        let inner = value.dropFirst(2).dropLast(2)
        return String(inner.split(separator: "|", maxSplits: 1).first ?? inner)
    }

    static func make(_ name: String) -> String {
        "[[\(name)]]"
    }
}

/// A note's path: its project's folder, then the day and time it starts and its title, so a folder
/// sorts by when meetings took place.
enum NoteName {
    /// `Project/2026-10-29 1400 Weekly sync.md`, with what a file name or an Obsidian link cannot hold
    /// taken out.
    static func make(title: String, start: Date?, project: String? = nil, calendar: Calendar = .current) -> String {
        let cleaned = clean(title)
        let prefix = start.map { stamp(for: $0, calendar: calendar) + " " } ?? ""
        let file = prefix + (cleaned.isEmpty ? "Meeting" : cleaned) + ".md"
        return folder(for: project).map { "\($0)/\(file)" } ?? file
    }

    /// The folder a note of `project` is kept in, `Work/Bouncer` nested; `nil` for none, or a name with
    /// nothing left once cleaned. Leading dots go too, as they would hide a folder.
    static func folder(for project: String?) -> String? {
        let parts = (project ?? "").split(separator: "/").map { String(clean(String($0)).drop { $0 == "." }) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// The folder `name` is in, `nil` for a note at the top.
    static func folder(of name: String) -> String? {
        let parts = name.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }

    /// `name` without its folder and extension and the day and time it starts with.
    static func title(of name: String) -> String {
        let file = file(of: name)
        let base = file.hasSuffix(".md") ? String(file.dropLast(3)) : file
        guard let match = base.prefixMatch(of: pattern) else { return base }
        let rest = base[match.range.upperBound...]
        return rest.isEmpty ? base : String(rest)
    }

    static func start(of name: String, calendar: Calendar) -> Date? {
        guard let match = file(of: name).prefixMatch(of: pattern) else { return nil }
        let (_, year, month, day, time) = match.output
        let hour = time.flatMap { Int($0.prefix(2)) } ?? 0
        let minute = time.flatMap { Int($0.suffix(2)) } ?? 0
        return calendar.date(from: DateComponents(
            year: Int(year), month: Int(month), day: Int(day), hour: hour, minute: minute
        ))
    }

    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")

    private static func file(of name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    private static func clean(_ text: String) -> String {
        text.unicodeScalars.filter { !forbidden.contains($0) }.map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }
    nonisolated(unsafe) private static let pattern = #/(\d{4})-(\d{2})-(\d{2})(?: (\d{4}))? /#

    private static func stamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }
}

/// Times as a note's properties hold them, `2026-10-29T14:00`, which Obsidian reads as a date and
/// time, and as the page shows them.
enum NoteTime {
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }

    /// Also reads seconds, a space for the `T`, and a day alone.
    static func date(from string: String, calendar: Calendar) -> Date? {
        guard let match = string.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/)
        else { return nil }
        let (_, year, month, day, hour, minute, second) = match.output
        return calendar.date(from: DateComponents(
            year: Int(year), month: Int(month), day: Int(day),
            hour: hour.flatMap { Int($0) } ?? 0, minute: minute.flatMap { Int($0) } ?? 0,
            second: second.flatMap { Int($0) } ?? 0
        ))
    }

    /// `hour`:`minute` on `day`.
    static func at(hour: Int, minute: Int, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Digits typed into a time, split into its hour and as much of its minutes as there is: the first
    /// two digits are the hour while they can be one, so "930" is 9:30. `nil` once no time starts so.
    static func split(_ digits: String) -> (hour: Int, minutes: String)? {
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let isTwoDigitHour = digits.count > 1 && Int(digits.prefix(2)).map { $0 < 24 } == true
        guard let hour = Int(digits.prefix(isTwoDigitHour ? 2 : 1)) else { return nil }
        let minutes = String(digits.dropFirst(isTwoDigitHour ? 2 : 1))
        guard minutes.count <= 2, minutes.first.map({ $0 <= "5" }) ?? true else { return nil }
        return (hour, minutes)
    }

    /// The digits as the field shows them: "14", "14:0", "9:30"; `nil` once no time starts so.
    static func typed(_ digits: String) -> String? {
        guard !digits.isEmpty else { return "" }
        guard let (_, minutes) = split(digits) else { return nil }
        return minutes.isEmpty ? digits : "\(digits.dropLast(minutes.count)):\(minutes)"
    }

    /// The time the digits stand for on `day`, the minutes they lack read as noughts: "14:3" is 14:30.
    static func time(typed digits: String, on day: Date, calendar: Calendar = .current) -> Date? {
        guard let (hour, minutes) = split(digits) else { return nil }
        let minute = Int(minutes.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        return at(hour: hour, minute: minute, on: day, calendar: calendar)
    }

    /// The quarter hour at or before `date`.
    static func quarter(before date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let hour = calendar.component(.hour, from: date)
        return at(hour: hour, minute: minute - minute % 15, on: date, calendar: calendar)
    }

    /// The next quarter hour after `date`, or with `up` false, the one before it.
    static func step(_ date: Date, up: Bool, calendar: Calendar = .current) -> Date {
        let quarter = quarter(before: date, calendar: calendar)
        if up { return quarter.addingTimeInterval(15 * 60) }
        return quarter == date ? date.addingTimeInterval(-15 * 60) : quarter
    }

    /// `date` on `day`, at the same time of day.
    static func moving(_ date: Date, to day: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day
        ) ?? date
    }

    /// "45 min", "1 h", "1 h 30 min"; `nil` for a meeting that has not ended or ended before it began.
    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end, end > start else { return nil }
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }
}

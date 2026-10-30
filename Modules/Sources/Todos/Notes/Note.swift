import Foundation

/// A meeting note: one Markdown file in the notes folder, what the meeting was in its properties,
/// which Obsidian shows and Dataview queries, and the note itself under them.
///
/// The title is the file's name, after the day and time it starts with, as Obsidian takes a note's
/// title from its name. People and the project are written as links, so a vault's graph and
/// backlinks join each meeting to them; plain names read just as well.
struct Note: Hashable, Identifiable {
    /// The file's name in the folder, which is what knows the note.
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
        project = frontmatter[Key.project]?.value.map(Link.target)
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
        set(Key.project, [project.map(Link.make)].compactMap(\.self), false)
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

/// A note's file name: the day and time it starts, then its title, so the folder sorts by when
/// meetings took place.
enum NoteName {
    /// `2026-10-29 1400 Weekly sync.md`, with what a file name or an Obsidian link cannot hold taken out.
    static func make(title: String, start: Date?, calendar: Calendar = .current) -> String {
        let cleaned = title.unicodeScalars.filter { !forbidden.contains($0) }.map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
        let prefix = start.map { stamp(for: $0, calendar: calendar) + " " } ?? ""
        return prefix + (cleaned.isEmpty ? "Meeting" : cleaned) + ".md"
    }

    /// `name` without its extension and the day and time it starts with.
    static func title(of name: String) -> String {
        let base = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        guard let match = base.prefixMatch(of: pattern) else { return base }
        let rest = base[match.range.upperBound...]
        return rest.isEmpty ? base : String(rest)
    }

    static func start(of name: String, calendar: Calendar) -> Date? {
        guard let match = name.prefixMatch(of: pattern) else { return nil }
        let (_, year, month, day, time) = match.output
        let hour = time.flatMap { Int($0.prefix(2)) } ?? 0
        let minute = time.flatMap { Int($0.suffix(2)) } ?? 0
        return calendar.date(from: DateComponents(
            year: Int(year), month: Int(month), day: Int(day), hour: hour, minute: minute
        ))
    }

    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
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

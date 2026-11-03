import Foundation
import Testing

@testable import Todos

@Suite struct NoteTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    private let markdown = """
        ---
        date: 2026-10-29T14:00
        end: 2026-10-29T14:45
        attendees:
          - "[[Anna]]"
          - Ben
        project: "[[Bouncer|the app]]"
        location: https://meet.example.com/abc
        tags:
          - work/bouncer
          - "#1on1"
        status: draft
        ---
        ## Notes
        Shipped it.
        """

    @Test func readsTheMeetingFromItsProperties() {
        let note = Note(name: "2026-10-29 1400 Weekly sync.md", markdown: markdown, calendar: calendar)
        #expect(note.title == "Weekly sync")
        #expect(note.start == date(29, 14))
        #expect(note.end == date(29, 14, 45))
        #expect(note.attendees == ["Anna", "Ben"])
        #expect(note.project == "Bouncer")
        #expect(note.location == "https://meet.example.com/abc")
        #expect(note.tags == ["work/bouncer", "1on1"])
        #expect(note.body == "## Notes\nShipped it.")
    }

    @Test func writesPropertiesBackKeepingTheOnesItDoesNotKnow() {
        var note = Note(name: "2026-10-29 1400 Weekly sync.md", markdown: markdown, calendar: calendar)
        note.attendees.append("Cleo")
        note.body = "Done."
        let written = note.markdown(over: markdown, calendar: calendar)
        #expect(written == """
            ---
            date: 2026-10-29T14:00
            end: 2026-10-29T14:45
            attendees:
              - "[[Anna]]"
              - "[[Ben]]"
              - "[[Cleo]]"
            project: "[[Bouncer]]"
            location: https://meet.example.com/abc
            tags:
              - work/bouncer
              - 1on1
            status: draft
            ---
            Done.
            """)
        #expect(Note(name: note.name, markdown: written, calendar: calendar).attendees == ["Anna", "Ben", "Cleo"])
    }

    @Test func addsOnlyPropertiesThatHaveAValue() {
        let note = Note(name: "Standup.md", title: "Standup", start: date(29, 9, 30), tags: ["daily"], body: "Hi")
        #expect(note.markdown(over: "", calendar: calendar) == """
            ---
            date: 2026-10-29T09:30
            tags:
              - daily
            ---
            Hi
            """)
    }

    @Test func keepsAPropertyItHasEmptiedRatherThanDroppingIt() {
        var note = Note(name: "a.md", markdown: "---\nproject: X\n---\n", calendar: calendar)
        note.project = nil
        #expect(note.markdown(over: "---\nproject: X\n---\n", calendar: calendar) == "---\nproject:\n---\n")
    }

    @Test func readsInlineListsAndAFileWithoutFrontmatter() {
        let inline = Note(name: "a.md", markdown: "---\ntags: [a, \"b\"]\nattendees: []\n---\nx", calendar: calendar)
        #expect(inline.tags == ["a", "b"])
        #expect(inline.attendees.isEmpty)
        let bare = Note(name: "Plain.md", markdown: "Just text", calendar: calendar)
        #expect(bare.title == "Plain")
        #expect(bare.start == nil)
        #expect(bare.body == "Just text")
    }

    @Test func readsAndKeepsAFileWithWindowsLineEndings() {
        let file = "---\r\nproject: X\r\nstatus: draft\r\n---\r\nText\r\n"
        var note = Note(name: "a.md", markdown: file, calendar: calendar)
        #expect(note.project == "X")
        #expect(note.body == "Text\r\n")
        note.project = "Y"
        #expect(
            note.markdown(over: file, calendar: calendar) == "---\nproject: \"[[Y]]\"\nstatus: draft\n---\nText\r\n"
        )
    }

    @MainActor @Test func renamesAFileOnlyInCase() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = NoteFolder(url: url)
        folder.write("x", to: "weekly sync.md")
        #expect(folder.rename("weekly sync.md", to: "Weekly sync.md") == "Weekly sync.md")
        #expect(folder.free("Weekly sync.md") == "Weekly sync 2.md")
    }

    @Test func takesTheStartFromTheNameWithoutADateProperty() {
        let note = Note(name: "2026-10-28 0915 Retro.md", markdown: "", calendar: calendar)
        #expect(note.start == date(28, 9, 15))
        #expect(Note(name: "2026-10-28 Retro.md", markdown: "", calendar: calendar).start == date(28))
    }

    @Test func quotesValuesYAMLWouldReadOtherwise() {
        let note = Note(name: "a.md", title: "a", location: "Room: 4", tags: ["x"])
        #expect(note.markdown(over: "").contains("location: \"Room: 4\""))
    }

    @Test func namesTheFileByWhenItStartsAndItsTitle() {
        #expect(NoteName.make(title: "Sync: Q4 / plan", start: date(29, 14), calendar: calendar)
            == "2026-10-29 1400 Sync Q4 plan.md")
        #expect(NoteName.make(title: "  ", start: nil, calendar: calendar) == "Meeting.md")
        #expect(NoteName.title(of: "2026-10-29 1400 Sync.md") == "Sync")
        #expect(NoteName.title(of: "2026-10-29 Sync.md") == "Sync")
        #expect(NoteName.title(of: "Sync.md") == "Sync")
    }

    @Test func keepsANoteInItsProjectsFolder() {
        #expect(NoteName.make(title: "Sync", start: date(29, 14), project: "Bouncer", calendar: calendar)
            == "Bouncer/2026-10-29 1400 Sync.md")
        #expect(NoteName.make(title: "Sync", start: nil, project: " Work / b: c ") == "Work/b c/Sync.md")
        #expect(NoteName.folder(for: "../..") == nil)
        #expect(NoteName.folder(for: "Work//.hidden") == "Work/hidden")
        #expect(NoteName.folder(for: nil) == nil)
        let other = "---\nproject: Other\n---\n"
        let note = Note(name: "Bouncer/2026-10-29 1400 Sync.md", markdown: other, calendar: calendar)
        #expect(note.project == "Bouncer")
        #expect(note.title == "Sync")
        #expect(note.start == date(29, 14))
        #expect(Note(name: "Sync.md", markdown: other, calendar: calendar).project == "Other")
        let nested = Note(name: "Work/Bouncer/Sync.md", markdown: "", calendar: calendar)
        #expect(nested.project == "Work/Bouncer")
        #expect(nested.markdown(over: "").contains("project: \"[[Bouncer]]\""))
    }

    @Test func searchFindsPeopleAndTheProject() {
        let note = Note(name: "a.md", title: "Sync", attendees: ["Anna Smith"], project: "Bouncer", body: "")
        #expect(note.mentions("anna"))
        #expect(note.mentions("bounc"))
        #expect(!note.mentions("ben"))
    }

    @Test func durations() {
        #expect(NoteTime.duration(from: date(29, 14), to: date(29, 14, 45)) == "45 min")
        #expect(NoteTime.duration(from: date(29, 14), to: date(29, 15)) == "1 h")
        #expect(NoteTime.duration(from: date(29, 14), to: date(29, 15, 30)) == "1 h 30 min")
        #expect(NoteTime.duration(from: date(29, 14), to: nil) == nil)
        #expect(NoteTime.duration(from: date(29, 14), to: date(29, 13)) == nil)
    }

    @Test func findsTheNearestTime() {
        let times = [date(31, 12, 45), date(31, 13), date(31, 13, 15)]
        #expect(NoteTime.nearest(to: date(31, 13, 4), among: times) == date(31, 13))
        #expect(NoteTime.nearest(to: date(31, 13, 4), among: times + [date(31, 13, 5)]) == date(31, 13, 5))
        #expect(NoteTime.nearest(to: date(31, 13, 4), among: []) == nil)
    }

    @Test func groupsByDayThisWeekThenByMonth() {
        // Thursday 29 October 2026.
        let now = date(29, 18)
        let notes = [
            Note(name: "a.md", title: "a", start: date(29, 9)),
            Note(name: "b.md", title: "b", start: date(28, 9)),
            Note(name: "c.md", title: "c", start: date(26, 9)),
            Note(name: "d.md", title: "d", start: date(3, 9)),
            Note(name: "e.md", title: "e", start: date(1, 9, month: 9)),
            Note(name: "f.md", title: "f", start: date(1, 9, month: 12, year: 2025)),
            Note(name: "g.md", title: "g"),
            Note(name: "h.md", title: "h", start: date(29, 15))
        ]
        let groups = NoteGroups.grouped(notes, now: now, calendar: calendar)
        #expect(groups.map(\.title) == [
            "Today", "Yesterday", "Monday", "October", "September", "December 2025", "Undated"
        ])
        #expect(groups[0].notes.map(\.name) == ["h.md", "a.md"])
    }
}

@Suite struct ListCompletionTests {
    @Test func offersKnownNamesForTheOneBeingTyped() {
        let known = ["Anna", "Ben", "Hannah", "Annika"]
        #expect(ListCompletion.suggestions(for: "an", carrying: ["Ben"], from: known) == ["Anna", "Annika", "Hannah"])
        #expect(ListCompletion.suggestions(for: "an", carrying: ["anna"], from: known) == ["Annika", "Hannah"])
        #expect(ListCompletion.suggestions(for: " ", carrying: ["Ben"], from: known) == ["Anna", "Hannah", "Annika"])
    }

    @Test func readsTheNameTyped() {
        #expect(ListCompletion.name(from: " Anna Berg, ") == "Anna Berg")
        #expect(ListCompletion.name(from: " ,") == nil)
    }

    @Test func knownNamesComeMostUsedFirst() {
        #expect(ListCompletion.known(in: [["Ben", "Anna"], ["Anna"], ["Cleo"]]) == ["Anna", "Ben", "Cleo"])
    }
}

@Suite @MainActor struct NoteDraftTests {
    @Test func aNoteWithoutAStartGetsNoneUntilOneIsSet() {
        let modified = Date(timeIntervalSince1970: 1_000_000)
        let draft = NoteDraft(Note(name: "Plain.md", title: "Plain", modified: modified))
        #expect(draft.note == draft.saved)
        draft.start = modified.addingTimeInterval(60)
        #expect(draft.note.start == modified.addingTimeInterval(60))
    }

    @Test func movingToAnotherDayKeepsTheTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let start = NoteTime.date(from: "2026-10-30T14:06", calendar: calendar) ?? Date()
        let day = NoteTime.date(from: "2026-10-28", calendar: calendar) ?? Date()
        let moved = NoteTime.moving(start, to: day, calendar: calendar)
        #expect(NoteTime.string(for: moved, calendar: calendar) == "2026-10-28T14:06")
    }
}

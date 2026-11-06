import AppKit
import SwiftUI

/// When a meeting ran: its day, start and, once it has, end, and how long it ran. A click on the day
/// opens a calendar under the row. The start and end edit like any macOS time, and while one does,
/// the quarter hours near the start, or the usual lengths for the end, are offered under the row.
/// The end stays on the start's day. Before there is one, a click on End offers the same lengths and now.
struct NoteTimes: View {
    private enum Picking { case day, start, end }

    @Bindable var draft: NoteDraft
    @State private var picking: Picking?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let day = TaskDay.label(for: TaskDay.string(for: draft.start), today: Date()).text
                opener(.day, day, help: "Change the day")
                time(.start, startTime, help: "Change the start")
                Text("–").foregroundStyle(.secondary)
                if let end = draft.end {
                    time(.end, endTime, help: "Change the end")
                    if let duration = NoteTime.duration(from: draft.start, to: end) {
                        Text(duration).foregroundStyle(.secondary)
                    }
                } else {
                    opener(.end, "End", help: "Note when the meeting ended")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            choices
        }
    }

    @ViewBuilder private var choices: some View {
        switch picking {
        case .day:
            DatePicker("Day", selection: day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .fixedSize()
        case .start:
            nearby(draft.start)
        case .end:
            HStack(spacing: 4) {
                ForEach([15, 30, 45, 60, 90], id: \.self, content: lasting)
                now { end($0) }
            }
        case nil:
            EmptyView()
        }
    }

    /// Opens its choices, or closes them; tinted so it reads as clickable.
    private func opener(_ choice: Picking, _ text: String, help: String) -> some View {
        Button { picking = picking == choice ? nil : choice } label: {
            Text(text)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(picking == choice ? 0.2 : 0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func time(_ choice: Picking, _ date: Binding<Date>, help: String) -> some View {
        let isEditing = Binding { picking == choice } set: { editing in
            if editing { picking = choice } else if picking == choice { picking = nil }
        }
        return TimeField(date: date, isEditing: isEditing)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(picking == choice ? 0.2 : 0.08)))
            .help(help)
    }

    /// The quarter hours from half an hour before the one at or before `date` to half an hour after it,
    /// the one nearest `date` a little brighter, and now.
    private func nearby(_ date: Date) -> some View {
        let quarter = NoteTime.quarter(before: date)
        let times = (-2...2).map { quarter.addingTimeInterval(TimeInterval($0 * 15 * 60)) }
        let nearest = NoteTime.nearest(to: date, among: times)
        return HStack(spacing: 4) {
            ForEach(times, id: \.self) { time in
                Button { start(time) } label: {
                    Chip(text: Self.clock(time), isSelected: time == date, isNear: time == nearest).monospacedDigit()
                }
                .buttonStyle(.plain)
            }
            now { start($0) }
        }
    }

    /// The likeliest pick, so a little brighter than the rest.
    private func now(pick: @escaping (Date) -> Void) -> some View {
        Button { pick(NoteEditor.minute(of: Date())) } label: { Chip(text: "Now", isNear: true) }
            .buttonStyle(.plain)
    }

    /// Ends the meeting `minutes` after it started.
    private func lasting(_ minutes: Int) -> some View {
        let end = draft.start.addingTimeInterval(TimeInterval(minutes * 60))
        return Button { self.end(end) } label: {
            Chip(text: NoteTime.duration(from: draft.start, to: end) ?? "", isSelected: end == draft.end)
        }
        .buttonStyle(.plain)
    }

    private var day: Binding<Date> {
        Binding { draft.start } set: { start(NoteTime.moving(draft.start, to: $0)) }
    }

    private var startTime: Binding<Date> {
        Binding { draft.start } set: { setStart($0) }
    }

    private var endTime: Binding<Date> {
        Binding { draft.end ?? draft.start } set: { setEnd($0) }
    }

    /// Sets the start and closes the choices.
    private func start(_ date: Date) {
        setStart(date)
        picking = nil
    }

    private func end(_ date: Date) {
        setEnd(date)
        picking = nil
    }

    /// The end moves to the start's day.
    private func setStart(_ date: Date) {
        draft.start = date
        draft.end = draft.end.map { NoteTime.moving($0, to: date) }
    }

    private func setEnd(_ date: Date) {
        draft.end = NoteTime.moving(date, to: draft.start)
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

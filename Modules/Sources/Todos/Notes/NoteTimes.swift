import SwiftUI

/// When a meeting ran: its day, start and, once it has, end, and how long it ran. A click on any of
/// them opens its choices under the row: a calendar, or the day's quarter hours. The end stays on
/// the start's day.
struct NoteTimes: View {
    private enum Picking { case day, start, end }

    @Bindable var draft: NoteDraft
    @State private var picking: Picking?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let day = TaskDay.label(for: TaskDay.string(for: draft.start), today: Date()).text
                opener(.day, day, help: "Change the day")
                opener(.start, Self.clock(draft.start), help: "Change the start")
                Text("–").foregroundStyle(.secondary)
                if let end = draft.end {
                    opener(.end, Self.clock(end), help: "Change the end")
                    if let duration = NoteTime.duration(from: draft.start, to: end) {
                        Text(duration).foregroundStyle(.secondary)
                    }
                } else {
                    Button("End now") { end(NoteEditor.minute(of: Date())) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Note when the meeting ended")
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
            HStack(alignment: .top, spacing: 12) {
                TimeGrid(day: draft.start, selected: draft.start) { start($0) }
                nowChip { start($0) }
            }
        case .end:
            HStack(alignment: .top, spacing: 12) {
                TimeGrid(day: draft.start, selected: draft.end, after: draft.start) { end($0) }
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 3) {
                    GridRow { nowChip { end($0) } }
                    GridRow { lasting(15); lasting(30) }
                    GridRow { lasting(45); lasting(60) }
                    GridRow { lasting(90) }
                }
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

    /// Ends the meeting `minutes` after it started.
    private func lasting(_ minutes: Int) -> some View {
        let end = draft.start.addingTimeInterval(TimeInterval(minutes * 60))
        return Button { self.end(end) } label: {
            Chip(text: NoteTime.duration(from: draft.start, to: end) ?? "", isSelected: end == draft.end)
        }
        .buttonStyle(.plain)
    }

    private func nowChip(_ set: @escaping (Date) -> Void) -> some View {
        Button { set(NoteEditor.minute(of: Date())) } label: { Chip(text: "Now") }
            .buttonStyle(.plain)
    }

    private var day: Binding<Date> {
        Binding { draft.start } set: { start(NoteTime.moving(draft.start, to: $0)) }
    }

    /// Sets the start and closes the choices; the end moves to its day.
    private func start(_ date: Date) {
        draft.start = date
        draft.end = draft.end.map { NoteTime.moving($0, to: date) }
        picking = nil
    }

    private func end(_ date: Date) {
        draft.end = NoteTime.moving(date, to: draft.start)
        picking = nil
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// The quarter hours of `day`, an hour a row, scrolled to the selected one's hour. The full and half
/// hours stand out, as meetings mostly start on them. Given `after`, the rows start at its hour, and
/// the times up to it cannot be picked.
private struct TimeGrid: View {
    let day: Date
    let selected: Date?
    var after: Date?
    let pick: (Date) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(hours, id: \.self) { hour in
                        HStack(spacing: 4) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                slot(NoteTime.at(hour: hour, minute: minute, on: day), isHalf: minute % 30 == 0)
                            }
                        }
                        .id(hour)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 110)
            .background(OverlayScrollers())
            .onAppear {
                let hour = Calendar.current.component(.hour, from: selected ?? after ?? Date())
                proxy.scrollTo(hour, anchor: .center)
            }
        }
    }

    private var hours: Range<Int> {
        (after.map { Calendar.current.component(.hour, from: $0) } ?? 0)..<24
    }

    private func slot(_ time: Date, isHalf: Bool) -> some View {
        let isOpen = after.map { time > $0 } ?? true
        return Button { pick(time) } label: {
            Chip(text: NoteTimes.clock(time), isSelected: time == selected)
                .monospacedDigit()
                .opacity(isOpen ? (isHalf ? 1 : 0.6) : 0.25)
        }
        .buttonStyle(.plain)
        .disabled(!isOpen)
    }
}

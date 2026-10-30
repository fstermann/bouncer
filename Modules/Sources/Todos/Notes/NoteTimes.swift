import SwiftUI

/// When a meeting ran: its day, which a click opens a calendar for, the times it started and, once
/// it has, ended, and how long it ran. Hovering offers to set either to now. The end stays on the
/// start's day, as its field shows only the time.
struct NoteTimes: View {
    @Bindable var draft: NoteDraft
    @State private var isPickingDay = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { isPickingDay.toggle() } label: {
                    Text(TaskDay.label(for: TaskDay.string(for: draft.start), today: Date()).text)
                        .foregroundStyle(isPickingDay ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Change the day")
                time("Start", Binding { draft.start } set: { start($0) })
                Text("–").foregroundStyle(.secondary)
                if let end = draft.end {
                    time("End", Binding { end } set: { self.end($0) })
                    if let duration = NoteTime.duration(from: draft.start, to: end) {
                        Text("· \(duration)").foregroundStyle(.secondary)
                    }
                } else {
                    now("End now", help: "Note when the meeting ended") { end($0) }
                }
                Spacer(minLength: 0)
                if isHovered {
                    now("Start now", help: "Start the meeting now") { start($0) }
                    if draft.end != nil { now("End now", help: "End the meeting now") { end($0) } }
                }
            }
            if isPickingDay {
                DatePicker("Day", selection: day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func time(_ title: String, _ date: Binding<Date>) -> some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .fixedSize()
    }

    private func now(_ title: String, help: String, set: @escaping (Date) -> Void) -> some View {
        Button(title) { set(NoteEditor.minute(of: Date())) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
    }

    private var day: Binding<Date> {
        Binding { draft.start } set: { day in
            start(NoteTime.moving(draft.start, to: day))
            isPickingDay = false
        }
    }

    private func start(_ date: Date) {
        draft.start = date
        draft.end = draft.end.map { NoteTime.moving($0, to: date) }
    }

    private func end(_ date: Date) {
        draft.end = NoteTime.moving(date, to: draft.start)
    }
}

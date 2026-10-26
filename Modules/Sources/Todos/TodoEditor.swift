import SwiftUI

/// A todo being changed, in place of its row: its title and note, its tags and when it is due.
struct TodoEditor: View {
    @Bindable var page: TodoPage
    let todo: Todo
    @State private var isChoosingDue = false
    @State private var isPickingDate = false
    @FocusState private var isTyping: Bool

    var body: some View {
        // Laid out like the row it stands in for, so the text stays where it was.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    field
                    Button { isChoosingDue.toggle() } label: { DueLabel(due: page.editDue, isChoosing: isChoosingDue) }
                        .buttonStyle(.plain)
                        .help("Set a due date")
                }
                if isChoosingDue { DueChoices(due: $page.editDue, isPickingDate: $isPickingDate) }
                HStack(spacing: 10) {
                    tags
                    Button("Cancel") { page.editing = nil }
                        .foregroundStyle(.secondary)
                    Button("Save", action: page.saveEdit)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)).padding(.horizontal, 6))
        .onAppear { isTyping = true }
    }

    private var field: some View {
        TextField("Todo", text: $page.editDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($isTyping)
            .onSubmit(page.saveEdit)
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.shift) else { return .ignored }
                page.editDraft += "\n"
                return .handled
            }
    }

    private var tags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(page.tags, id: \.self) { tag in
                    let isOn = page.editTags.contains(tag)
                    Button {
                        if isOn { page.editTags.removeAll { $0 == tag } } else { page.editTags.append(tag) }
                    } label: {
                        Chip(text: tag, color: page.color(of: tag), isSelected: isOn)
                    }
                }
            }
        }
    }
}

/// The calendar a due date is set from, with the day once one is.
struct DueLabel: View {
    let due: String?
    let isChoosing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
            if let due { Text(TaskDay.label(for: due, today: Date()).text) }
        }
        .font(.callout)
        .foregroundStyle(due == nil && !isChoosing ? .secondary : .primary)
    }
}

/// When a todo is due. Picking leaves the choices up, so a mis-click is put right with one more click.
struct DueChoices: View {
    @Binding var due: String?
    @Binding var isPickingDate: Bool
    /// Vertical in a row's menu, which hangs under its icon.
    var axis: Axis = .horizontal

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        layout {
            choice("Today", .today)
            choice("Tomorrow", .tomorrow)
            choice("Friday", .thisWeek)
            Button { isPickingDate.toggle() } label: {
                Chip(text: pickedLabel ?? "Date…", isSelected: isPickingDate || pickedLabel != nil)
            }
            .buttonStyle(.plain)
            if axis == .horizontal { Spacer() }
            if due != nil {
                Button("Clear") {
                    due = nil
                    isPickingDate = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        if isPickingDate {
            DatePicker("", selection: pickedDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)
        }
    }

    private func choice(_ title: String, _ choice: DueChoice) -> some View {
        let day = TaskDay.string(for: choice, today: Date())
        return Button {
            due = day
            isPickingDate = false
        } label: {
            Chip(text: title, isSelected: due == day && !isPickingDate)
        }
        .buttonStyle(.plain)
    }

    /// The chosen day, when it is none of the quick choices.
    private var pickedLabel: String? {
        let today = Date()
        guard let due,
              ![DueChoice.today, .tomorrow, .thisWeek].map({ TaskDay.string(for: $0, today: today) }).contains(due)
        else { return nil }
        return TaskDay.label(for: due, today: today).text
    }

    private var pickedDay: Binding<Date> {
        Binding {
            due.flatMap { TaskDay.date(from: $0, calendar: .current) } ?? Date()
        } set: { due = TaskDay.string(for: $0) }
    }
}

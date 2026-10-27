import AppKit
import SwiftUI

/// A todo being changed, in place of its row: its title and note, with its tags and due day behind
/// the input row's icons. Return or clicking into another field saves it; Escape drops the change.
struct TodoEditor: View {
    @Bindable var page: TodoPage
    let todo: Todo
    @FocusState private var isTyping: Bool
    @State private var iconsWidth: CGFloat = 0

    private var choosingDue: RowMenu { RowMenu(line: todo.line, kind: .due) }

    var body: some View {
        // Laid out like the row it stands in for, so the text stays where it was and the click that
        // opened it lands on the same letter.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: page.toggleEditing) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .frame(width: TodoPage.markWidth)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            // Laid over the field's end rather than beside it, as the row lays them, so their height
            // cannot add to the row's.
            field
                .padding(.trailing, iconsWidth + 8)
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    icons.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { iconsWidth = $0 }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: page.editHeight, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)).padding(.horizontal, 6))
        .onAppear {
            isTyping = true
            guard let click = page.editClick else { return }
            page.editClick = nil
            // A turn later, once the field stands where the title was.
            DispatchQueue.main.async { replayClick(at: click) }
        }
        .onChange(of: isTyping) { if !$1, page.editing == todo { page.saveEdit() } }
    }

    /// The row's icons, so none move or change as it opens.
    private var icons: some View {
        HStack(spacing: 10) {
            if !page.tags.isEmpty {
                MenuButton(page: page, menu: RowMenu(line: todo.line, kind: .tags), help: "Set tags") {
                    Image(systemName: "tag").foregroundStyle(.secondary)
                }
            }
            MenuButton(page: page, menu: choosingDue, help: "Set a due date") {
                DueLabel(due: page.editDue, isChoosing: page.menu == choosingDue)
            }
            Button {
                page.editing = nil
                page.onDelete?(todo)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .font(.callout)
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
}

/// Clicks at `point` in the panel, now on the field standing in for the title, so the cursor goes
/// where the title was clicked.
@MainActor private func replayClick(at point: CGPoint) {
    guard let window = NSApp.keyWindow else { return }
    let events = [NSEvent.EventType.leftMouseDown, .leftMouseUp].compactMap { type in
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        )
    }
    guard events.count == 2 else { return }
    // Queued first: the field tracks the mouse from its mouse-down until the up arrives.
    NSApp.postEvent(events[1], atStart: false)
    window.sendEvent(events[0])
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

/// When a todo is due. Clicking the chosen day again clears it.
struct DueChoices: View {
    @Binding var due: String?
    @Binding var isPickingDate: Bool

    var body: some View {
        choice("Today", .today)
        choice("Tomorrow", .tomorrow)
        choice("Friday", .thisWeek)
        Button {
            if pickedLabel != nil, !isPickingDate { due = nil } else { isPickingDate.toggle() }
        } label: {
            Chip(text: pickedLabel ?? "Date…", isSelected: isPickingDate || pickedLabel != nil)
        }
        .buttonStyle(.plain)
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
        let isChosen = due == day && !isPickingDate
        return Button {
            due = isChosen ? nil : day
            isPickingDate = false
        } label: {
            Chip(text: title, isSelected: isChosen)
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

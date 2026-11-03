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
            .modifier(SuggestsTags(page: page, text: page.editDraft, line: todo.line))
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
    let due: String?
    /// Sets the day, and closes the choices when `closes`.
    let choose: (String?, _ closes: Bool) -> Void
    /// The day typed after `//`, offered ahead of the quick choices.
    var typed: String?
    /// The day Return takes, after `//`.
    var highlighted: String?
    /// Open from the start for a day picked from it before, so it can be changed.
    @State private var isPickingDate: Bool

    init(
        due: String?, typed: String? = nil, highlighted: String? = nil,
        choose: @escaping (String?, _ closes: Bool) -> Void
    ) {
        self.due = due
        self.typed = typed
        self.highlighted = highlighted
        self.choose = choose
        _isPickingDate = State(initialValue: Self.pickedLabel(of: due) != nil)
    }

    /// Today, tomorrow and Friday, which the keyboard steps through.
    static let quick: [(title: String, choice: DueChoice)] = [
        ("Today", .today), ("Tomorrow", .tomorrow), ("Friday", .thisWeek)
    ]

    var body: some View {
        let today = Date()
        if let typed, !Self.quick.map({ TaskDay.string(for: $0.choice, today: today) }).contains(typed) {
            choice(TaskDay.label(for: typed, today: today).text, day: typed)
        }
        ForEach(Self.quick, id: \.title) { quick in
            choice(quick.title, day: TaskDay.string(for: quick.choice, today: today))
        }
        Button { isPickingDate.toggle() } label: {
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
        if due != nil {
            Button { choose(nil, true) } label: { Chip(text: "No date") }
                .buttonStyle(.plain)
        }
    }

    private func choice(_ title: String, day: String) -> some View {
        let isChosen = due == day && !isPickingDate
        return Button {
            choose(isChosen ? nil : day, true)
        } label: {
            // Filled while highlighted, as a highlighted tag suggestion is.
            Chip(text: title, isSelected: highlighted == nil ? isChosen : highlighted == day)
        }
        .buttonStyle(.plain)
    }

    private var pickedLabel: String? { Self.pickedLabel(of: due) }

    /// The chosen day, when it is none of the quick choices.
    private static func pickedLabel(of due: String?) -> String? {
        let today = Date()
        guard let due, !quick.map({ TaskDay.string(for: $0.choice, today: today) }).contains(due) else { return nil }
        return TaskDay.label(for: due, today: today).text
    }

    /// The calendar's month arrows move the date by a month and keep its day, so only a change of day
    /// is a day clicked, which closes the choices.
    private var pickedDay: Binding<Date> {
        let shown = due.flatMap { TaskDay.date(from: $0, calendar: .current) } ?? Date()
        return Binding { shown } set: { picked in
            let calendar = Calendar.current
            let isNewDay = calendar.component(.day, from: picked) != calendar.component(.day, from: shown)
            choose(TaskDay.string(for: picked), isNewDay)
        }
    }
}

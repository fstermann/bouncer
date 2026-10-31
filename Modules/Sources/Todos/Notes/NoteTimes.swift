import AppKit
import SwiftUI

/// When a meeting ran: its day, start and, once it has, end, and how long it ran. A click on the day
/// opens a calendar under the row; a click on a time turns it into a field to type a time into, with
/// the quarter hours near it offered under the row, and for the end, how long it lasted. The end stays
/// on the start's day.
struct NoteTimes: View {
    private enum Picking { case day, start, end }

    @Bindable var draft: NoteDraft
    @State private var picking: Picking?
    /// What the field shows: the time as it was, or as stepped to, until digits are typed.
    @State private var typed = ""
    /// The digits typed, `nil` until one is.
    @State private var digits: String?
    @State private var stepped: Date?
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let day = TaskDay.label(for: TaskDay.string(for: draft.start), today: Date()).text
                opener(.day, day, help: "Change the day")
                time(.start, draft.start, help: "Change the start")
                Text("–").foregroundStyle(.secondary)
                if let end = draft.end {
                    time(.end, end, help: "Change the end")
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
        // Clicking away keeps what was typed; a pick or Escape has closed the field already.
        .onChange(of: isTyping) { if !$1, picking == .start || picking == .end { take() } }
    }

    @ViewBuilder private var choices: some View {
        switch picking {
        case .day:
            DatePicker("Day", selection: day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .fixedSize()
        case .start:
            nearby(draft.start, after: nil) { start($0) }
        case .end:
            VStack(alignment: .leading, spacing: 4) {
                nearby(draft.end ?? draft.start, after: draft.start) { end($0) }
                HStack(spacing: 4) { ForEach([15, 30, 45, 60, 90], id: \.self, content: lasting) }
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

    /// The start or end, which a click turns into a field: Return takes what is typed, and the arrows
    /// step it a quarter hour at a time. It takes only digits that a time can start with, and puts the
    /// colon in itself.
    @ViewBuilder private func time(_ choice: Picking, _ date: Date, help: String) -> some View {
        if picking == choice {
            // As wide as the longest time, so it takes no more room than the button it replaces.
            Text("00:00")
                .monospacedDigit()
                .hidden()
                .overlay { field(date) }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.2)))
        } else {
            Button {
                typed = Self.clock(date)
                digits = nil
                stepped = nil
                picking = choice
            } label: {
                Text(Self.clock(date))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }

    private func field(_ date: Date) -> some View {
        TextField("", text: $typed)
            .textFieldStyle(.plain)
            .monospacedDigit()
            .focused($isTyping)
            .onSubmit { take() }
            // Taken before the field gets them: what it holds cannot be reset while a key changes it.
            .onKeyPress(characters: Self.notDigits, phases: .down, action: refuse)
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                type((isAllSelected ? "" : digits ?? "") + press.characters)
                return .handled
            }
            // The Delete key sends U+007F, not the U+0008 `.delete` holds.
            .onKeyPress(keys: [.delete, KeyEquivalent("\u{7F}")]) { _ in
                type(isAllSelected ? "" : String((digits ?? "").dropLast()))
                return .handled
            }
            .onKeyPress(.upArrow) { step(from: date, up: true) }
            .onKeyPress(.downArrow) { step(from: date, up: false) }
            .onKeyPress(.escape) {
                picking = nil
                return .handled
            }
            // A turn later, once the field is in the window: focus set before then is lost.
            .onAppear { Task { isTyping = true } }
    }

    /// The quarter hours from half an hour before the one at or before `date` to half an hour after it,
    /// later than `after`, and now.
    private func nearby(_ date: Date, after: Date?, pick: @escaping (Date) -> Void) -> some View {
        let quarter = NoteTime.quarter(before: date)
        let times = (-2...2).map { quarter.addingTimeInterval(TimeInterval($0 * 15 * 60)) }
            .filter { time in after.map { time > $0 } ?? true }
        return HStack(spacing: 4) {
            ForEach(times, id: \.self) { time in
                Button { pick(time) } label: {
                    Chip(text: Self.clock(time), isSelected: time == date).monospacedDigit()
                }
                .buttonStyle(.plain)
            }
            Button { pick(NoteEditor.minute(of: Date())) } label: { Chip(text: "Now") }
                .buttonStyle(.plain)
        }
    }

    /// Keeps out what is no part of a time, but lets commands by.
    private func refuse(_ press: KeyPress) -> KeyPress.Result {
        press.modifiers.contains(.command) ? .ignored : .handled
    }

    /// Whether the field's text is all selected, as it opens or after Command-A, so the next digit
    /// replaces it.
    private var isAllSelected: Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.selectedRange().length == (editor.string as NSString).length
    }

    /// Shows `new` as the digits typed, if a time can start with them.
    private func type(_ new: String) {
        guard let shown = NoteTime.typed(new) else { return }
        digits = new
        typed = shown
    }

    /// The time typed, or else stepped to; `nil` for none.
    private var entered: Date? {
        digits.map { NoteTime.time(typed: $0, on: draft.start) } ?? stepped
    }

    /// Sets the time entered and closes the field.
    private func take() {
        let choice = picking
        picking = nil
        guard let time = entered else { return }
        if choice == .start { start(time) } else if choice == .end { end(time) }
    }

    private func step(from date: Date, up: Bool) -> KeyPress.Result {
        let time = NoteTime.step(entered ?? date, up: up)
        digits = nil
        stepped = time
        typed = Self.clock(time)
        return .handled
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

    /// What can be typed but is no part of a time; arrows, Return and Escape stay keys.
    private static let notDigits = CharacterSet.letters.union(.punctuationCharacters).union(.symbols)
        .union(.whitespaces).subtracting(.decimalDigits)

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

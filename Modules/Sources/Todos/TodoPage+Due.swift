import Foundation

/// The due choices, and `//` typed into a todo to open them from the keyboard.
extension TodoPage {
    /// Sets the day of the todo the due choices are open for: the one typed, the one being changed, or
    /// one in the list, straight to the file. Chosen after `//`, the `//` and what follows go.
    func chooseDue(_ day: String?, closing: Bool) {
        guard let menu, menu.kind == .due else { return }
        if dueQuery != nil { removeDueQuery() }
        if closing { self.menu = nil }
        if let line = menu.line, editing?.line == line {
            editDue = day
        } else if let line = menu.line {
            if let todo = todos.first(where: { $0.line == line }) { setDue(of: todo, to: day) }
        } else {
            draftDue = day
        }
    }

    /// The field the cursor is in: the draft, or the todo being changed.
    private var typed: String { editing == nil ? draft : editTitle }

    /// Opens the due choices while the draft, or the todo being changed, ends in `//` and what follows,
    /// and closes them once it no longer does.
    func followDueQuery() {
        let query = QuickDue.query(in: typed)
        guard query != dueQuery else { return }
        let choosing = RowMenu(line: editing?.line, kind: .due)
        if let query {
            if menu == nil || menu == choosing || menu?.kind == .suggestions { menu = choosing }
            guard menu == choosing else { return }
            dueQuery = query
            dueStep = nil
        } else {
            dueQuery = nil
            dueStep = nil
            if menu == choosing { menu = nil }
        }
    }

    /// The days the arrows step through: the one typed after `//`, if it reads as one, then the quick
    /// choices.
    var keyboardDays: [String] {
        let today = Date()
        return [typedDue].compactMap(\.self) + DueChoices.quick.map { TaskDay.string(for: $0.choice, today: today) }
    }

    /// The day typed after `//`.
    var typedDue: String? { dueQuery.flatMap { QuickDue.day(from: $0, today: Date()) } }

    /// What Return takes: the day the arrows stepped to, or else the one typed, or the quick choice
    /// typed the start of. Nothing until something is typed or stepped to.
    var highlightedDue: String? {
        if let dueStep, keyboardDays.indices.contains(dueStep) { return keyboardDays[dueStep] }
        if let typedDue { return typedDue }
        return dueQuery.flatMap(QuickDue.choice(for:)).map { TaskDay.string(for: $0, today: Date()) }
    }

    func stepDue(by step: Int) {
        let days = keyboardDays
        let current = dueStep ?? highlightedDue.flatMap(days.firstIndex(of:)) ?? (step > 0 ? -1 : days.count)
        dueStep = (current + step + days.count) % days.count
    }

    /// Takes the `//` and what follows out of the field it was typed into.
    func removeDueQuery() {
        dueQuery = nil
        dueStep = nil
        if editing == nil {
            draft = QuickDue.removingQuery(from: draft)
        } else {
            var lines = editDraft.components(separatedBy: "\n")
            lines[0] = QuickDue.removingQuery(from: lines[0])
            editDraft = lines.joined(separator: "\n")
        }
    }
}

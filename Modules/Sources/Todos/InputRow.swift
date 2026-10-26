import SwiftUI

/// The field a todo is typed into, with its due day and tags behind icons, and tags offered while
/// one is typed after `#`.
struct InputRow: View {
    @Bindable var page: TodoPage
    @FocusState private var isTyping: Bool

    private var suggesting: RowMenu { RowMenu(line: nil, kind: .suggestions) }
    private var choosingDue: RowMenu { RowMenu(line: nil, kind: .due) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            field
            if !page.tags.isEmpty {
                MenuButton(page: page, menu: RowMenu(line: nil, kind: .tags), help: "Set tags") {
                    Image(systemName: "tag")
                        .font(.callout)
                        .foregroundStyle(TaskText(page.draft).tags.isEmpty ? .secondary : .primary)
                }
            }
            MenuButton(page: page, menu: choosingDue, help: "Set a due date") {
                DueLabel(due: page.draftDue, isChoosing: page.menu == choosingDue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .onChange(of: page.focusRequests, initial: true) { isTyping = true }
        .onChange(of: page.draft) { suggest() }
    }

    private var field: some View {
        TextField("Add a todo", text: $page.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($isTyping)
            .onSubmit(add)
            // Return adds the todo, or takes the highlighted tag; Shift-Return starts a new line, which
            // becomes its note.
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    page.draft += "\n"
                    return .handled
                }
                return completeIfSuggesting()
            }
            .onKeyPress(.tab) { completeIfSuggesting() }
            .onKeyPress(.downArrow) { moveSuggestion(by: 1) }
            .onKeyPress(.upArrow) { moveSuggestion(by: -1) }
            .anchorPreference(key: MenuAnchor.self, value: .bounds) { page.menu == suggesting ? $0 : nil }
    }

    /// Offers tags while one is typed, unless another of the field's menus is open.
    private func suggest() {
        page.suggestion = 0
        if !page.suggestions.isEmpty, page.menu == nil || page.menu == suggesting {
            page.menu = suggesting
        } else if page.menu == suggesting {
            page.menu = nil
        }
    }

    private func completeIfSuggesting() -> KeyPress.Result {
        let suggestions = page.suggestions
        guard page.menu == suggesting, suggestions.indices.contains(page.suggestion) else { return .ignored }
        page.complete(with: suggestions[page.suggestion])
        return .handled
    }

    private func moveSuggestion(by step: Int) -> KeyPress.Result {
        let count = page.suggestions.count
        guard page.menu == suggesting, count > 0 else { return .ignored }
        page.suggestion = (page.suggestion + step + count) % count
        return .handled
    }

    private func add() {
        page.onAdd?(page.draft)
        page.draft = ""
        page.draftDue = nil
        page.menu = nil
    }
}

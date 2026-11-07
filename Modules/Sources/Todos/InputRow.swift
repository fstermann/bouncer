import SwiftUI

/// The field a todo is typed into, with its due day and tags behind icons, and tags offered while
/// one is typed after `#`.
struct InputRow: View {
    @Bindable var page: TodoPage
    let isTyping: FocusState<Bool>.Binding
    @State private var arrowKeys = TypedArrowKeys()
    @State private var imageKeys = PastedImageKeys()

    private var choosingDue: RowMenu { RowMenu(line: nil, kind: .due) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "plus")
                .frame(width: TodoPage.markWidth)
                .foregroundStyle(.tertiary)
            field
            if !page.tags.isEmpty {
                MenuButton(page: page, menu: RowMenu(line: nil, kind: .tags), help: "Set tags") {
                    Image(systemName: "tag")
                        .font(.callout)
                        .foregroundStyle(TaskText(page.draft).tags.isEmpty ? .secondary : .primary)
                }
            }
            MenuButton(page: page, menu: choosingDue, help: "Set a due date") {
                DueLabel(due: page.draftDue, time: page.draftTime, isChoosing: page.menu == choosingDue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .onChange(of: page.focusRequests, initial: true) { isTyping.wrappedValue = true }
    }

    private var field: some View {
        TextField("Add a todo", text: $page.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused(isTyping)
            .onChange(of: isTyping.wrappedValue, initial: true) {
                arrowKeys.isActive = $1
                imageKeys.images = page.images
                imageKeys.isActive = $1
            }
            .onDisappear {
                arrowKeys.isActive = false
                imageKeys.isActive = false
            }
            .onSubmit(page.add)
            // Return adds the todo, or takes the highlighted tag; Shift-Return starts a new line, which
            // becomes its note.
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.shift) else { return .ignored }
                page.draft += "\n"
                return .handled
            }
            .modifier(SuggestsTags(page: page, text: page.draft, line: nil))
    }
}

/// Offers tags while one is typed after `#` into `text`, unless another of the field's menus is open,
/// and takes the highlighted one on Return or Tab. `//` opens the due choices, picked from the same way.
struct SuggestsTags: ViewModifier {
    let page: TodoPage
    let text: String
    /// The todo whose field it is; `nil` for the todo being typed.
    let line: Int?

    private var suggesting: RowMenu { RowMenu(line: line, kind: .suggestions) }
    private var choosingDue: RowMenu { RowMenu(line: line, kind: .due) }

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return, phases: .down) { press in
                press.modifiers.contains(.shift) ? .ignored : completeIfSuggesting()
            }
            .onKeyPress(.tab) { completeIfSuggesting() }
            .onKeyPress(.downArrow) { moveSuggestion(by: 1) }
            .onKeyPress(.upArrow) { moveSuggestion(by: -1) }
            .anchorPreference(key: MenuAnchor.self, value: .bounds) { page.menu == suggesting ? $0 : nil }
            .onChange(of: text) { suggest() }
    }

    private func suggest() {
        page.followDueQuery()
        page.suggestion = 0
        if !page.suggestions.isEmpty, page.menu == nil || page.menu == suggesting {
            page.menu = suggesting
        } else if page.menu == suggesting {
            page.menu = nil
        }
    }

    private func completeIfSuggesting() -> KeyPress.Result {
        if page.menu == choosingDue, page.dueQuery != nil {
            // With nothing to take, Return leaves the `//` rather than adding it with the todo.
            if let day = page.highlightedDue { page.chooseDue(day, closing: true) } else { page.menu = nil }
            return .handled
        }
        let suggestions = page.suggestions
        guard page.menu == suggesting, suggestions.indices.contains(page.suggestion) else { return .ignored }
        page.complete(with: suggestions[page.suggestion])
        return .handled
    }

    private func moveSuggestion(by step: Int) -> KeyPress.Result {
        if page.menu == choosingDue, page.dueQuery != nil {
            page.stepDue(by: step)
            return .handled
        }
        let count = page.suggestions.count
        guard page.menu == suggesting, count > 0 else { return .ignored }
        page.suggestion = (page.suggestion + step + count) % count
        return .handled
    }
}

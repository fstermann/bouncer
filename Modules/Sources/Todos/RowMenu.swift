import SwiftUI

/// Which choices are open, and for which todo. By line, so it stays open as the todo's text changes.
struct RowMenu: Equatable, Hashable {
    /// Suggestions hang under the field a tag is typed into, a tag's colours under its chip, and the
    /// others under the icon that opened them.
    enum Kind: Hashable { case due, tags, suggestions, colors(String) }
    /// `nil` for the todo being typed.
    let line: Int?
    let kind: Kind

    /// Where the menu hangs, in screen coordinates: under `anchor`, left-aligned to the field or a
    /// chip, or right-aligned to an icon, and kept off the panel's left edge. The page's coordinates run down
    /// from its top-left corner, the panel's top.
    func frame(size: CGSize, under anchor: CGRect, in panel: CGRect) -> CGRect {
        let left = switch kind {
        case .suggestions, .colors: anchor.minX
        case .due, .tags: anchor.maxX - size.width
        }
        let minX = max(panel.minX + 8, panel.minX + left)
        let maxY = panel.maxY - anchor.maxY - 4
        return CGRect(x: minX, y: maxY - size.height, width: size.width, height: size.height)
    }
}

/// The open menu, in a view of its own beside the panel rather than in it, so it can hang past the
/// panel's bottom edge, which cuts off what the page draws.
struct RowMenuHost: View {
    let page: TodoPage

    var body: some View {
        if let menu = page.menu, menu.line == nil || todo(of: menu) != nil {
            RowMenuView(page: page, todo: todo(of: menu), kind: menu.kind)
                .id(menu)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    page.menuSize = size
                    page.onResize?()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
        }
    }

    private func todo(of menu: RowMenu) -> Todo? {
        menu.line.flatMap { line in page.todos.first { $0.line == line } }
    }
}

/// Opens `menu` under itself, or closes it.
struct MenuButton<Label: View>: View {
    let page: TodoPage
    let menu: RowMenu
    let help: String
    @ViewBuilder let label: Label

    var body: some View {
        Button { page.menu = page.menu == menu ? nil : menu } label: { label }
            .buttonStyle(.plain)
            .help(help)
            .anchorPreference(key: MenuAnchor.self, value: .bounds) { page.menu == menu ? $0 : nil }
    }
}

/// The frame of what the open menu hangs under.
struct MenuAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// When a todo is due, which tags it carries, or the tag being typed, for a todo in the list or,
/// without one, the todo being typed.
struct RowMenuView: View {
    let page: TodoPage
    let todo: Todo?
    let kind: RowMenu.Kind
    @State private var isPickingDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch kind {
            case .due:
                DueChoices(due: due, isPickingDate: $isPickingDate, axis: .vertical)
            case .tags:
                let carried = TaskText(todo?.text ?? page.draft).tags
                ForEach(page.tags, id: \.self) { tag in
                    Button { toggle(tag) } label: {
                        Chip(text: tag, color: page.color(of: tag), isSelected: carried.contains(tag))
                    }
                    .buttonStyle(.plain)
                }
            case .suggestions:
                ForEach(Array(page.suggestions.enumerated()), id: \.element) { index, tag in
                    Button { page.complete(with: tag) } label: {
                        Chip(text: tag, color: page.color(of: tag), isSelected: index == page.suggestion)
                    }
                    .buttonStyle(.plain)
                }
            case .colors(let tag):
                Palette(page: page, tag: tag)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
    }

    /// Written straight to the file, or to the todo being typed; one day is all a todo takes, so the
    /// choices close on it.
    private var due: Binding<String?> {
        Binding { todo.map { TaskText($0.text).due } ?? page.draftDue } set: { day in
            page.menu = nil
            if let todo { page.setDue(of: todo, to: day) } else { page.draftDue = day }
        }
    }

    private func toggle(_ tag: String) {
        if let todo { page.toggleTag(tag, of: todo) } else { page.draft = TagCompletion.toggling(tag, in: page.draft) }
    }
}

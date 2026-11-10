import SwiftUI

/// Which choices are open, and for which todo. By line, so it stays open as the todo's text changes.
struct RowMenu: Equatable, Hashable {
    /// Suggestions hang under the field a tag is typed into, a tag's colours under its chip, a todo's
    /// actions and the Claude group's where they were right-clicked, and the others under the icon
    /// that opened them.
    enum Kind: Hashable { case due, tags, suggestions, colors(String), actions, queue, working }
    /// `nil` for the todo being typed.
    let line: Int?
    let kind: Kind

    /// Where the menu hangs, in screen coordinates: under `anchor`, left-aligned to the field or a
    /// chip, or right-aligned to an icon, and kept off the panel's left edge. The page's coordinates run down
    /// from its top-left corner, the panel's top.
    func frame(size: CGSize, under anchor: CGRect, in panel: CGRect) -> CGRect {
        let left = switch kind {
        case .suggestions, .colors, .actions, .queue, .working: anchor.minX
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
struct MenuButton<Page: TagFiltering, Label: View>: View {
    let page: Page
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

/// Where a right-click opened `menu`, for it to hang from.
struct ClickAnchor: ViewModifier {
    let point: CGPoint
    let isOpen: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .anchorPreference(key: MenuAnchor.self, value: .bounds) { isOpen ? $0 : nil }
                .padding(.leading, point.x)
                .padding(.top, point.y)
                .allowsHitTesting(false)
        }
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

    var body: some View {
        switch kind {
        case .actions:
            if let todo { RowActions(page: page, todo: todo) }
        case .queue:
            QueueActions(page: page)
        case .working:
            WorkingActions(page: page)
        case .due:
            DueChoices(
                due: due, time: time, typed: todo == nil || isEditing ? page.typedDue : nil,
                highlighted: todo == nil || isEditing ? page.highlightedDue : nil, choose: setDue,
                chooseTime: page.chooseTime
            )
            .menuSurface()
        case .tags:
            let carried = TaskText(isEditing ? page.editTitle : todo?.text ?? page.draft).tags
            TagChoices(page: page, tags: page.tags, carried: carried, toggle: toggle)
            .menuSurface()
        default:
            choices
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch kind {
            case .suggestions:
                ForEach(Array(page.suggestions.enumerated()), id: \.element) { index, tag in
                    Button { page.complete(with: tag) } label: {
                        Chip(tag: tag, color: page.color(of: tag), isSelected: index == page.suggestion)
                    }
                    .buttonStyle(.plain)
                }
            case .colors(let tag):
                Palette(page: page, tag: tag)
                RepositoryLink(page: page, tag: tag)
            case .actions, .queue, .working, .due, .tags:
                EmptyView()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
    }

    /// Whether the todo is open in the editor, whose choices wait for it to be saved.
    private var isEditing: Bool { todo != nil && page.editing == todo }

    private var due: String? {
        isEditing ? page.editDue : todo.map { TaskText($0.text).due } ?? page.draftDue
    }

    private var time: String? {
        isEditing ? page.editTime : todo.map { TaskText($0.text).time } ?? page.draftTime
    }

    private func setDue(_ day: String?, closes: Bool) {
        page.chooseDue(day, closing: closes)
    }

    private func toggle(_ tag: String) {
        if isEditing {
            page.editDraft = TagCompletion.toggling(tag, in: page.editDraft)
        } else if let todo {
            page.toggleTag(tag, of: todo)
        } else {
            page.draft = TagCompletion.toggling(tag, in: page.draft)
        }
    }
}

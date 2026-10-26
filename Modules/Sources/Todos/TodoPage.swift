import Observation
import SwiftUI

/// What the todo page shows, and what it does when used.
@MainActor
@Observable
final class TodoPage {
    var todos: [Todo] = []
    /// From the file's frontmatter; offered as filters even before any todo carries them.
    var categories: [String] = []
    /// Tag to colour name, from the preferences.
    var tagColors: [String: String] = [:]
    var draft = ""
    /// `yyyy-MM-dd` for the todo being typed.
    var draftDue: String?
    /// The highlighted one of the tags offered while one is typed.
    var suggestion = 0
    var isAddingCategory = false
    var categoryDraft = ""
    /// The tag whose colour is being picked, in the palette under the categories.
    var coloringTag: String?
    /// The category the list is narrowed to.
    var filter: String?
    /// The row beside the notch, which the page starts below.
    var menuBarHeight: CGFloat = 24
    var showsSwitch = false
    var showsDone = false
    /// Just ticked, and kept in the list a moment so a mis-click can be taken back.
    var lingering: Set<Todo> = []
    /// Deleted, and shown a moment longer so a mis-click can be taken back.
    var deleting: Set<Todo> = []
    /// The lines of todos whose note is shown in full.
    var expanded: Set<Int> = []
    /// The list's natural height and the whole page's, as last laid out.
    var listHeight: CGFloat = 0
    var contentHeight: CGFloat?
    /// Bumped each time the panel opens, to put the cursor in the field.
    var focusRequests = 0
    /// The todo being changed, in place of its row, and what it is being changed to.
    var editing: Todo?
    var editDraft = ""
    var editTags: [String] = []
    var editDue: String?
    /// The choices open under one of a row's icons.
    var menu: RowMenu?
    /// The open menu's icon, in the page's coordinates, and the menu's size, for the panel to place it.
    @ObservationIgnored var menuIcon: CGRect = .zero
    @ObservationIgnored var menuSize: CGSize = .zero

    @ObservationIgnored var onToggle: (@MainActor (Todo) -> Void)?
    @ObservationIgnored var onAdd: (@MainActor (String) -> Void)?
    /// A todo, its new text and its new note.
    @ObservationIgnored var onEdit: (@MainActor (Todo, String, String) -> Void)?
    @ObservationIgnored var onDelete: (@MainActor (Todo) -> Void)?
    @ObservationIgnored var onRestore: (@MainActor (Todo) -> Void)?
    @ObservationIgnored var onAddCategory: (@MainActor (String) -> Void)?
    @ObservationIgnored var onColor: (@MainActor (String, String?) -> Void)?
    @ObservationIgnored var onSwitch: (@MainActor () -> Void)?
    /// The page's height changed, so the panel has to refit.
    @ObservationIgnored var onResize: (@MainActor () -> Void)?

    /// The categories, then any other tag a todo carries, each once.
    var tags: [String] {
        var seen = Set(categories)
        return categories + todos.flatMap { TaskText($0.text).tags }.filter { seen.insert($0).inserted }
    }

    /// Open todos, and ticked ones still lingering: the soonest due first, the rest in file order.
    var open: [Todo] {
        filtered.filter { !$0.isDone || lingering.contains($0) }
            .sorted { (TaskText($0.text).due ?? "~", $0.line) < (TaskText($1.text).due ?? "~", $1.line) }
    }
    /// Ticked todos stay in the file, as Obsidian keeps them, and are listed here on request.
    var done: [Todo] { filtered.filter { $0.isDone && !lingering.contains($0) } }
    var rows: [Todo] { showsDone ? open + done : open }

    /// Nothing half-entered that the pointer leaving would throw away.
    var isIdle: Bool {
        draft.isEmpty && !isAddingCategory && coloringTag == nil && editing == nil && menu == nil
    }

    private var filtered: [Todo] {
        guard let filter else { return todos }
        return todos.filter { TaskText($0.text).tags.contains(filter) }
    }

    func startEditing(_ todo: Todo) {
        let text = TaskText(todo.text)
        editing = todo
        editDraft = todo.note.isEmpty ? text.title : text.title + "\n" + todo.note
        editTags = text.tags
        editDue = text.due
        coloringTag = nil
    }

    /// Tags typed into the title join the chosen ones; the day it was done is kept.
    func saveEdit() {
        guard let todo = editing else { return }
        let lines = editDraft.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return }
        var text = TaskText(first)
        text.tags = editTags + text.tags.filter { !editTags.contains($0) }
        text.due = editDue ?? text.due
        text.done = TaskText(todo.text).done
        editing = nil
        onEdit?(todo, text.text, lines.dropFirst().joined(separator: "\n"))
    }

    func setDue(of todo: Todo, to due: String?) {
        var text = TaskText(todo.text)
        text.due = due
        onEdit?(todo, text.text, todo.note)
    }

    func toggleTag(_ tag: String, of todo: Todo) {
        var text = TaskText(todo.text)
        if text.tags.contains(tag) { text.tags.removeAll { $0 == tag } } else { text.tags.append(tag) }
        onEdit?(todo, text.text, todo.note)
    }

    /// The tags offered for the `#word` the draft ends in.
    var suggestions: [String] { TagCompletion.suggestions(for: draft, from: tags) }

    func complete(with tag: String) {
        draft = TagCompletion.completing(draft, with: tag)
    }

    func color(of tag: String) -> Color? {
        tagColors[tag].flatMap(TagColor.init(rawValue:))?.color
    }

    func setColor(_ color: TagColor, of tag: String) {
        let name = color == .grey ? nil : color.rawValue
        tagColors[tag] = name
        onColor?(tag, name)
    }

    static let width: CGFloat = 380
    static let maxListHeight: CGFloat = 320

    /// An estimate until the page has been laid out, and its laid-out height from then on.
    var height: CGFloat { contentHeight ?? menuBarHeight + 28 * CGFloat(rows.count + 2) }
}

struct TodoPageView: View {
    @Bindable var page: TodoPage

    var body: some View {
        VStack(spacing: 0) {
            topRow
            TagRow(page: page)
            if let tag = page.coloringTag { Palette(page: page, tag: tag) }
            list
            InputRow(page: page)
        }
        .overlayPreferenceValue(MenuAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor, page.menu != nil {
                    Color.clear
                        .onChange(of: proxy[anchor], initial: true) {
                            page.menuIcon = $1
                            page.onResize?()
                        }
                }
            }
            // Only measures; never in the way of the page's clicks and hovers.
            .allowsHitTesting(false)
        }
        .onChange(of: page.menu) {
            if $1 == nil { page.menuSize = .zero }
            page.onResize?()
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            page.contentHeight = height
            page.onResize?()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var topRow: some View {
        HStack {
            if !page.done.isEmpty || page.showsDone {
                Button(page.showsDone ? "Hide done" : "\(page.done.count) done") { page.showsDone.toggle() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if page.showsSwitch {
                Button { page.onSwitch?() } label: { Image(systemName: "menubar.rectangle") }
                    .buttonStyle(.plain)
                    .help("Show hidden items")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: page.menuBarHeight)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(page.rows) { todo in
                    if page.editing == todo {
                        TodoEditor(page: page, todo: todo)
                    } else {
                        TodoRow(page: page, todo: todo)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { page.listHeight = $0 }
        }
        .frame(height: min(page.listHeight, TodoPage.maxListHeight))
    }
}

private struct TodoRow: View {
    let page: TodoPage
    let todo: Todo
    @State private var isHovered = false

    var body: some View {
        let text = TaskText(todo.text)
        let isDeleting = page.deleting.contains(todo)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDeleting ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(text.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .strikethrough(todo.isDone || isDeleting)
                        .foregroundStyle(isDeleting ? .red : todo.isDone ? .secondary : .primary)
                    ForEach(text.tags, id: \.self) { Chip(text: $0, color: page.color(of: $0)) }
                    Spacer(minLength: 0)
                    if let due = text.due {
                        let label = TaskDay.label(for: due, today: Date())
                        Text(label.text)
                            .font(.caption)
                            .foregroundStyle(label.isOverdue && !todo.isDone ? .red : .secondary)
                    }
                    if isDeleting {
                        Button { page.onRestore?(todo) } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Undo delete")
                    } else if isHovered || page.menu?.line == todo.line {
                        actions
                    }
                }
                if !todo.note.isEmpty {
                    // Its own tap, which wins over the row's, so reading a note does not tick it.
                    Text(todo.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(page.expanded.contains(todo.line) ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if page.expanded.remove(todo.line) == nil { page.expanded.insert(todo.line) }
                        }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if !isDeleting { page.onToggle?(todo) } }
        .onHover { isHovered = $0 }
        .overlay(RightClick { if !isDeleting { page.startEditing(todo) } })
        .help("Right-click to edit")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            MenuButton(page: page, menu: RowMenu(line: todo.line, kind: .due), help: "Set a due date") {
                Image(systemName: "calendar")
            }
            if !page.tags.isEmpty {
                MenuButton(page: page, menu: RowMenu(line: todo.line, kind: .tags), help: "Set tags") {
                    Image(systemName: "tag")
                }
            }
            Button { page.onDelete?(todo) } label: { Image(systemName: "trash") }
                .help("Delete")
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The categories to filter by, and a way to add one. Right-clicking one opens its colours.
private struct TagRow: View {
    @Bindable var page: TodoPage

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(page.tags, id: \.self) { tag in
                    Button { page.filter = page.filter == tag ? nil : tag } label: {
                        Chip(text: tag, color: page.color(of: tag), isSelected: page.filter == tag)
                            // Ringed while its colours are open below it.
                            .overlay(Capsule().stroke(.white, lineWidth: page.coloringTag == tag ? 1.5 : 0))
                    }
                    .buttonStyle(.plain)
                    .overlay(RightClick { page.coloringTag = tag })
                }
                if page.isAddingCategory {
                    TextField("Category", text: $page.categoryDraft)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 90)
                        .onSubmit {
                            page.onAddCategory?(page.categoryDraft)
                            page.categoryDraft = ""
                            page.isAddingCategory = false
                        }
                } else {
                    Button { page.isAddingCategory = true } label: { Chip(text: "+") }
                        .buttonStyle(.plain)
                        .help("Add a category")
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 22)
        .padding(.bottom, 6)
    }
}

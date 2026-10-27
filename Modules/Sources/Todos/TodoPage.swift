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
    /// The tags the list is narrowed to: it shows the todos carrying all of them.
    var filters: Set<String> = []
    /// The list is narrowed to todos carrying no tag, which no tag filter can join.
    var showsUntagged = false
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
    /// Its title and tags on the first line, as typed into the add field, and its note under them.
    var editDraft = ""
    var editDue: String?
    /// Where the click that opened the editor landed, in window coordinates, to put the cursor there.
    @ObservationIgnored var editClick: CGPoint?
    /// The height of the row the editor stands in for, which it keeps so the list does not shift.
    @ObservationIgnored var editHeight: CGFloat = 0
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
    @ObservationIgnored var onRemoveCategory: (@MainActor (String) -> Void)?
    @ObservationIgnored var onColor: (@MainActor (String, String?) -> Void)?
    @ObservationIgnored var onSwitch: (@MainActor () -> Void)?
    /// The page's height changed, so the panel has to refit.
    @ObservationIgnored var onResize: (@MainActor () -> Void)?

    /// The categories, then any other tag a listed todo carries, each once: a tag only done todos
    /// carry shows while they do.
    var tags: [String] {
        var seen = Set(categories)
        return categories + listed.flatMap { TaskText($0.text).tags }.filter { seen.insert($0).inserted }
    }

    /// How many listed todos carry `tag`, whatever the filters.
    func count(of tag: String) -> Int {
        listed.filter { TaskText($0.text).tags.contains(tag) }.count
    }

    var untaggedCount: Int { listed.filter { TaskText($0.text).tags.isEmpty }.count }

    /// Offered only beside tags, and while some todo has none.
    var offersUntagged: Bool { !tags.isEmpty && untaggedCount > 0 }

    func toggleFilter(_ tag: String) {
        showsUntagged = false
        if filters.remove(tag) == nil { filters.insert(tag) }
    }

    func toggleUntagged() {
        filters = []
        showsUntagged.toggle()
    }

    /// Open todos, and ticked ones still lingering or being edited: the soonest due first, the rest
    /// in file order.
    var open: [Todo] {
        filtered.filter(isListedOpen)
            .sorted { (TaskText($0.text).due ?? "~", $0.line) < (TaskText($1.text).due ?? "~", $1.line) }
    }
    /// Ticked todos stay in the file, as Obsidian keeps them, and are listed here on request.
    var done: [Todo] { filtered.filter { !isListedOpen($0) } }
    var rows: [Todo] { showsDone ? open + done : open }

    /// Nothing half-entered that the pointer leaving would throw away.
    var isIdle: Bool {
        draft.isEmpty && !isAddingCategory && editing == nil && menu == nil
    }

    /// A todo ticked and then opened in the editor stays until the edit ends, rather than going
    /// from under the cursor. Listed with the done ones, it stays where it is.
    private func isListedOpen(_ todo: Todo) -> Bool {
        !todo.isDone || lingering.contains(todo) || !showsDone && editing == todo
    }

    private var listed: [Todo] { showsDone ? todos : todos.filter(isListedOpen) }

    private var filtered: [Todo] {
        todos.filter {
            let tags = TaskText($0.text).tags
            return showsUntagged ? tags.isEmpty : filters.isSubset(of: tags)
        }
    }

    /// Saves the todo being changed first, as a click elsewhere does.
    func startEditing(_ todo: Todo, at click: CGPoint? = nil) {
        saveEdit()
        editClick = click
        var text = TaskText(todo.text)
        editDue = text.due
        text.due = nil
        text.done = nil
        editing = todo
        editDraft = todo.note.isEmpty ? text.text : text.text + "\n" + todo.note
    }

    /// The day it was done is kept.
    func saveEdit() {
        guard let todo = editing else { return }
        if menu?.kind == .suggestions { menu = nil }
        let lines = editDraft.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return }
        var text = TaskText(first)
        text.due = editDue ?? text.due
        text.done = TaskText(todo.text).done
        editing = nil
        onEdit?(todo, text.text, lines.dropFirst().joined(separator: "\n"))
    }

    /// Ticks the todo being changed, saving the change first. Found again by its line, since saving
    /// changed its text.
    func toggleEditing() {
        guard let todo = editing else { return }
        saveEdit()
        editing = nil
        if let saved = todos.first(where: { $0.line == todo.line }) { onToggle?(saved) }
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

    /// The tags offered for the `#word` the draft, or the title being edited, ends in.
    var suggestions: [String] {
        TagCompletion.suggestions(for: editing == nil ? draft : editTitle, from: tags)
    }

    func complete(with tag: String) {
        if editing == nil {
            draft = TagCompletion.completing(draft, with: tag)
        } else {
            var lines = editDraft.components(separatedBy: "\n")
            lines[0] = TagCompletion.completing(lines[0], with: tag)
            editDraft = lines.joined(separator: "\n")
        }
    }

    /// The edited todo's first line, which holds its tags.
    var editTitle: String { editDraft.components(separatedBy: "\n")[0] }

    func color(of tag: String) -> Color? {
        tagColors[tag].flatMap(TagColor.init(rawValue:))?.color
    }

    func setColor(_ color: TagColor, of tag: String) {
        let name = color == .grey ? nil : color.rawValue
        tagColors[tag] = name
        onColor?(tag, name)
    }

    static let width: CGFloat = 420
    static let maxListHeight: CGFloat = 320
    /// The column the rows' circles stand in, which the field's plus and the editor's circle share.
    static let markWidth: CGFloat = 16

    /// An estimate until the page has been laid out, and its laid-out height from then on.
    var height: CGFloat { contentHeight ?? menuBarHeight + 28 * CGFloat(rows.count + 2) }
}

struct TodoPageView: View {
    private static let list = "list"
    @Bindable var page: TodoPage
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 0) {
            topRow
            TagRow(page: page, isTyping: $isTyping)
            list
            InputRow(page: page, isTyping: $isTyping)
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
                Button(page.showsDone ? "Hide done" : "Show \(page.done.count) done") { page.showsDone.toggle() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if page.showsSwitch {
                Button { page.onSwitch?() } label: { Image(systemName: "menubar.rectangle") }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
            // A row's menu closes on scrolling, as a popover does, rather than riding off with its icon.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.list)).minY } action: { _ in
                if page.menu?.line != nil { page.menu = nil }
            }
            .background(OverlayScrollers())
        }
        .coordinateSpace(.named(Self.list))
        .frame(height: min(page.listHeight, TodoPage.maxListHeight))
    }
}

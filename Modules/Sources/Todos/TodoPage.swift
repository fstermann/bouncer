import Observation
import Settings
import SwiftUI

/// What the todo page shows, and what it does when used.
@MainActor
@Observable
final class TodoPage: TagFiltering {
    var todos: [Todo] = []
    /// From the file's frontmatter; offered as filters even before any todo carries them.
    var categories: [String] = []
    /// Tag to colour name, from the file, or from the preferences while it keeps none.
    var tagColors: [String: String] = [:]
    /// The order the tags' chips were dragged into, from the preferences.
    var tagOrder: [String] = []
    var draft = ""
    /// `yyyy-MM-dd` for the todo being typed.
    var draftDue: String?
    /// `HH:mm` on that day.
    var draftTime: String?
    /// The highlighted one of the tags offered while one is typed.
    var suggestion = 0
    var isAddingCategory = false
    var categoryDraft = ""
    /// The local repository each tag's todos go to Claude in, and where those without one go.
    var repositories: [String: String] = [:]
    var claudeFolder = ""
    /// The Claude Code session each todo sent to Claude went to, by its title.
    var sessions: [String: ClaudeSession] = [:]
    /// The tags the list is narrowed to: it shows the todos carrying all of them.
    var filters: Set<String> = []
    /// The list is narrowed to todos carrying no tag, which no tag filter can join.
    var showsUntagged = false
    /// The todos are being searched for `query`, which narrows the list and is marked in it.
    var isSearching = false
    var query = ""
    /// Bumped to put the cursor back in the search field.
    var searchFocusRequests = 0
    /// The row beside the notch, which the page starts below.
    var menuBarHeight: CGFloat = 24
    var showsDone = false
    /// Just ticked, and kept in the list a moment so a mis-click can be taken back.
    var lingering: Set<Todo> = []
    /// Deleted, and shown a moment longer so a mis-click can be taken back.
    var deleting: Set<Todo> = []
    /// The lines of todos whose note is shown in full.
    var expanded: Set<Int> = []
    /// How far down the list was scrolled, which the next open scrolls back to.
    @ObservationIgnored var scrollOffset: CGFloat = 0
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
    var editTime: String?
    /// Where the click that opened the editor landed, in window coordinates, to put the cursor there.
    @ObservationIgnored var editClick: CGPoint?
    /// The height of the row the editor stands in for, which it keeps so the list does not shift.
    @ObservationIgnored var editHeight: CGFloat = 0
    /// The choices open under one of a row's icons.
    var menu: RowMenu?
    /// What is typed after `//`, while the due choices are open from it.
    var dueQuery: String?
    /// The due choice the arrows stepped to, among `keyboardDays`.
    var dueStep: Int?
    /// The open menu's icon, in the page's coordinates, and the menu's size, for the panel to place it.
    @ObservationIgnored var menuIcon: CGRect = .zero
    @ObservationIgnored var menuSize: CGSize = .zero
    /// Where the open menu was right-clicked open, in its row's or heading's coordinates.
    var menuClick: CGPoint = .zero

    /// Where pasted images are saved and read back from; `nil` while the page is closed.
    @ObservationIgnored var images: PastedImages?
    @ObservationIgnored var onToggle: (@MainActor (Todo) -> Void)?
    @ObservationIgnored var onAdd: (@MainActor (String) -> Void)?
    /// A todo, its new text and its new note.
    @ObservationIgnored var onEdit: (@MainActor (Todo, String, String) -> Void)?
    @ObservationIgnored var onDelete: (@MainActor (Todo) -> Void)?
    /// A todo, and whether it is now in progress.
    @ObservationIgnored var onMark: (@MainActor (Todo, Bool) -> Void)?
    /// Todos sent to Claude Code in a repository.
    @ObservationIgnored var onSend: (@MainActor ([Todo], String) -> Void)?
    /// Picks up the Claude Code session a todo was sent to, in Terminal.
    @ObservationIgnored var onResume: (@MainActor (Todo) -> Void)?
    /// Ticks the todos Claude worked on.
    @ObservationIgnored var onFinish: (@MainActor ([Todo]) -> Void)?
    /// A tag to link a repository to, or with `nil`, to unlink.
    @ObservationIgnored var onLink: (@MainActor (String, Bool) -> Void)?
    @ObservationIgnored var onRestore: (@MainActor (Todo) -> Void)?
    @ObservationIgnored var onAddCategory: (@MainActor (String) -> Void)?
    @ObservationIgnored var onRemoveCategory: (@MainActor (String) -> Void)?
    @ObservationIgnored var onColor: (@MainActor (String, String?) -> Void)?
    /// The order the chips were dragged into, once the drag ends.
    @ObservationIgnored var onOrder: (@MainActor ([String]) -> Void)?
    /// The page's height changed, so the panel has to refit.
    @ObservationIgnored var onResize: (@MainActor () -> Void)?

    /// Open todos, and ticked ones still lingering or being edited: the soonest due first, the rest
    /// in file order.
    var open: [Todo] {
        filtered.filter(isListedOpen)
            .sorted { (Self.dueKey(of: $0), $0.line) < (Self.dueKey(of: $1), $1.line) }
    }
    /// Ticked todos stay in the file, as Obsidian keeps them, and are listed here on request.
    var done: [Todo] { filtered.filter { !isListedOpen($0) } }
    /// The listed todos still to do; one just ticked no longer counts while it lingers.
    var openCount: Int { open.filter { !$0.isDone }.count }
    /// Open todos tagged for Claude, waiting to be sent, which lead the list.
    var queued: [Todo] { groups.queued }
    /// Todos sent to Claude, still in progress, after those waiting.
    var working: [Todo] { groups.working }
    /// The rest of the open todos.
    var others: [Todo] { groups.others }
    var rows: [Todo] { sections.flatMap(\.todos) }
    /// Of the other todos, those due today or before, which lead them, sorted as they are, and are set apart.
    var dueTodayCount: Int { Self.dueTodayCount(in: others) }

    /// The list's sections, each under its heading; `nil` for a list that needs none.
    var sections: [(title: String?, todos: [Todo])] {
        let (queued, working, others) = (groups.queued, groups.working, groups.others)
        let today = Self.dueTodayCount(in: others)
        var sections: [(title: String?, todos: [Todo])] = [
            ("For Claude", queued), ("Claude working", working)
        ].filter { !$0.todos.isEmpty }
        let hasHeadings = !sections.isEmpty || today > 0
        if today > 0 {
            sections += [("Today", Array(others.prefix(today))), ("Later", Array(others.dropFirst(today)))]
        } else {
            sections.append((hasHeadings ? "Todos" : nil, others))
        }
        if showsDone { sections.append((hasHeadings ? "Done" : nil, done)) }
        return sections.filter { !$0.todos.isEmpty }
    }

    /// Nothing half-entered that the pointer leaving would throw away.
    var isIdle: Bool {
        draft.isEmpty && !isAddingCategory && editing == nil && menu == nil && query.isEmpty
    }

    /// A todo ticked and then opened in the editor stays until the edit ends, rather than going
    /// from under the cursor. Listed with the done ones, it stays where it is.
    private func isListedOpen(_ todo: Todo) -> Bool {
        !todo.isDone || lingering.contains(todo) || !showsDone && editing == todo
    }

    private var listed: [Todo] { showsDone ? todos : todos.filter(isListedOpen) }

    /// A tag only done todos carry shows while they do.
    var listedTags: [[String]] { listed.map(\.tags) }

    private var filtered: [Todo] {
        todos.filter {
            isShown(carrying: $0.tags) && isFound($0)
        }
    }

    /// In its title or its note; every todo while nothing is searched for.
    private func isFound(_ todo: Todo) -> Bool {
        guard hasQuery else { return true }
        return [TaskText(todo.text).title, todo.note].contains { !TextSearch.ranges(of: query, in: $0).isEmpty }
    }

    /// Adds the todo typed, with the tags the list is narrowed to, so it shows in the list. Of a
    /// filter and one nested under it, only the nested one is added, which carries both.
    func add() {
        var lines = draft.components(separatedBy: "\n")
        if !lines[0].trimmingCharacters(in: .whitespaces).isEmpty {
            lines[0] += lackingFilters(in: TaskText(lines[0]).tags).map { " #\($0)" }.joined()
        }
        onAdd?(lines.joined(separator: "\n"))
        draft = ""
        draftDue = nil
        draftTime = nil
        menu = nil
    }

    /// Saves the todo being changed first, as a click elsewhere does.
    func startEditing(_ todo: Todo, at click: CGPoint? = nil) {
        saveEdit()
        editClick = click
        var text = TaskText(todo.text)
        editDue = text.due
        editTime = text.time
        text.due = nil
        text.time = nil
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
        text.time = text.due == nil ? nil : editTime ?? text.time
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

    /// A todo without a day keeps no time.
    func setDue(of todo: Todo, to due: String?) {
        var text = TaskText(todo.text)
        text.due = due
        if due == nil { text.time = nil }
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

    static let width: CGFloat = 420
    static let maxListHeight: CGFloat = 320
    /// The column the rows' circles stand in, which the field's plus and the editor's circle share.
    static let markWidth: CGFloat = 16

    /// An estimate until the page has been laid out, and its laid-out height from then on.
    var height: CGFloat { contentHeight ?? menuBarHeight + 28 * CGFloat(rows.count + 2) }
}

extension TodoPage: PanelPage {
    var width: CGFloat { Self.width }

    func menuFrame(in panel: CGRect) -> CGRect? {
        menu.map { $0.frame(size: menuSize, under: menuIcon, in: panel) }
    }

    var view: TodoPageView { TodoPageView(page: self) }
    var menuView: RowMenuHost { RowMenuHost(page: self) }
}

struct TodoPageView: View {
    private static let list = "list"
    @Bindable var page: TodoPage
    @FocusState private var isTyping: Bool
    /// How far rows run on past the list's top and bottom, which fade out to show it.
    @State private var aboveTop: CGFloat = 0
    @State private var belowBottom: CGFloat = 0

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
            if $1?.kind != .due {
                page.dueQuery = nil
                page.dueStep = nil
            }
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
            Text("\(page.openCount) open")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Left of the notch, since the page button takes the right.
            if !page.done.isEmpty || page.showsDone {
                Button(page.showsDone ? "Hide done" : "\(page.done.count) done") { page.showsDone.toggle() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help(page.showsDone ? "Hide done todos" : "Show done todos")
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: page.menuBarHeight)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(page.sections, id: \.todos.first?.id) { section in
                    if let title = section.title { heading(title) }
                    ForEach(section.todos) { todo in
                        if page.editing == todo {
                            TodoEditor(page: page, todo: todo)
                        } else {
                            TodoRow(page: page, todo: todo)
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { page.listHeight = $0 }
            // A row's menu closes on scrolling, as a popover does, rather than riding off with its icon.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.list)).minY } action: { _ in
                if page.menu?.line != nil { page.menu = nil }
            }
            .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(Self.list)).minY } action: {
                aboveTop = $0
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                let visible = geometry.bounds(of: .named(Self.list))?.height ?? .infinity
                return geometry.frame(in: .named(Self.list)).maxY - visible
            } action: { belowBottom = $0 }
            .background(OverlayScrollers())
            .background(ScrollMemory(offset: page.scrollOffset) { page.scrollOffset = $0 })
        }
        .coordinateSpace(.named(Self.list))
        .mask(EdgeFade(axis: .vertical, beforeStart: aboveTop, pastEnd: belowBottom, ramp: TodoRow.verticalPadding))
        .frame(height: min(page.listHeight, TodoPage.maxListHeight))
    }

    @ViewBuilder private func heading(_ title: String) -> some View {
        let text = Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
        switch title {
        case "For Claude": withMenu(text, .queue, help: "Right-click to send to Claude")
        case "Claude working": withMenu(text, .working, help: "Right-click to resume Claude's sessions")
        default: text
        }
    }

    private func withMenu(_ heading: some View, _ kind: RowMenu.Kind, help: String) -> some View {
        let menu = RowMenu(line: nil, kind: kind)
        return heading
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(help)
            .modifier(ClickAnchor(point: page.menuClick, isOpen: page.menu == menu))
            .overlay(RightClick { point in
                page.menuClick = point
                page.menu = menu
            })
    }
}

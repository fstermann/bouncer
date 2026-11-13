import MenuBar
import SwiftUI

/// A todo's right-click menu. Hovering an item with an arrow opens its choices beside it, and a
/// click picks one.
struct RowActions: View {
    let page: TodoPage
    let todo: Todo
    @State private var submenu: Submenu?
    /// Each opener's top, which its choices line up with.
    @State private var tops: [Submenu: CGFloat] = [:]

    private enum Submenu { case tags, due }
    nonisolated private static let space = "actions"

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if !todo.isDone {
                    item(todo.isInProgress ? "Mark open" : "Mark in progress", "circle.lefthalf.filled") {
                        page.onMark?(todo, !todo.isInProgress)
                    }
                }
                item(todo.isDone ? "Mark open" : "Mark done", "checkmark.circle") { page.onToggle?(todo) }
                if page.sessions[ClaudeQueue.key(of: todo)] != nil {
                    item("Resume in Terminal", "terminal") { page.onResume?(todo) }
                    item("Abort Claude", "xmark.circle") { page.onAbort?([todo]) }
                }
                item(
                    ClaudeQueue.isForClaude(todo) ? "Remove from Claude" : "Mark for Claude",
                    Image(nsImage: ClaudeMark.image(side: 13)).renderingMode(.template)
                ) {
                    page.toggleTag(ClaudeQueue.tag, of: todo)
                }
                MenuDivider()
                if !page.tags.isEmpty { opener("Tags", "tag", .tags) }
                opener("Due date", "calendar", .due)
                MenuDivider()
                item("Edit", "pencil") { page.startEditing(todo) }
                item("Delete", "trash") { page.onDelete?(todo) }
            }
            .frame(width: 180)
            .menuSurface()
            if let submenu {
                Group {
                    switch submenu {
                    case .tags: tagChoices
                    case .due:
                        let text = TaskText(todo.text)
                        // Left open once a day is picked: the todo moves in the list, and its time is set here.
                        DueChoices(due: text.due, time: text.time) { day, _ in
                            page.setDue(of: todo, to: day)
                            if day == nil { page.menu = nil }
                        } chooseTime: { page.setTime(of: todo, to: $0) }
                    }
                }
                .menuSurface()
                .padding(.top, tops[submenu] ?? 0)
            }
        }
        .coordinateSpace(.named(Self.space))
    }

    private var tagChoices: some View {
        TagChoices(page: page, tags: page.tags.filter { $0 != ClaudeQueue.tag }, carried: todo.tags) {
            page.toggleTag($0, of: todo)
        }
    }

    private func item(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        item(title, Image(systemName: icon), action: action)
    }

    private func item(_ title: String, _ icon: Image, action: @escaping () -> Void) -> some View {
        MenuItem(title: title, icon: icon) {
            page.menu = nil
            action()
        }
        .onHover { if $0 { submenu = nil } }
    }

    private func opener(_ title: String, _ icon: String, _ kind: Submenu) -> some View {
        MenuItem(title: title, icon: Image(systemName: icon), hasArrow: true, isOpen: submenu == kind) {
            submenu = kind
        }
            .onHover { if $0 { submenu = kind } }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY - 4 } action: {
                tops[kind] = $0
            }
    }
}

/// The Claude group's right-click menu: send its todos to Claude Code, a session per repository.
struct QueueActions: View {
    let page: TodoPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(page.queueGroups, id: \.folder) { group in
                let count = group.todos.count == 1 ? "1 todo" : "\(group.todos.count) todos"
                let icon = Image(systemName: "paperplane")
                MenuItem(title: "Send \(count) to Claude", detail: name(of: group.folder), icon: icon) {
                    page.menu = nil
                    page.onSend?(group.todos, group.folder)
                }
            }
        }
        .frame(minWidth: 200)
        .menuSurface()
    }

    private func name(of folder: String) -> String {
        URL(filePath: folder).lastPathComponent
    }
}

/// The working group's right-click menu: pick up or abort each session, or finish them all.
struct WorkingActions: View {
    let page: TodoPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(page.workingSessions, id: \.session.id) { group in
                let count = group.todos.count == 1 ? "1 todo" : "\(group.todos.count) todos"
                let folder = URL(filePath: group.session.folder).lastPathComponent
                MenuItem(title: "Resume \(count)", detail: folder, icon: Image(systemName: "terminal")) {
                    page.menu = nil
                    if let todo = group.todos.first { page.onResume?(todo) }
                }
                MenuItem(title: "Abort \(count)", detail: folder, icon: Image(systemName: "xmark.circle")) {
                    page.menu = nil
                    page.onAbort?(group.todos)
                }
            }
            if !page.workingSessions.isEmpty { MenuDivider() }
            MenuItem(title: "Mark all done", icon: Image(systemName: "checkmark.circle")) {
                page.menu = nil
                page.onFinish?(page.working)
            }
        }
        .frame(minWidth: 200)
        .menuSurface()
    }
}

/// A tag's linked repository, under its colours: Claude works on the tag's todos there.
struct RepositoryLink: View {
    let page: TodoPage
    let tag: String

    var body: some View {
        if let folder = page.repositories[tag] {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text((folder as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .leading)
                Button { page.onLink?(tag, false) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Unlink \(folder)")
            }
            .font(.caption)
            .help(folder)
        } else {
            Button { page.onLink?(tag, true) } label: {
                Label("Link repository…", systemImage: "folder.badge.plus").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Send this tag's todos to Claude in a local repository")
        }
    }
}

/// A row of a menu: an icon, its title, and what it leads to or is set to.
struct MenuItem: View {
    let title: String
    var detail: String?
    let icon: Image
    var iconColor: Color?
    var hasArrow = false
    /// Highlighted, as while its choices are open or the keyboard is on it.
    var isOpen = false
    var isChecked = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.font(iconColor == nil ? nil : .system(size: 7)).frame(width: 16)
                    .foregroundStyle(iconColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                Text(title)
                Spacer(minLength: 12)
                if let detail { Text(detail).foregroundStyle(.secondary).lineLimit(1) }
                if hasArrow { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                if isChecked { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(isHovered || isOpen ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
    }
}

extension View {
    /// The look the row menus share.
    func menuSurface() -> some View {
        padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
    }
}

/// Tags as menu rows: a dot in each one's colour, nested ones indented under the tag above, and a
/// check on those carried.
struct TagChoices: View {
    let page: TodoPage
    let tags: [String]
    let carried: [String]
    let toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tags, id: \.self) { tag in
                let depth = TagPath.lineage(of: tag).count - 1
                MenuItem(
                    title: TagPath.leaf(of: tag), icon: Image(systemName: "circle.fill"),
                    iconColor: page.color(of: tag) ?? .white.opacity(0.35), isChecked: carried.contains(tag)
                ) { toggle(tag) }
                    .padding(.leading, CGFloat(depth) * 14)
            }
        }
        .frame(minWidth: 160)
    }
}

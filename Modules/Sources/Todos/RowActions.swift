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
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                if !todo.isDone {
                    item(todo.isInProgress ? "Mark open" : "Mark in progress", "circle.lefthalf.filled") {
                        page.onMark?(todo, !todo.isInProgress)
                    }
                }
                item(todo.isDone ? "Mark open" : "Mark done", "checkmark.circle") { page.onToggle?(todo) }
                if page.sessions[ClaudeQueue.key(of: todo)] != nil {
                    item("Resume in Terminal", "terminal") { page.onResume?(todo) }
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
                VStack(alignment: .leading, spacing: 4) {
                    switch submenu {
                    case .tags: tagChoices
                    case .due:
                        let text = TaskText(todo.text)
                        DueChoices(due: text.due, time: text.time) { day, closes in
                            page.setDue(of: todo, to: day)
                            if closes { page.menu = nil }
                        } chooseTime: { page.setTime(of: todo, to: $0) }
                    }
                }
                .padding(8)
                .menuSurface()
                .frame(maxWidth: 240, alignment: .leading)
                .padding(.top, tops[submenu] ?? 0)
            }
        }
        .coordinateSpace(.named(Self.space))
    }

    private var tagChoices: some View {
        ForEach(page.tags.filter { $0 != ClaudeQueue.tag }, id: \.self) { tag in
            Button { page.toggleTag(tag, of: todo) } label: {
                Chip(tag: tag, color: page.color(of: tag), isSelected: todo.tags.contains(tag))
            }
            .buttonStyle(.plain)
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

/// The working group's right-click menu: pick up each session in Terminal, or finish them all.
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
                Text(URL(filePath: folder).lastPathComponent).lineLimit(1).truncationMode(.middle)
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

private struct MenuItem: View {
    let title: String
    var detail: String?
    let icon: Image
    var hasArrow = false
    var isOpen = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 16).foregroundStyle(.secondary)
                Text(title)
                Spacer(minLength: 12)
                if let detail { Text(detail).foregroundStyle(.secondary).lineLimit(1) }
                if hasArrow { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
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

private struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
    }
}

extension View {
    /// The look the row menus share.
    func menuSurface() -> some View {
        padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
    }
}

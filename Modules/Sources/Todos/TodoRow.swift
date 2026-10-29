import AppKit
import SwiftUI

struct TodoRow: View {
    let page: TodoPage
    let todo: Todo
    @State private var isHovered = false
    @State private var height: CGFloat = 0
    static let verticalPadding: CGFloat = 6

    var body: some View {
        let text = TaskText(todo.text)
        let isDeleting = page.deleting.contains(todo)
        let showsAccessory = isDeleting || isHovered || page.menu?.line == todo.line
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { if !isDeleting { page.onToggle?(todo) } } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .frame(width: TodoPage.markWidth)
                    .foregroundStyle(isDeleting ? .red : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                // Tags beside a title that fits on one line with them; otherwise on a line of their own,
                // so the title keeps the row's width.
                ViewThatFits(in: .horizontal) {
                    titleLine(text, isDeleting: isDeleting, showsTags: true)
                    VStack(alignment: .leading, spacing: 4) {
                        titleLine(text, isDeleting: isDeleting, showsTags: false)
                        if !text.tags.isEmpty { HStack(spacing: 6) { tagChips(text) } }
                    }
                }
                // Laid over the first line rather than beside it, so showing them cannot rewrap the title.
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    if showsAccessory {
                        accessory(isDeleting: isDeleting)
                            .padding(.leading, 28)
                            // Taller than the icons, to cover a chip's capsule too.
                            .background(backdrop.padding(.vertical, -4))
                    }
                }
                if !todo.note.isEmpty {
                    // Its own tap, which wins over the row's, so reading a note does not edit it.
                    Text(page.marked(todo.note))
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
        .padding(.vertical, Self.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isHovered ? 0.06 : 0)).padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .onHover { isHovered = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }

    private func titleLine(_ text: TaskText, isDeleting: Bool, showsTags: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(page.marked(text.title))
                .lineLimit(3)
                .truncationMode(.tail)
                .strikethrough(todo.isDone || isDeleting)
                .foregroundStyle(isDeleting ? .red : todo.isDone ? .secondary : .primary)
                // The cursor goes where the title was clicked; elsewhere on the row, to its end.
                .onTapGesture {
                    edit(at: NSApp.currentEvent?.locationInWindow)
                }
            if showsTags { tagChips(text) }
            Spacer(minLength: 0)
            if let due = text.due {
                let label = TaskDay.label(for: due, today: Date())
                Text(label.text)
                    .font(.caption)
                    .foregroundStyle(label.isOverdue && !todo.isDone ? .red : .secondary)
            }
        }
    }

    private func tagChips(_ text: TaskText) -> some View {
        ForEach(text.tags, id: \.self) { Chip(tag: $0, color: page.color(of: $0)).fixedSize() }
    }

    private func edit(at click: CGPoint? = nil) {
        guard !page.deleting.contains(todo) else { return }
        page.startEditing(todo, at: click)
        page.editHeight = height
    }

    /// The row's own fill, fading in from the left and solid a little before the icons, so they
    /// hide what they lie over.
    private var backdrop: some View {
        ZStack {
            Color.black
            Color.white.opacity(isHovered ? 0.06 : 0)
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 20)
                Color.black
            }
        }
    }

    @ViewBuilder private func accessory(isDeleting: Bool) -> some View {
        if isDeleting {
            Button { page.onRestore?(todo) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Undo delete")
        } else {
            actions
        }
    }

    private var actions: some View {
        // In the input row's order, so tag and calendar sit where they do under the list.
        HStack(spacing: 10) {
            if !page.tags.isEmpty {
                MenuButton(page: page, menu: RowMenu(line: todo.line, kind: .tags), help: "Set tags") {
                    Image(systemName: "tag")
                }
            }
            MenuButton(page: page, menu: RowMenu(line: todo.line, kind: .due), help: "Set a due date") {
                Image(systemName: "calendar")
            }
            Button { page.onDelete?(todo) } label: { Image(systemName: "trash") }
                .help("Delete")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

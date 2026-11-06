import AppKit
import MenuBar
import SwiftUI

struct TodoRow: View {
    let page: TodoPage
    let todo: Todo
    @State private var isHovered = false
    /// Hovered long enough to be read: its title and note show in full.
    @State private var isRead = false
    @State private var reading: Task<Void, Never>?
    @State private var height: CGFloat = 0
    static let verticalPadding: CGFloat = 6
    private static let readDelay: Duration = .milliseconds(800)

    var body: some View {
        let text = TaskText(todo.text)
        let isDeleting = page.deleting.contains(todo)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { if !isDeleting { page.onToggle?(todo) } } label: {
                StatusMark(todo: todo)
                    .foregroundStyle(isDeleting ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help("Right-click to mark in progress")
            VStack(alignment: .leading, spacing: 2) {
                // Tags beside a title that fits on one line with them; otherwise on a line of their own,
                // so the title keeps the row's width.
                ViewThatFits(in: .horizontal) {
                    titleLine(text, isDeleting: isDeleting, showsTags: true)
                    VStack(alignment: .leading, spacing: 4) {
                        titleLine(text, isDeleting: isDeleting, showsTags: false)
                        if !shownTags(text).isEmpty { HStack(spacing: 6) { tagChips(text) } }
                    }
                }
                // Laid over the first line rather than beside it, so showing them cannot rewrap the title.
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    if isDeleting {
                        undoDelete
                            .padding(.leading, 28)
                            // Taller than the icons, to cover a chip's capsule too.
                            .background(backdrop.padding(.vertical, -4))
                    }
                }
                let note = ImageEmbed.stripped(todo.note)
                if !note.isEmpty {
                    // Its own tap, which wins over the row's, so reading a note does not edit it.
                    Text(page.marked(note))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isRead || page.expanded.contains(todo.line) ? nil : 1)
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
        .modifier(ClickAnchor(point: page.menuClick, isOpen: page.menu == actions))
        .overlay(RightClick(action: rightClick))
        .onHover(perform: hover)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }

    private func titleLine(_ text: TaskText, isDeleting: Bool, showsTags: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(page.marked(ImageEmbed.stripped(text.title)))
                .lineLimit(isRead ? nil : 3)
                .truncationMode(.tail)
                .strikethrough(todo.isDone || isDeleting)
                .foregroundStyle(isDeleting ? .red : todo.isDone ? .secondary : .primary)
                // The cursor goes where the title was clicked; elsewhere on the row, to its end.
                .onTapGesture {
                    edit(at: NSApp.currentEvent?.locationInWindow)
                }
            if let images = page.images {
                ForEach(ImageEmbed.names(in: todo.text + "\n" + todo.note), id: \.self) { name in
                    ImagePreview(name: name, images: images).font(.caption)
                }
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

    private var actions: RowMenu { RowMenu(line: todo.line, kind: .actions) }

    /// On the circle, takes the todo in or out of progress; anywhere else, opens its actions there.
    private func rightClick(at point: CGPoint) {
        guard !page.deleting.contains(todo) else { return }
        if point.x < Self.circleEdge {
            page.menu = nil
            page.onMark?(todo, !todo.isInProgress)
        } else {
            page.menuClick = point
            page.menu = page.menu == actions ? nil : actions
        }
    }

    /// Past the circle and the space after it, from the row's left edge.
    private static let circleEdge: CGFloat = 14 + TodoPage.markWidth + 4

    /// Without `#claude`, which the todo's group and circle already show.
    private func shownTags(_ text: TaskText) -> [String] {
        text.tags.filter { $0 != ClaudeQueue.tag }
    }

    private func tagChips(_ text: TaskText) -> some View {
        ForEach(shownTags(text), id: \.self) { Chip(tag: $0, color: page.color(of: $0)).fixedSize() }
    }

    private func hover(_ isInside: Bool) {
        isHovered = isInside
        reading?.cancel()
        guard isInside else {
            if isRead { withAnimation(.snappy) { isRead = false } }
            return
        }
        reading = Task {
            try? await Task.sleep(for: Self.readDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { isRead = true }
        }
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

    private var undoDelete: some View {
        Button { page.onRestore?(todo) } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Undo delete")
    }
}

/// A todo's circle: open, in progress, with Claude, or done.
struct StatusMark: View {
    let todo: Todo

    var body: some View {
        Group {
            if todo.isDone {
                Image(systemName: "checkmark.circle.fill")
            } else if todo.isInProgress && ClaudeQueue.isForClaude(todo) {
                Image(nsImage: ClaudeMark.image(side: 13)).renderingMode(.template)
            } else if todo.isInProgress {
                Image(systemName: "circle.lefthalf.filled")
            } else {
                Image(systemName: "circle")
            }
        }
        .frame(width: TodoPage.markWidth)
    }
}

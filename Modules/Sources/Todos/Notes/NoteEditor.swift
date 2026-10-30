import AppKit
import SwiftUI

/// The names used across the notes so far, offered while one is typed.
struct NoteSuggestions {
    var people: [String] = []
    var projects: [String] = []
    var tags: [String] = []
    var tagColors: [String: String] = [:]

    @MainActor init(_ page: NotePage) {
        people = page.people
        projects = page.projects
        tags = page.tags
        tagColors = page.tagColors
    }

    init() {}

    func color(of tag: String) -> Color? {
        TagColor.of(tag, in: tagColors)
    }
}

/// A meeting's note: its title, when it ran, who came, its project, place and tags, and the note
/// itself. Every change is saved as it is made.
struct NoteEditor: View {
    @Bindable var draft: NoteDraft
    let known: NoteSuggestions
    let onEdit: (NoteDraft) -> Void
    /// `nil` in a window of its own, which has neither a list to go back to nor anywhere to pop out to.
    var onBack: (() -> Void)?
    var onPopOut: (() -> Void)?
    let onDelete: () -> Void
    /// Fills its window rather than keeping the panel's height.
    var fillsHeight = false
    @FocusState private var isWritingBody: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 6) {
                times
                MetaRow(symbol: "person.2", help: "People") {
                    ChipField(
                        placeholder: "People", items: $draft.people,
                        offered: { ListCompletion.suggestions(for: $0, carrying: $1, from: known.people) },
                        item: ListCompletion.name(from:)
                    )
                }
                HStack(spacing: 12) {
                    MetaRow(symbol: "folder", help: "Project") {
                        ChipField(
                            placeholder: "Project", items: project,
                            offered: { ListCompletion.suggestions(for: $0, carrying: $1, from: known.projects) },
                            item: ListCompletion.name(from:), isSingle: true
                        )
                    }
                    MetaRow(symbol: "link", help: "Room or call link") {
                        HStack(spacing: 4) {
                            TextField("Room or link", text: $draft.location).textFieldStyle(.plain)
                            if let link = draft.link {
                                Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("Open link")
                            }
                        }
                    }
                }
                MetaRow(symbol: "tag", help: "Tags") {
                    ChipField(
                        placeholder: "Tags", items: $draft.tags,
                        offered: { TagCompletion.suggestions(for: $0, carrying: $1, from: known.tags) },
                        item: TagCompletion.tag(from:), breaks: " ,", color: known.color(of:)
                    )
                }
            }
            .font(.callout)
            Divider().overlay(.white.opacity(0.1))
            TextEditor(text: $draft.body)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($isWritingBody)
                .frame(height: fillsHeight ? nil : NotePage.bodyHeight)
                .frame(maxHeight: fillsHeight ? .infinity : nil)
                .background(OverlayScrollers())
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .onChange(of: draft.note) { onEdit(draft) }
        .onChange(of: draft.bodyFocusRequests, initial: true) {
            // A turn later, once the editor is in the window: focus set before then is lost.
            if $1 > 0 { Task { isWritingBody = true } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .help("All meetings")
            }
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.headline)
                .onSubmit { draft.bodyFocusRequests += 1 }
            if let onPopOut {
                Button(action: onPopOut) { Image(systemName: "macwindow.on.rectangle") }
                    .help("Open in a window")
            }
            Button(action: onDelete) { Image(systemName: "trash") }
                .help("Move to Trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var times: some View {
        MetaRow(symbol: "clock", help: "When") { NoteTimes(draft: draft) }
    }

    /// The project as the one chip its field holds.
    private var project: Binding<[String]> {
        Binding { draft.project.isEmpty ? [] : [draft.project] } set: { draft.project = $0.last ?? "" }
    }

    static func minute(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
    }
}

/// One of a meeting's properties, behind its symbol.
private struct MetaRow<Content: View>: View {
    let symbol: String
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: TodoPage.markWidth)
                .foregroundStyle(.tertiary)
                .help(help)
            content
        }
    }
}

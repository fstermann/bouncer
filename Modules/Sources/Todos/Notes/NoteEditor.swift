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
    @FocusState private var isTypingLocation: Bool
    /// Empty properties shown since their adder was clicked.
    @State private var revealed: Set<Field> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 6) {
                times
                if shows(.people) {
                    MetaRow(symbol: Field.people.symbol, help: "People") {
                        ChipField(
                            placeholder: "People", items: $draft.people,
                            offered: { ListCompletion.suggestions(for: $0, carrying: $1, from: known.people) },
                            item: ListCompletion.name(from:), focusesOnAppear: revealed.contains(.people)
                        )
                    }
                }
                if shows(.project) || shows(.link) {
                    HStack(spacing: 12) {
                        if shows(.project) {
                            MetaRow(symbol: Field.project.symbol, help: "Project") {
                                ChipField(
                                    placeholder: "Project", items: project,
                                    offered: {
                                        ListCompletion.suggestions(for: $0, carrying: $1, from: known.projects)
                                    },
                                    item: ListCompletion.name(from:), isSingle: true,
                                    focusesOnAppear: revealed.contains(.project)
                                )
                            }
                        }
                        if shows(.link) { location }
                    }
                }
                if shows(.tags) {
                    MetaRow(symbol: Field.tags.symbol, help: "Tags") {
                        ChipField(
                            placeholder: "Tags", items: $draft.tags,
                            offered: { TagCompletion.suggestions(for: $0, carrying: $1, from: known.tags) },
                            item: TagCompletion.tag(from:), breaks: " ,", color: known.color(of:),
                            focusesOnAppear: revealed.contains(.tags)
                        )
                    }
                }
                adders
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

    /// The properties left out while empty, added from the row under the others.
    private enum Field: CaseIterable {
        case people, project, link, tags

        var symbol: String {
            switch self {
            case .people: "person.2"
            case .project: "folder"
            case .link: "link"
            case .tags: "tag"
            }
        }

        var title: String {
            switch self {
            case .people: "People"
            case .project: "Project"
            case .link: "Room or link"
            case .tags: "Tags"
            }
        }
    }

    private func shows(_ field: Field) -> Bool {
        guard !revealed.contains(field) else { return true }
        return switch field {
        case .people: !draft.people.isEmpty
        case .project: !draft.project.isEmpty
        case .link: !draft.location.isEmpty
        case .tags: !draft.tags.isEmpty
        }
    }

    @ViewBuilder private var adders: some View {
        let hidden = Field.allCases.filter { !shows($0) }
        if !hidden.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "plus")
                    .frame(width: TodoPage.markWidth)
                    .foregroundStyle(.tertiary)
                ForEach(hidden, id: \.self) { field in
                    Button {
                        revealed.insert(field)
                        // A turn later, once the field is in the window.
                        if field == .link { Task { isTypingLocation = true } }
                    } label: {
                        Label(field.title, systemImage: field.symbol)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var location: some View {
        MetaRow(symbol: Field.link.symbol, help: "Room or call link") {
            HStack(spacing: 4) {
                TextField("Room or link", text: $draft.location)
                    .textFieldStyle(.plain)
                    .focused($isTypingLocation)
                if let link = draft.link {
                    Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Open link")
                }
            }
        }
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

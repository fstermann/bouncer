import AppKit
import SwiftUI

/// The names used across the notes so far, offered while one is typed.
struct NoteSuggestions {
    var people: [String] = []
    var projects: [String] = []
    var tags: [String] = []

    @MainActor init(_ page: NotePage) {
        people = page.people
        projects = page.projects
        tags = page.tags
    }

    init() {}
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
                    ListField(placeholder: "People", text: $draft.people, known: known.people)
                }
                HStack(spacing: 12) {
                    MetaRow(symbol: "folder", help: "Project") {
                        ListField(placeholder: "Project", text: $draft.project, known: known.projects, isList: false)
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
                    ListField(placeholder: "Tags", text: $draft.tagText, known: known.tags)
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
        .onChange(of: draft.bodyFocusRequests, initial: true) { if $1 > 0 { isWritingBody = true } }
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

    /// When it started and, once ended, when it ended and how long it ran.
    private var times: some View {
        MetaRow(symbol: "clock", help: "When") {
            HStack(spacing: 6) {
                DatePicker("Start", selection: $draft.start)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .fixedSize()
                Text("–").foregroundStyle(.secondary)
                if let end = draft.end {
                    let ending = Binding { end } set: { draft.end = $0 }
                    DatePicker("End", selection: ending, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .fixedSize()
                    if let duration = NoteTime.duration(from: draft.start, to: end) {
                        Text(duration).foregroundStyle(.secondary)
                    }
                } else {
                    Button("End now") { draft.end = Self.minute(of: Date()) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Note when the meeting ended")
                }
                Spacer(minLength: 0)
            }
        }
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

/// A comma-separated list, or with `isList` off a single name, offering the names already used for
/// the one being typed: Tab takes the first, a click any of them.
private struct ListField: View {
    let placeholder: String
    @Binding var text: String
    let known: [String]
    var isList = true
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onKeyPress(.tab) {
                    guard let first = suggestions.first else { return .ignored }
                    take(first)
                    return .handled
                }
            if isFocused, !suggestions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(suggestions.prefix(5), id: \.self) { name in
                        Button { take(name) } label: { Chip(text: name) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var suggestions: [String] {
        ListCompletion.suggestions(for: isList ? text : text.replacingOccurrences(of: ",", with: " "), from: known)
    }

    private func take(_ name: String) {
        text = isList ? ListCompletion.completing(text, with: name) : name
    }
}

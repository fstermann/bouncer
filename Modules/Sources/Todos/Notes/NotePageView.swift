import Settings
import SwiftUI

struct NotePageView: View {
    private static let list = "list"
    @Bindable var page: NotePage
    @FocusState private var isTyping: Bool
    @State private var aboveTop: CGFloat = 0
    @State private var belowBottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if let draft = page.editing {
                NoteEditor(
                    draft: draft, known: NoteSuggestions(page), onEdit: { page.onEdit?($0) },
                    onBack: { page.onBack?() }, onPopOut: { page.onPopOut?() },
                    onDelete: { page.onDelete?(draft.saved) }
                )
                .id(draft.id)
            } else {
                TagRow(page: page, isTyping: $isTyping)
                list
                inputRow
            }
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
            Text(page.notes.count == 1 ? "1 meeting" : "\(page.notes.count) meetings")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The notch lies between the count and the rest.
            Spacer()
            PageSwitches(pages: page.switches) { page.onSwitch?($0) }
        }
        .padding(.horizontal, 14)
        .frame(height: page.menuBarHeight)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(page.groups, id: \.title) { group in
                    Text(group.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(group.notes) { note in
                        NoteRow(page: page, note: note, showsDay: !Self.isDay(group.title, of: note, now: page.now))
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { page.listHeight = $0 }
            .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(Self.list)).minY } action: {
                aboveTop = $0
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                let visible = geometry.bounds(of: .named(Self.list))?.height ?? .infinity
                return geometry.frame(in: .named(Self.list)).maxY - visible
            } action: { belowBottom = $0 }
            .background(OverlayScrollers())
        }
        .coordinateSpace(.named(Self.list))
        .mask(EdgeFade(axis: .vertical, beforeStart: aboveTop, pastEnd: belowBottom, ramp: TodoRow.verticalPadding))
        .frame(height: min(page.listHeight, NotePage.maxListHeight))
    }

    /// Whether the heading already names the note's day, so its row needs only the time.
    private static func isDay(_ title: String, of note: Note, now: Date) -> Bool {
        guard let day = note.day else { return true }
        return Calendar.current.isDate(day, equalTo: now, toGranularity: .weekOfYear)
            || Calendar.current.isDateInYesterday(day)
    }

    private var inputRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "plus")
                .frame(width: TodoPage.markWidth)
                .foregroundStyle(.tertiary)
            TextField("Start a meeting", text: $page.draft)
                .textFieldStyle(.plain)
                .focused($isTyping)
                .onSubmit(page.create)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .onChange(of: page.focusRequests, initial: true) { isTyping = true }
    }
}

/// The other pages of the notch panel, one icon each.
struct PageSwitches: View {
    let pages: [NotchPage]
    let action: (NotchPage) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(pages, id: \.self) { page in
                Button { action(page) } label: { Image(systemName: page.symbol) }
                    .help(page.help)
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

extension NotchPage {
    public var symbol: String {
        switch self {
        case .items: "menubar.rectangle"
        case .todos: "checklist"
        case .notes: "note.text"
        }
    }

    public var help: String {
        switch self {
        case .items: "Show hidden items"
        case .todos: "Show todos"
        case .notes: "Show meeting notes"
        }
    }
}

struct NoteRow: View {
    let page: NotePage
    let note: Note
    /// Off under a heading that names the day already.
    let showsDay: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "note.text")
                .frame(width: TodoPage.markWidth)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(page.marked(note.title))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ForEach(note.tags, id: \.self) { Chip(tag: $0, color: page.color(of: $0)).fixedSize() }
                    Spacer(minLength: 0)
                    if isHovered {
                        Button { page.onDelete?(note) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .help("Move to Trash")
                    } else {
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !detail.isEmpty {
                    Text(page.marked(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let snippet {
                    Text(page.marked(snippet))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, TodoRow.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isHovered ? 0.06 : 0)).padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { page.onOpen?(note) }
        .onHover { isHovered = $0 }
    }

    /// When it started, how long it ran, and the day too where the heading does not name it.
    private var time: String {
        guard let start = note.start else { return "" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(showsDay ? "MMMd jj:mm" : "jj:mm")
        return ([formatter.string(from: start)] + [NoteTime.duration(from: start, to: note.end)].compactMap(\.self))
            .joined(separator: " · ")
    }

    private var detail: String {
        ([note.attendees.joined(separator: ", ")] + [note.project].compactMap(\.self))
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The line of the note's text the search found, while nothing else shown holds it.
    private var snippet: String? {
        guard page.hasQuery, TextSearch.ranges(of: page.query, in: note.title + " " + detail).isEmpty else {
            return nil
        }
        return note.body.components(separatedBy: "\n")
            .first { !TextSearch.ranges(of: page.query, in: $0).isEmpty }?
            .trimmingCharacters(in: .whitespaces)
    }
}

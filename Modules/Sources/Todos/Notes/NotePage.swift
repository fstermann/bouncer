import Observation
import Settings
import SwiftUI

/// A note open in the editor, in the panel or a window of its own, as it is being changed.
@MainActor
@Observable
final class NoteDraft: Identifiable {
    /// What was last saved, under its file's name, which follows the title once the editing ends.
    var saved: Note
    /// As it was opened, before any change.
    let opened: Note
    var title: String
    var start: Date
    var end: Date?
    var people: [String]
    var project: String
    var location: String
    var tags: [String]
    var body: String
    /// Bumped to put the cursor in the note's text. One from the start, so a note opens with the
    /// cursor there rather than its whole title selected.
    var bodyFocusRequests = 1
    /// An image to put in at the cursor, as a screenshot taken from the header is.
    var embedRequest: EmbedRequest?

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(_ note: Note) {
        saved = note
        opened = note
        title = note.title
        start = note.start ?? note.modified ?? Date()
        end = note.end
        people = note.attendees
        project = note.project ?? ""
        location = note.location ?? ""
        tags = note.tags
        body = note.body
    }

    /// The note as it now stands.
    var note: Note {
        var note = saved
        note.title = title.trimmingCharacters(in: .whitespaces)
        // A note opened without a start gets one only once it is set.
        note.start = opened.start == nil && start == (opened.modified ?? start) ? nil : start
        note.end = end
        note.attendees = people
        note.project = project.trimmingCharacters(in: .whitespaces).nilIfEmpty
        note.location = location.trimmingCharacters(in: .whitespaces).nilIfEmpty
        note.tags = tags
        note.body = body
        return note
    }

    /// The location as a link to open, once it is one.
    var link: URL? {
        guard let url = URL(string: location.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true
        else { return nil }
        return url
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// What the notes page shows: the meetings so far, newest first, or the one open in the editor.
@MainActor
@Observable
final class NotePage: TagFiltering {
    var notes: [Note] = []
    var categories: [String] { [] }
    var tagColors: [String: String] = [:]
    var tagOrder: [String] = []
    var filters: Set<String> = []
    var showsUntagged = false
    var isAddingCategory = false
    var categoryDraft = ""
    var isSearching = false
    var query = ""
    var searchFocusRequests = 0
    var focusRequests = 0
    /// Only a tag's colours open, under its chip.
    var menu: RowMenu?
    @ObservationIgnored var menuIcon: CGRect = .zero
    @ObservationIgnored var menuSize: CGSize = .zero
    /// The title of the meeting being started.
    var draft = ""
    var editing: NoteDraft?
    var menuBarHeight: CGFloat = 24
    var listHeight: CGFloat = 0
    var contentHeight: CGFloat?
    /// Now, as of the panel opening, which the list's headings are reckoned from.
    var now = Date()

    /// The presentation timer, which outlives the panel.
    @ObservationIgnored var clock: PresentationClock?
    /// Where pasted images are saved and read back from; `nil` while the page is closed.
    @ObservationIgnored var images: PastedImages?
    /// Takes a screenshot and returns its embed; `nil` while screenshots are off.
    @ObservationIgnored var onScreenshot: TakeScreenshot?
    @ObservationIgnored var onCreate: (@MainActor (String) -> Void)?
    @ObservationIgnored var onOpen: (@MainActor (Note) -> Void)?
    /// Back to the list from the editor.
    @ObservationIgnored var onBack: (@MainActor () -> Void)?
    @ObservationIgnored var onEdit: (@MainActor (NoteDraft) -> Void)?
    @ObservationIgnored var onDelete: (@MainActor (Note) -> Void)?
    @ObservationIgnored var onArchive: (@MainActor (Note) -> Void)?
    @ObservationIgnored var onPopOut: (@MainActor () -> Void)?
    @ObservationIgnored var onColor: (@MainActor (String, String?) -> Void)?
    @ObservationIgnored var onOrder: (@MainActor ([String]) -> Void)?
    @ObservationIgnored var onResize: (@MainActor () -> Void)?
    var onAddCategory: (@MainActor (String) -> Void)? { nil }
    var onRemoveCategory: (@MainActor (String) -> Void)? { nil }

    /// An archived note counts only towards its `archived` chip, until that chip is picked.
    var listedTags: [[String]] { notes.map { isListed($0) ? $0.tags : [Note.archivedTag] } }

    /// The notes the filters and the search leave, under headings by when they took place.
    var groups: [NoteGroups.Group] {
        NoteGroups.grouped(
            notes.filter { isListed($0) && isShown(carrying: $0.tags) && (!hasQuery || $0.mentions(query)) }, now: now
        )
    }

    private func isListed(_ note: Note) -> Bool {
        !note.isArchived || filters.contains(Note.archivedTag)
    }

    var people: [String] { ListCompletion.known(in: notes.map(\.attendees)) }
    /// Each project and the folders it is nested in, so `Work` is offered as well as `Work/Bouncer`.
    var projects: [String] { ListCompletion.known(in: notes.map { $0.project.map(TagPath.lineage) ?? [] }) }

    /// Nothing half-entered that the pointer leaving would throw away, and no note open, which a
    /// meeting is still being written into.
    var isIdle: Bool { draft.isEmpty && editing == nil && menu == nil && query.isEmpty }

    /// Starts a meeting now, with the tags the list is narrowed to, so it shows in the list.
    func create() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        draft = ""
        onCreate?(title)
    }

    static let width: CGFloat = 460
    static let maxListHeight: CGFloat = 360
    static let bodyHeight: CGFloat = 300

    var height: CGFloat { contentHeight ?? menuBarHeight + (editing == nil ? 120 : Self.bodyHeight + 160) }
}

extension NotePage: PanelPage {
    var width: CGFloat { Self.width }

    func menuFrame(in panel: CGRect) -> CGRect? {
        menu.map { $0.frame(size: menuSize, under: menuIcon, in: panel) }
    }

    var view: NotePageView { NotePageView(page: self) }
    var menuView: NoteMenuHost { NoteMenuHost(page: self) }
}

/// A tag's colours, under its chip, beside the panel so they can hang past its edge.
struct NoteMenuHost: View {
    let page: NotePage

    var body: some View {
        if let menu = page.menu, case .colors(let tag) = menu.kind {
            Palette(page: page, tag: tag)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
                .id(menu)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    page.menuSize = size
                    page.onResize?()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
        }
    }
}

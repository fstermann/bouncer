import Observation
import SwiftUI

/// A page whose list is narrowed by tag chips and searched, as the todo and the notes pages are.
/// Tags nest, colours and chip order are shared between the two, and both search alike.
@MainActor
protocol TagFiltering: AnyObject, Observable {
    /// Offered as filters even before any item carries them.
    var categories: [String] { get }
    /// The tags of each item listed, before filtering.
    var listedTags: [[String]] { get }
    /// Tag to colour name, from the preferences.
    var tagColors: [String: String] { get set }
    /// The order the tags' chips were dragged into, from the preferences.
    var tagOrder: [String] { get set }
    /// The tags the list is narrowed to: it shows the items carrying all of them.
    var filters: Set<String> { get set }
    /// The list is narrowed to items carrying no tag, which no tag filter can join.
    var showsUntagged: Bool { get set }
    var isAddingCategory: Bool { get set }
    var categoryDraft: String { get set }
    /// The items are being searched for `query`, which narrows the list and is marked in it.
    var isSearching: Bool { get set }
    var query: String { get set }
    /// Bumped to put the cursor back in the search field.
    var searchFocusRequests: Int { get set }
    /// Bumped to put the cursor back in the page's main field.
    var focusRequests: Int { get set }
    /// The choices open under one of the page's controls.
    var menu: RowMenu? { get set }
    /// `nil` where tags cannot be added from the chips.
    var onAddCategory: (@MainActor (String) -> Void)? { get }
    var onRemoveCategory: (@MainActor (String) -> Void)? { get }
    var onColor: (@MainActor (String, String?) -> Void)? { get }
    /// The order the chips were dragged into, once the drag ends.
    var onOrder: (@MainActor ([String]) -> Void)? { get }
    var onResize: (@MainActor () -> Void)? { get }
}

extension TagFiltering {
    /// The categories and any other tag a listed item carries, each once and after the tags it is
    /// nested under, in the order they were dragged into.
    var tags: [String] {
        var seen = Set<String>()
        let found = (categories + listedTags.flatMap(\.self))
            .flatMap(TagPath.lineage).filter { seen.insert($0).inserted }
        return TagPath.sorted(found, by: tagOrder)
    }

    /// Moves `tag`'s chip to where `target`'s stands, if both sit under the same tag.
    func moveTag(_ tag: String, onto target: String) {
        tagOrder = TagPath.moving(tag, onto: target, in: tags, order: tagOrder)
    }

    /// The tags offered as chips, the selected filters first. Nested tags are offered once the tag
    /// above them is selected, ahead of the rest; those under the deepest selected tag even before
    /// any item carries them. Once some are selected, only the other tags that narrow the list
    /// further are offered with them.
    var chipTags: [String] {
        let shown = tags.filter { !filters.contains($0) && (TagPath.parent(of: $0).map(filters.contains) ?? true) }
        let offered = shown.filter {
            filters.isEmpty || count(of: $0) > 0 || TagPath.parent(of: $0).map(deepestFilters.contains) == true
        }
        let nested = offered.filter { TagPath.parent(of: $0) != nil }
        return tags.filter(filters.contains) + nested + offered.filter { TagPath.parent(of: $0) == nil }
    }

    /// The categories that are `tag` or nested under it, which deleting its chip deletes.
    func categories(under tag: String) -> [String] {
        categories.filter { TagPath.matches($0, tag) }
    }

    /// The selected tags no other selected tag is nested under, which between them carry all the filters.
    var deepestFilters: Set<String> {
        filters.filter { filter in !filters.contains { $0 != filter && TagPath.matches($0, filter) } }
    }

    /// How many listed items carry `tag`, or a tag under it, beside the selected filters.
    func count(of tag: String) -> Int {
        listedTags.filter { carriesFilters($0) && $0.contains { TagPath.matches($0, tag) } }.count
    }

    var untaggedCount: Int { listedTags.filter(\.isEmpty).count }

    /// Offered only beside tags, while some item has none, and while no tag is selected, which no
    /// untagged item could carry.
    var offersUntagged: Bool { !tags.isEmpty && untaggedCount > 0 && filters.isEmpty }

    func toggleFilter(_ tag: String) {
        showsUntagged = false
        // The tags under it were offered only beside it, so they go with it.
        if filters.contains(tag) { filters = filters.filter { !TagPath.matches($0, tag) } } else { filters.insert(tag) }
    }

    func toggleUntagged() {
        filters = []
        showsUntagged.toggle()
    }

    /// Whether an item carrying `tags` is listed under the filters, or as untagged.
    func isShown(carrying tags: [String]) -> Bool {
        showsUntagged ? tags.isEmpty : carriesFilters(tags)
    }

    func carriesFilters(_ tags: [String]) -> Bool {
        filters.allSatisfy { filter in tags.contains { TagPath.matches($0, filter) } }
    }

    /// The deepest filters `tags` does not already carry, which an item added under them takes.
    func lackingFilters(in tags: [String]) -> [String] {
        deepestFilters.filter { filter in !tags.contains { TagPath.matches($0, filter) } }.sorted()
    }

    func openSearch() {
        isSearching = true
        searchFocusRequests += 1
    }

    /// Forgets the search, and gives the cursor back to the page's field.
    func closeSearch() {
        guard isSearching else { return }
        isSearching = false
        query = ""
        focusRequests += 1
    }

    /// Something is searched for.
    var hasQuery: Bool { isSearching && !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// `text` with what the search found in it marked.
    func marked(_ text: String) -> AttributedString {
        var marked = AttributedString(text)
        guard isSearching else { return marked }
        for range in TextSearch.ranges(of: query, in: text) {
            guard let found = Range(range, in: marked) else { continue }
            marked[found].backgroundColor = .yellow.opacity(0.4)
        }
        return marked
    }

    /// A nested tag without a colour of its own takes the one of the tag above it.
    func color(of tag: String) -> Color? {
        tagColors[tag].flatMap(TagColor.init(rawValue:))?.color ?? TagPath.parent(of: tag).flatMap(color)
    }

    func setColor(_ color: TagColor, of tag: String) {
        let name = color == .grey ? nil : color.rawValue
        tagColors[tag] = name
        onColor?(tag, name)
    }
}

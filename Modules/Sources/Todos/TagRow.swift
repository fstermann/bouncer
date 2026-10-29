import SwiftUI

/// The categories to filter by, and a way to add one. Right-clicking one opens its colours, and
/// dragging one moves it among the tags beside it.
struct TagRow: View {
    private static let strip = "strip"
    private static let chipSpace = "chips"
    @Bindable var page: TodoPage
    /// The todo field's focus, which gets the cursor back once a category is named.
    let isTyping: FocusState<Bool>.Binding
    /// How far chips run on past the strip's ends, which fade out to show it.
    @State private var beforeStart: CGFloat = 0
    @State private var pastEnd: CGFloat = 0
    /// The chip being dragged, where the pointer holds it, and where the pointer is.
    @State private var dragged: String?
    @State private var grab: CGFloat = 0
    @State private var pointer: CGFloat = 0
    @State private var widths: [String: CGFloat] = [:]
    /// The chip a drag has moved next to, scrolled into view so the drag can carry on past the edge.
    @State private var ahead: String?

    var body: some View {
        HStack(spacing: 6) {
            // Scrolled only once they overflow, with the plus kept in view after them.
            ViewThatFits(in: .horizontal) {
                chips
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        chips
                            .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(Self.strip)).minX } action: {
                                beforeStart = $0
                            }
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                let visible = geometry.bounds(of: .named(Self.strip))?.width ?? .infinity
                                return geometry.frame(in: .named(Self.strip)).maxX - visible
                            } action: { pastEnd = $0 }
                    }
                    .coordinateSpace(.named(Self.strip))
                    .mask(EdgeFade(axis: .horizontal, beforeStart: beforeStart, pastEnd: pastEnd))
                    // A chip just selected has moved to the front, which may be scrolled out of view.
                    .onChange(of: page.filters) {
                        guard let first = page.chipTags.first else { return }
                        withAnimation(.snappy) { proxy.scrollTo(first, anchor: .leading) }
                    }
                    .onChange(of: ahead) {
                        guard let ahead = $1 else { return }
                        withAnimation(.snappy) { proxy.scrollTo(ahead) }
                    }
                }
            }
            if page.isAddingCategory {
                PanelField(placeholder: "Tag", text: $page.categoryDraft) {
                    page.onAddCategory?(page.categoryDraft)
                    page.isAddingCategory = false
                } onEnd: {
                    // Given up once the cursor goes elsewhere, so the plus comes back.
                    page.isAddingCategory = false
                }
                .frame(width: 90)
            } else {
                Button { page.isAddingCategory = true } label: { Chip(text: "+") }
                    .buttonStyle(.plain)
                    .help("Add a tag")
            }
            Spacer(minLength: 0)
            SearchControl(page: page)
        }
        .padding(.horizontal, 14)
        .frame(height: 22)
        .onChange(of: page.isAddingCategory) {
            guard !$1 else { return }
            page.categoryDraft = ""
            isTyping.wrappedValue = true
        }
        .onChange(of: page.focusRequests) { page.isAddingCategory = false }
        // A filter whose chip has gone would narrow the list with nothing to undo it by.
        .onChange(of: page.tags) { page.filters.formIntersection($1) }
        .onChange(of: page.offersUntagged) { if !$1 { page.showsUntagged = false } }
        .padding(.bottom, 6)
    }

    private var chips: some View {
        let starts = starts(of: page.chipTags)
        return HStack(spacing: Self.spacing) {
            ForEach(page.chipTags, id: \.self) { tag in
                let coloring = RowMenu(line: nil, kind: .colors(tag))
                Chip(
                    tag: tag, color: page.color(of: tag), isSelected: page.filters.contains(tag),
                    count: page.count(of: tag)
                )
                    // Ringed while its colours are open below it.
                    .overlay(Capsule().stroke(.white, lineWidth: page.menu == coloring ? 1.5 : 0))
                    .contentShape(Capsule())
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[tag] = $0 }
                    .offset(x: dragged == tag ? pointer - grab - (starts[tag] ?? 0) : 0)
                    .zIndex(dragged == tag ? 1 : 0)
                    // Held under the pointer while the others slide out of its way.
                    .transaction { if dragged == tag { $0.animation = nil } }
                    .onTapGesture { withAnimation(.snappy) { page.toggleFilter(tag) } }
                    .gesture(drag(tag))
                .overlay(RightClick { page.menu = coloring })
                .anchorPreference(key: MenuAnchor.self, value: .bounds) { page.menu == coloring ? $0 : nil }
            }
            if page.offersUntagged {
                Button { withAnimation(.snappy) { page.toggleUntagged() } } label: {
                    Chip(text: "untagged", isSelected: page.showsUntagged, count: page.untaggedCount)
                }
                .buttonStyle(.plain)
            }
        }
        .coordinateSpace(.named(Self.chipSpace))
        // Tags come and go, and reorder, as todos change elsewhere too.
        .animation(.snappy, value: page.chipTags)
        .animation(.snappy, value: page.offersUntagged)
    }

    private static let spacing: CGFloat = 6

    /// Where each chip starts along the row, from the chips' widths. Their measured frames would lag
    /// a swap by a layout pass, and swap the chip straight back.
    private func starts(of chips: [String]) -> [String: CGFloat] {
        var end: CGFloat = 0
        var starts: [String: CGFloat] = [:]
        for chip in chips {
            starts[chip] = end
            end += (widths[chip] ?? 0) + Self.spacing
        }
        return starts
    }

    /// Swaps the chip with the one beside it once it is dragged past that one's middle. Selected chips
    /// lead the row whatever their order, so only the others move, and only among the tags beside them.
    private func drag(_ tag: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.chipSpace))
            .onChanged { value in
                let chips = page.chipTags
                let starts = starts(of: chips)
                guard !page.filters.contains(tag), let start = starts[tag], let width = widths[tag],
                      let index = chips.firstIndex(of: tag) else { return }
                if dragged != tag {
                    dragged = tag
                    grab = value.startLocation.x - start
                }
                pointer = value.location.x
                let left = pointer - grab
                let middle = { (other: String) in (starts[other] ?? 0) + (widths[other] ?? 0) / 2 }
                let movable = { (other: String) in
                    !page.filters.contains(other) && TagPath.parent(of: other) == TagPath.parent(of: tag)
                }
                let next = chips.dropFirst(index + 1).first.flatMap { movable($0) ? $0 : nil }
                let previous = chips.prefix(index).last.flatMap { movable($0) ? $0 : nil }
                if let next, left + width > middle(next) {
                    withAnimation(.snappy) { page.moveTag(tag, onto: next) }
                    let moved = page.chipTags
                    ahead = moved.firstIndex(of: tag).flatMap { moved.dropFirst($0 + 1).first } ?? tag
                } else if let previous, left < middle(previous) {
                    withAnimation(.snappy) { page.moveTag(tag, onto: previous) }
                    let moved = page.chipTags
                    ahead = moved.firstIndex(of: tag).flatMap { moved.prefix($0).last } ?? tag
                }
            }
            .onEnded { _ in
                withAnimation(.snappy) { dragged = nil }
                ahead = nil
                // Saved once, not at each swap: any change to the preferences reconfigures the menu bar.
                page.onOrder?(page.tagOrder)
            }
    }
}

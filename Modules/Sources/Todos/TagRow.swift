import SwiftUI

/// The categories to filter by, and a way to add one. Right-clicking one opens its colours.
struct TagRow: View {
    @Bindable var page: TodoPage
    /// The todo field's focus, which gets the cursor back once a category is named.
    let isTyping: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            // Scrolled only once they overflow, with the plus kept in view after them.
            ViewThatFits(in: .horizontal) {
                chips
                ScrollView(.horizontal, showsIndicators: false) { chips }
            }
            if page.isAddingCategory {
                CategoryField(text: $page.categoryDraft) {
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
                    .help("Add a category")
            }
            Spacer(minLength: 0)
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
        HStack(spacing: 6) {
            ForEach(page.tags, id: \.self) { tag in
                let coloring = RowMenu(line: nil, kind: .colors(tag))
                Button { page.toggleFilter(tag) } label: {
                    Chip(
                        text: tag, color: page.color(of: tag), isSelected: page.filters.contains(tag),
                        count: page.count(of: tag)
                    )
                        // Ringed while its colours are open below it.
                        .overlay(Capsule().stroke(.white, lineWidth: page.menu == coloring ? 1.5 : 0))
                }
                .buttonStyle(.plain)
                .overlay(RightClick { page.menu = coloring })
                .anchorPreference(key: MenuAnchor.self, value: .bounds) { page.menu == coloring ? $0 : nil }
            }
            if page.offersUntagged {
                Button { page.toggleUntagged() } label: {
                    Chip(text: "untagged", isSelected: page.showsUntagged, count: page.untaggedCount)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

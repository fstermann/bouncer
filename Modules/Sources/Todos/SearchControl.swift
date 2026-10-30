import SwiftUI

/// A magnifying glass that springs open into a field searching the page, closed again by the
/// cross at its end, which stays where the glass was.
struct SearchControl<Page: TagFiltering>: View {
    @Bindable var page: Page

    var body: some View {
        HStack(spacing: 0) {
            Button { withAnimation(.snappy) { page.openSearch() } } label: { Image(systemName: "magnifyingglass") }
                .help("Search (⌘F)")
            // Kept in place while closed, since SwiftUI takes an AppKit view out without its transition.
            PanelField(
                placeholder: "Search", text: $page.query, focusRequests: page.searchFocusRequests,
                takesCursorOnAppear: false, onEnd: {}
            )
            .frame(width: page.isSearching ? 130 : 0)
            .padding(.leading, page.isSearching ? 4 : 0)
            .opacity(page.isSearching ? 1 : 0)
            .allowsHitTesting(page.isSearching)
            Button { withAnimation(.snappy) { page.closeSearch() } } label: { Image(systemName: "xmark") }
                .help("Close search")
                .frame(width: page.isSearching ? nil : 0)
                .padding(.leading, page.isSearching ? 4 : 0)
                .opacity(page.isSearching ? 1 : 0)
                .allowsHitTesting(page.isSearching)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, page.isSearching ? 8 : 0)
        .padding(.vertical, 2)
        .background(Capsule().fill(.white.opacity(page.isSearching ? 0.15 : 0)))
    }
}

import Foundation

/// What the overview's items stand for: a desktop's Space and front window, a window's place and badge;
/// and picking or tiling them.
extension Overview {
    /// The Space a Spaces view item stands for.
    func space(of item: WindowInfo) -> SpaceInfo? {
        spaceItems.first { $0.item.id == item.id }?.space
    }

    /// What picking `item` brings forward: itself, or for a desktop its front window. Empty for an empty
    /// desktop, which no public call can switch to.
    func pickable(_ item: WindowInfo) -> [WindowInfo] {
        guard view == .spaces, SpaceItems.isDesktop(item) else { return [item] }
        guard let desktop = space(of: item) else { return [] }
        return front(of: desktop)
    }

    /// A desktop's front window, which brings the desktop forward; empty when it has none of its own.
    func front(of desktop: SpaceInfo) -> [WindowInfo] {
        if desktop.isCurrent { return Array(desktop.windows.prefix(1)) }
        let elsewhere = Set(spaceItems.filter { $0.space.id != desktop.id }.flatMap { $0.space.windows.map(\.id) })
        return desktop.windows.first { !elsewhere.contains($0.id) }.map { [$0] } ?? []
    }

    /// Where a window lives, for one off the current Space: "Desktop 2", "Full screen".
    func place(of window: WindowInfo) -> String? {
        guard let space = spaces[window.id], !space.isCurrent else { return nil }
        switch space.kind {
        case .desktop: return space.name
        case .fullScreen: return "Full screen"
        }
    }

    /// The badge a card shows: its app's, or for a desktop or deck its apps' together, each app counted once.
    func badge(of items: [WindowInfo]) -> String? {
        let windows = items.flatMap { item in
            view == .spaces && SpaceItems.isDesktop(item) ? space(of: item)?.windows ?? [] : [item]
        }
        return DockBadges.combined(Set(windows.map(\.pid)).compactMap { badges[$0] })
    }

    func pick(_ items: [WindowInfo]) {
        let windows = items.flatMap(pickable)
        guard !windows.isEmpty else { return }
        onPick?(windows)
    }

    func tile(_ id: UUID) {
        guard let live = arrangement.decks.first(where: { $0.id == id }) else { return }
        let windows = Tiling.tileable(live.windows, spaces: spaces)
        guard !windows.isEmpty else { return }
        onTile?(windows)
    }
}

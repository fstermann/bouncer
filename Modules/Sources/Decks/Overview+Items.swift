import AppKit

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

    /// Whether `window` is being dragged away from its card.
    func isDragging(_ window: WindowInfo) -> Bool {
        drag?.isMoving == true && drag?.window.id == window.id
    }

    // MARK: - Dragging

    /// Less than this from where it started, in points, a press is still a click.
    static let dragThreshold: CGFloat = 4

    /// Ends the drag with no drop here, the pointer having let go over another display; returns the drag.
    func endDrag() -> Drag? {
        defer { drag = nil }
        return drag
    }

    func dragged(to point: CGPoint) {
        guard var drag else { return }
        drag.point = point
        drag.isMoving = drag.isMoving || hypot(point.x - drag.start.x, point.y - drag.start.y) >= Self.dragThreshold
        self.drag = drag
    }

    // MARK: - Other displays

    /// A window dragged in from another display's overview, its picture, and where the pointer has it.
    struct Incoming {
        let window: WindowInfo
        let picture: NSImage?
        var point: CGPoint
    }

    /// Whether `drag` can be dropped on another display's overview: a moving deck or window off any full
    /// screen Space, not a desktop, and Accessibility to move it.
    func canMoveAcross(_ drag: Drag) -> Bool {
        drag.isMoving && canRaise && !(view == .spaces && SpaceItems.isDesktop(drag.window))
            && !moved(by: drag).isEmpty
    }

    /// The windows a drop on another display moves: the dragged window, or the dragged deck's, less any
    /// on a full screen Space, which cannot be moved.
    func moved(by drag: Drag) -> [WindowInfo] {
        let windows = drag.deck.map { deck in arrangement.decks.first { $0.id == deck }?.windows ?? [] }
            ?? [drag.window]
        return windows.filter { spaces[$0.id]?.kind != .fullScreen }
    }
}

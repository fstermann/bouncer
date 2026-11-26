import Foundation

/// What the keyboard does in the overview: typing narrows the cards, a digit goes to a desktop, Return
/// picks, Command-R names what the pointer is on.
extension Overview {
    /// Brings forward the desktop numbered `number` on this display, as Mission Control counts them.
    func jump(to number: Int) {
        guard let desktop = spaceItems.first(where: { $0.space.kind == .desktop(number: number) })?.space else {
            return
        }
        go(to: desktop)
    }

    /// Brings forward the first card the filter left: a deck's windows, or an item.
    func pickFirst() {
        let arrangement = arrangement
        if let live = arrangement.decks.first(where: { !$0.windows.isEmpty }) {
            pick(deck: live)
        } else if let item = arrangement.ungrouped.first {
            pick([item])
        }
    }

    /// A key pressed while no name is being typed. Returns whether the overview took it.
    func key(_ key: OverviewKey) -> Bool {
        guard renaming == nil else { return false }
        switch key {
        case .rename:
            return renameHovered()
        case .escape:
            guard !query.isEmpty else { return false }
            query = ""
        case .delete:
            guard !query.isEmpty else { return false }
            query.removeLast()
        case .enter:
            guard !query.isEmpty else { return false }
            pickFirst()
        case .text(let text):
            type(text)
        }
        return true
    }

    /// A digit before anything else goes to that desktop; other text narrows the cards. A leading space is dropped.
    private func type(_ text: String) {
        if query.isEmpty, let number = Int(text), (1...9).contains(number) {
            jump(to: number)
        } else if !(query.isEmpty && text.allSatisfy(\.isWhitespace)) {
            query += text
        }
    }

    // MARK: - Full screen

    /// What dropping `drag` on the full screen bar would do: a window of the current desktop enters full
    /// screen, the current full screen Space leaves it. `nil` for anything else: a window on another Space
    /// cannot be reached through Accessibility (issue #45).
    func fullScreenDrop(of drag: Drag) -> FullScreenChange? {
        guard drag.deck == nil else { return nil }
        if drag.source == .desktop { return spaces[drag.window.id]?.isCurrent == true ? .enter : nil }
        guard view == .spaces, let space = spaceItems.first(where: { $0.item.id == drag.window.id })?.space,
              space.kind == .fullScreen, space.isCurrent
        else { return nil }
        return .leave
    }

    enum FullScreenChange {
        case enter, leave
    }
}

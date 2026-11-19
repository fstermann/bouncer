import AppKit
import Settings

#if DEV
extension DecksController {
    /// What one of the read-only commands, or the split, answers.
    public func devReport(_ command: String) -> String {
        switch command {
        case "pictures": devPictures()
        case "cards": devCards()
        case "spaces": devSpaces()
        default: devSplit()
        }
    }

    /// Opens two overviews side by side on the main display, standing in for two displays.
    public func devSplit() -> String {
        guard let screen = NSScreen.screens.first else { return "no display" }
        func half(_ rect: CGRect, _ side: Int) -> CGRect {
            let width = (rect.width / 2).rounded(.down)
            return CGRect(x: rect.minX + CGFloat(side) * width, y: rect.minY, width: width, height: rect.height)
        }
        close()
        open(on: (0..<2).map {
            Area(screen: screen, frame: half(screen.frame, $0), visibleFrame: half(screen.visibleFrame, $0))
        })
        return "split"
    }

    /// Groups the `count` frontmost windows on screen into a new deck, for checking decks from a shell.
    public func devGroup(_ count: Int) -> String {
        let windows = Array(WindowList.onScreen().prefix(count))
        guard !windows.isEmpty else { return "no windows" }
        settings.preferences.decks = DeckMatching.grouping(windows, in: settings.preferences.decks).decks
        return "grouped \(windows.map(\.label))"
    }

    /// Hovers the deck at `index` in the open overview, as the pointer would.
    public func devHover(_ index: Int) -> String {
        guard let overview, index < overview.decks.count else { return "no such deck" }
        overview.devShow(overview.decks[index].id)
        return "hovering \(overview.decks[index].name)"
    }

    /// Removes every deck, or only those of one view.
    public func devClearDecks(_ kind: DeckKind? = nil) {
        settings.preferences.decks.removeAll { kind == nil || $0.kind == kind }
    }

    /// Brings the window numbered `id` forward from wherever it is, as picking it in the overview would.
    public func devFocus(_ id: CGWindowID) -> String {
        guard let window = SpaceList.read()?.flatMap(\.windows).first(where: { $0.id == id }) else {
            return "no window \(id)"
        }
        Task.detached { SpaceFocus.raise(window) }
        return "focusing \(window.label)"
    }

    /// How many of the open overview's windows have their picture, of how many.
    public func devPictures() -> String {
        guard let overview else { return "closed" }
        return "\(overview.thumbnails.count)/\(overview.windows.count)"
    }

    /// Where the open overview draws each window's card, in screen points from the top left.
    public func devCards() -> String {
        guard let overview else { return "closed" }
        return overview.hoverFrames.compactMap { target, frame -> String? in
            let name: String
            switch target {
            case .window(let id): name = "\(id)"
            case .trayWindow(let id): name = "tray-\(id)"
            case .desktop(let id):
                guard let entry = overview.spaceItems.first(where: { $0.item.id == id }) else { return nil }
                name = "desk-\(entry.space.name)".replacingOccurrences(of: " ", with: "-")
            case .deck(let id):
                name = (overview.decks.first { $0.id == id }?.name ?? "deck").replacingOccurrences(of: " ", with: "-")
            case .newDeck, .newDesktop: name = target == .newDeck ? "new" : "new-desktop"
            case .fullScreen: name = "full-screen"
            case .tray, .grid, .removeDesktop: return nil
            }
            return "\(name) \(Int(frame.midX)) \(Int(frame.midY))"
        }.sorted().joined(separator: "\n")
    }

    /// Every Space with its windows, as the overview reads them.
    public func devSpaces() -> String {
        guard let spaces = SpaceList.read() else { return "SkyLight unavailable" }
        return spaces.map { space in
            let name = switch space.kind {
            case .desktop(let number): "Desktop \(number)"
            case .fullScreen: "full screen"
            }
            return "\(space.id) \(name)\(space.isCurrent ? " (current)" : ""): "
                + space.windows.map { "\($0.id) \($0.label)" }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
#endif

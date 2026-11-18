import CoreGraphics
import Foundation
import Settings

/// The Spaces view's items: each Space stood in for by one window, so decks of Spaces are matched,
/// dragged and dropped by the same code as decks of windows.
///
/// A full screen Space stands as its app's window, whose number and title find it again as any
/// window's do. A desktop has no window of its own, so it stands as a made up one: numbered from a
/// range no window server number reaches, owned by no app, titled with the desktop's name, and stored
/// by its Space's identifier, which lasts until the desktop is removed.
enum SpaceItems {
    /// Above every window server number, which counts up from 1 and is 32 bits.
    static let firstDesktopID: CGWindowID = 0xF000_0000

    /// The item for each Space, in Mission Control's order, with the Space it stands for.
    static func items(for spaces: [SpaceInfo]) -> [(item: WindowInfo, space: SpaceInfo)] {
        var desktops: CGWindowID = 0
        return spaces.compactMap { space in
            switch space.kind {
            case .fullScreen:
                guard let window = space.windows.first else { return nil }
                return (window, space)
            case .desktop:
                defer { desktops += 1 }
                let item = WindowInfo(
                    id: firstDesktopID + desktops, pid: 0, bundleID: nil, appName: space.name, title: space.name,
                    frame: .zero
                )
                return (item, space)
            }
        }
    }

    static func isDesktop(_ item: WindowInfo) -> Bool {
        item.id >= firstDesktopID
    }

    /// `decks` of Spaces with each desktop member's stored number made the item now standing for its
    /// Space, or cleared when that desktop is gone, so window number matching finds desktops as it
    /// finds windows.
    static func resolved(_ decks: [Deck], with items: [(item: WindowInfo, space: SpaceInfo)]) -> [Deck] {
        let byUUID = Dictionary(items.map { ($0.space.uuid, $0.item.id) }) { first, _ in first }
        return decks.map { deck in
            var deck = deck
            deck.members = deck.members.map { member in
                guard let uuid = member.space else { return member }
                var member = member
                member.windowID = byUUID[uuid]
                return member
            }
            return deck
        }
    }

    /// `decks` of Spaces as they are stored: each desktop member by its Space's identifier rather than
    /// the number standing for it while the overview is open. The inverse of `resolved`.
    static func stored(_ decks: [Deck], with items: [(item: WindowInfo, space: SpaceInfo)]) -> [Deck] {
        let byID = Dictionary(items.map { ($0.item.id, $0.space.uuid) }) { first, _ in first }
        return decks.map { deck in
            var deck = deck
            deck.members = deck.members.map { member in
                guard let id = member.windowID, id >= firstDesktopID else { return member }
                return DeckMember(app: "", title: nil, windowID: nil, space: byID[id] ?? member.space)
            }
            return deck
        }
    }

    /// Every deck brought up to date with what is open: decks of windows over `windows`, decks of
    /// Spaces over `items`, their desktops found by identifier. Desktop members come back numbered as
    /// their items, for the overview; `stored` turns them back.
    ///
    /// - Parameter existing: the number of every window that exists, on screen or not.
    static func refreshed(
        _ decks: [Deck], windows: [WindowInfo], items: [(item: WindowInfo, space: SpaceInfo)]?,
        existing: Set<CGWindowID>
    ) -> [Deck] {
        let windowDecks = decks.filter { $0.kind == .windows }
        let spaceDecks = decks.filter { $0.kind == .spaces }
        let refreshedWindows = DeckMatching.refreshed(windowDecks, over: windows, existing: existing)
        guard let items else { return refreshedWindows + spaceDecks }
        return refreshedWindows + DeckMatching.refreshed(
            resolved(spaceDecks, with: items), over: items.map(\.item),
            existing: existing.union(items.map(\.item.id))
        )
    }
}

import CoreGraphics
import Foundation
import Settings

/// A deck with the windows of it that are open now, in the deck's order.
public struct LiveDeck: Hashable, Sendable, Identifiable {
    public let deck: Deck
    public let windows: [WindowInfo]

    public var id: UUID { deck.id }
}

/// What the overview shows: its decks, then the windows in none.
struct Arrangement: Hashable, Sendable {
    var decks: [LiveDeck]
    var ungrouped: [WindowInfo]
}

/// Pairs decks with open windows, and keeps what decks store in step with what was found.
enum DeckMatching {
    /// The key a member is stored under for `window`: its bundle identifier, or its app's name.
    static func app(of window: WindowInfo) -> String {
        window.bundleID ?? window.appName
    }

    static func member(for window: WindowInfo) -> DeckMember {
        DeckMember(app: app(of: window), title: window.title, windowID: window.id)
    }

    private struct MemberIndex: Hashable {
        let deck: Int
        let member: Int
    }

    /// Each deck's open windows in the deck's order, and the windows in no deck front to back.
    ///
    /// A member is matched by window number while that window is open. Otherwise it takes the first
    /// unclaimed window of the same app with the same title: after a relaunch, numbers are new.
    /// A window goes to at most one member, and the first deck to claim it keeps it.
    static func arrange(_ decks: [Deck], over windows: [WindowInfo]) -> Arrangement {
        let claimed = claims(decks, over: windows)
        let live = decks.enumerated().map { index, deck in
            LiveDeck(deck: deck, windows: windows.filter { claimed[$0.id]?.deck == index }
                .sorted { claimed[$0.id]?.member ?? 0 < claimed[$1.id]?.member ?? 0 })
        }
        return Arrangement(decks: live, ungrouped: windows.filter { claimed[$0.id] == nil })
    }

    private static func claims(_ decks: [Deck], over windows: [WindowInfo]) -> [CGWindowID: MemberIndex] {
        var claimed: [CGWindowID: MemberIndex] = [:]
        let open = Dictionary(windows.map { ($0.id, $0) }) { first, _ in first }
        for (deckIndex, deck) in decks.enumerated() {
            for (memberIndex, member) in deck.members.enumerated() {
                guard let id = member.windowID, let window = open[id], claimed[id] == nil,
                      member.space != nil || member.app == app(of: window) else { continue }
                claimed[id] = MemberIndex(deck: deckIndex, member: memberIndex)
            }
        }
        for (deckIndex, deck) in decks.enumerated() {
            for (memberIndex, member) in deck.members.enumerated() {
                let index = MemberIndex(deck: deckIndex, member: memberIndex)
                if let id = member.windowID, claimed[id] == index { continue }
                guard let title = member.title, !title.isEmpty,
                      let window = windows.first(where: {
                          claimed[$0.id] == nil && app(of: $0) == member.app && $0.title == title
                      })
                else { continue }
                claimed[window.id] = index
            }
        }
        return claimed
    }

    /// `decks` with what each member stores brought up to date.
    ///
    /// A member matched to a window on screen takes its number and title. One whose window still exists
    /// elsewhere, minimized or on another Space, is kept as it is. One whose window has closed keeps
    /// only its app and title, to be found again by them; without a title nothing could find it again,
    /// so it is forgotten.
    ///
    /// - Parameter existing: the number of every window that exists, on screen or not.
    static func refreshed(_ decks: [Deck], over windows: [WindowInfo], existing: Set<CGWindowID>) -> [Deck] {
        let claimed = claims(decks, over: windows)
        var matches: [MemberIndex: WindowInfo] = [:]
        for window in windows {
            if let index = claimed[window.id] { matches[index] = window }
        }
        let offScreen = existing.subtracting(windows.map(\.id))
        return decks.enumerated().map { deckIndex, deck in
            var deck = deck
            deck.members = deck.members.enumerated().compactMap { memberIndex, member in
                if let window = matches[MemberIndex(deck: deckIndex, member: memberIndex)] {
                    return Self.member(for: window)
                }
                if let id = member.windowID, offScreen.contains(id) { return member }
                guard let title = member.title, !title.isEmpty else { return nil }
                return DeckMember(app: member.app, title: title, windowID: nil)
            }
            return deck
        }
    }

    /// `decks` with `window` taken out of whichever deck held it.
    static func removing(_ window: WindowInfo, from decks: [Deck]) -> [Deck] {
        decks.map { deck in
            var deck = deck
            deck.members.removeAll { $0.windowID == window.id }
            return deck
        }
    }

    /// `decks` with `window` moved into the deck `id`, out of any other.
    static func adding(_ window: WindowInfo, to id: UUID, in decks: [Deck]) -> [Deck] {
        removing(window, from: decks).map { deck in
            guard deck.id == id else { return deck }
            var deck = deck
            deck.members.append(member(for: window))
            return deck
        }
    }

    /// `decks` with a new deck holding `windows`, named and coloured as the next one.
    static func grouping(_ windows: [WindowInfo], in decks: [Deck]) -> (decks: [Deck], id: UUID) {
        let deck = Deck(name: nextName(in: decks), color: nextColor(in: decks), members: windows.map(member(for:)))
        var decks = decks
        for window in windows { decks = removing(window, from: decks) }
        return (decks + [deck], deck.id)
    }

    /// "Deck 1", "Deck 2": the first number no deck is named with.
    static func nextName(in decks: [Deck]) -> String {
        let names = Set(decks.map(\.name))
        let number = (1...).first { !names.contains("Deck \($0)") } ?? decks.count + 1
        return "Deck \(number)"
    }

    /// The first colour no deck has, or round again once every one is taken.
    static func nextColor(in decks: [Deck]) -> DeckColor {
        let used = Set(decks.map(\.color))
        return DeckColor.allCases.first { !used.contains($0) }
            ?? DeckColor.allCases[decks.count % DeckColor.allCases.count]
    }
}

import CoreGraphics
import Settings
import Testing

@testable import Decks

@Suite struct ReorderTests {
    /// Two rows of cards 100 wide, 20 apart: three on the first, two on the second.
    private let cards = [
        CGRect(x: 0, y: 0, width: 100, height: 80), CGRect(x: 120, y: 0, width: 100, height: 80),
        CGRect(x: 240, y: 0, width: 100, height: 80),
        CGRect(x: 60, y: 100, width: 100, height: 80), CGRect(x: 180, y: 100, width: 100, height: 80)
    ]

    @Test func takesTheSideOfTheNearestCard() {
        #expect(Reorder.slot(at: CGPoint(x: 20, y: 40), among: cards, reach: 40) == 0)
        #expect(Reorder.slot(at: CGPoint(x: 90, y: 40), among: cards, reach: 40) == 1)
        #expect(Reorder.slot(at: CGPoint(x: 115, y: 40), among: cards, reach: 40) == 1)
        #expect(Reorder.slot(at: CGPoint(x: 330, y: 40), among: cards, reach: 40) == 3)
        #expect(Reorder.slot(at: CGPoint(x: 300, y: 140), among: cards, reach: 40) == 5)
    }

    @Test func farFromEveryCardIsNoSlot() {
        #expect(Reorder.slot(at: CGPoint(x: 600, y: 40), among: cards, reach: 40) == nil)
        #expect(Reorder.slot(at: CGPoint(x: 20, y: 40), among: [], reach: 40) == nil)
    }

    @Test func eitherSideOfItselfIsNoMove() {
        #expect(Reorder.isNoMove(from: 2, to: 2))
        #expect(Reorder.isNoMove(from: 2, to: 3))
        #expect(!Reorder.isNoMove(from: 2, to: 1))
        #expect(!Reorder.isNoMove(from: nil, to: 1))
    }

    @Test func marksTheGapOrTheRowsEnd() {
        #expect(Reorder.marker(for: 1, among: cards, gap: 20) == CGRect(x: 108.5, y: 0, width: 3, height: 80))
        #expect(Reorder.marker(for: 0, among: cards, gap: 20) == CGRect(x: -11.5, y: 0, width: 3, height: 80))
        // Before the second row's first card, not after the first row's last.
        #expect(Reorder.marker(for: 3, among: cards, gap: 20) == CGRect(x: 48.5, y: 100, width: 3, height: 80))
        #expect(Reorder.marker(for: 5, among: cards, gap: 20) == CGRect(x: 288.5, y: 100, width: 3, height: 80))
    }

    @Test func onlyTheMiddleHalfGroups() {
        let card = cards[0]
        #expect(Reorder.isMiddle(CGPoint(x: 50, y: 40), of: card))
        #expect(Reorder.isMiddle(CGPoint(x: 30, y: 40), of: card))
        #expect(!Reorder.isMiddle(CGPoint(x: 20, y: 40), of: card))
        #expect(!Reorder.isMiddle(CGPoint(x: 90, y: 40), of: card))
        #expect(!Reorder.isMiddle(CGPoint(x: 50, y: 90), of: card))
    }

    @Test func movesAmongWhatIsShown() {
        let list = ["a", "b", "c", "d", "e"]
        #expect(Reorder.moving("d", to: 0, among: list, in: list) == ["d", "a", "b", "c", "e"])
        #expect(Reorder.moving("a", to: 5, among: list, in: list) == ["b", "c", "d", "e", "a"])
        #expect(Reorder.moving("a", to: 3, among: list, in: list) == ["b", "c", "a", "d", "e"])
        // Filtered down to b, d and e: after the last shown one, not at the very end of the list.
        #expect(Reorder.moving("b", to: 2, among: ["b", "d", "e"], in: list + ["f"]) == ["a", "c", "d", "b", "e", "f"])
        #expect(Reorder.moving("x", to: 0, among: list, in: list) == list)
    }

    @Test func storedOrderFirstThenTheRest() {
        let items = ["a", "b", "c", "d"]
        #expect(Reorder.ordered(items, by: ["c", "gone", "a"]) { $0 } == ["c", "a", "b", "d"])
        #expect(Reorder.ordered(items, by: []) { $0 } == items)
    }
}

@MainActor
@Suite struct OverviewReorderTests {
    private let frames = (0..<3).map { CGRect(x: 20 + CGFloat($0) * 216, y: 20, width: 190, height: 140) }

    private func center(_ frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: nil, appName: "App", title: "w\(id)", frame: .zero)
    }

    private func member(_ id: CGWindowID) -> DeckMember {
        DeckMember(app: "App", title: "w\(id)", windowID: id)
    }

    private func drag(_ overview: Overview, from start: CGPoint, to end: CGPoint) {
        #expect(overview.press(at: start))
        overview.dragged(to: end)
        overview.released(at: end)
    }

    private func desktops() -> Overview {
        let spaces = (1...3).map { index in
            SpaceInfo(id: UInt64(index), uuid: "d\(index)", kind: .desktop(number: index), isCurrent: index == 1,
                      windows: [])
        }
        let overview = Overview(windows: [], spaceItems: SpaceItems.items(for: spaces), decks: [], wallpaper: nil,
                                canRaise: true, canSeeTitles: true)
        overview.view = .spaces
        overview.hoverFrames = Dictionary(uniqueKeysWithValues: zip(overview.items.map { .desktop($0.id) }, frames))
        return overview
    }

    @Test func theCurrentFullScreenSpaceGroupsLikeAnyOtherCard() {
        let app = window(9)
        let spaces = [
            SpaceInfo(id: 1, uuid: "d1", kind: .desktop(number: 1), isCurrent: false, windows: []),
            SpaceInfo(id: 2, uuid: "fs", kind: .fullScreen, isCurrent: true, windows: [app])
        ]
        let overview = Overview(windows: [app], spaceItems: SpaceItems.items(for: spaces), decks: [], wallpaper: nil,
                                canRaise: true, canSeeTitles: true)
        overview.view = .spaces
        overview.hoverFrames = [
            .desktop(overview.items[0].id): frames[0], .window(app.id): frames[1], .newDeck: frames[2]
        ]
        drag(overview, from: center(frames[1]), to: center(frames[2]))
        #expect(overview.arrangement.decks.map { $0.windows.map(\.id) } == [[app.id]])
    }

    @Test func aSpaceDroppedAtACardsEdgeMovesThere() {
        let overview = desktops()
        let items = overview.items
        drag(overview, from: center(frames[2]), to: CGPoint(x: frames[0].minX + 5, y: frames[0].midY))
        #expect(overview.items == [items[2], items[0], items[1]])
        #expect(overview.spaceOrder == ["d3", "d1", "d2"])
        #expect(overview.decks.isEmpty)
    }

    @Test func aSpaceDroppedOnACardsMiddleStillGroups() {
        let overview = desktops()
        drag(overview, from: center(frames[0]), to: center(frames[1]))
        #expect(overview.decks.count == 1)
        #expect(overview.spaceOrder.isEmpty)
    }

    @Test func aDeckDraggedPastAnotherMovesAfterIt() {
        let first = Deck(name: "A", members: [member(1)])
        let second = Deck(name: "B", members: [member(2)])
        let overview = Overview(windows: [window(1), window(2)], decks: [first, second], wallpaper: nil,
                                canRaise: true, canSeeTitles: true)
        overview.hoverFrames = [.deck(first.id): frames[0], .deck(second.id): frames[1]]
        drag(overview, from: center(frames[0]), to: CGPoint(x: frames[1].maxX + 5, y: frames[1].midY))
        #expect(overview.decks.map(\.name) == ["B", "A"])
    }

    @Test func aTrayCardDraggedFirstLeadsTheDeck() {
        let deck = Deck(name: "A", members: [member(1), member(2), member(3)])
        let overview = Overview(windows: [window(1), window(2), window(3)], decks: [deck], wallpaper: nil,
                                canRaise: true, canSeeTitles: true)
        overview.trayDeck = deck.id
        overview.hoverFrames = [
            .tray: CGRect(x: 0, y: 0, width: 700, height: 200),
            .trayWindow(1): frames[0], .trayWindow(2): frames[1], .trayWindow(3): frames[2]
        ]
        drag(overview, from: center(frames[2]), to: CGPoint(x: frames[0].minX + 5, y: frames[0].midY))
        #expect(overview.decks[0].members.map(\.windowID) == [3, 1, 2])
        #expect(overview.arrangement.decks[0].windows.map(\.id) == [3, 1, 2])
    }
}

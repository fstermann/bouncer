import CoreGraphics
import Foundation
import Settings
import Testing

@testable import Decks

@Suite struct DeckMatchingTests {
    private func window(
        _ id: CGWindowID, app: String = "com.example.code", title: String? = "main.swift"
    ) -> WindowInfo {
        WindowInfo(
            id: id, pid: 1, bundleID: app, appName: "Code", title: title,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    private func deck(_ members: [DeckMember], name: String = "Code") -> Deck {
        Deck(name: name, members: members)
    }

    @Test func matchesByWindowNumberFirst() {
        let decks = [deck([DeckMember(app: "com.example.code", title: "old title", windowID: 2)])]
        let arrangement = DeckMatching.arrange(decks, over: [window(1), window(2), window(3)])
        #expect(arrangement.decks[0].windows.map(\.id) == [2])
        #expect(arrangement.ungrouped.map(\.id) == [1, 3])
    }

    @Test func hidesAnEmptyDeckWhoseWindowsAreOnAnotherDisplay() {
        let decks = [
            deck([DeckMember(app: "com.example.code", title: nil, windowID: 1)], name: "Here"),
            deck([DeckMember(app: "com.example.code", title: nil, windowID: 2)], name: "There"),
            deck([], name: "New")
        ]
        let here = DeckMatching.arrange(decks, over: [window(1)])
        let shown = DeckMatching.hidingElsewhere(here, over: [window(2)])
        #expect(shown.decks.map(\.deck.name) == ["Here", "New"])
    }

    @Test func matchesByAppAndTitleAfterARelaunch() {
        let decks = [deck([DeckMember(app: "com.example.code", title: "b.swift", windowID: 99)])]
        let windows = [
            window(1, title: "a.swift"), window(2, title: "b.swift"), window(3, app: "other", title: "b.swift")
        ]
        let arrangement = DeckMatching.arrange(decks, over: windows)
        #expect(arrangement.decks[0].windows.map(\.id) == [2])
    }

    @Test func aWindowGoesToOneMemberOnly() {
        let member = DeckMember(app: "com.example.code", title: "main.swift", windowID: nil)
        let decks = [deck([member, member]), deck([member], name: "Other")]
        let arrangement = DeckMatching.arrange(decks, over: [window(1)])
        #expect(arrangement.decks[0].windows.map(\.id) == [1])
        #expect(arrangement.decks[1].windows.isEmpty)
        #expect(arrangement.ungrouped.isEmpty)
    }

    @Test func aNumberClaimBeatsAnEarlierTitleMatch() {
        let byTitle = deck([DeckMember(app: "com.example.code", title: "main.swift", windowID: nil)], name: "A")
        let byNumber = deck([DeckMember(app: "com.example.code", title: "main.swift", windowID: 1)], name: "B")
        let arrangement = DeckMatching.arrange([byTitle, byNumber], over: [window(1)])
        #expect(arrangement.decks[0].windows.isEmpty)
        #expect(arrangement.decks[1].windows.map(\.id) == [1])
    }

    @Test func keepsWindowsInTheDecksOrder() {
        let decks = [deck([
            DeckMember(app: "com.example.code", title: nil, windowID: 3),
            DeckMember(app: "com.example.code", title: nil, windowID: 1)
        ])]
        let arrangement = DeckMatching.arrange(decks, over: [window(1), window(2), window(3)])
        #expect(arrangement.decks[0].windows.map(\.id) == [3, 1])
    }

    @Test func refreshTakesTheMatchedWindowsNumberAndTitle() {
        let decks = [deck([DeckMember(app: "com.example.code", title: "main.swift", windowID: 99)])]
        let refreshed = DeckMatching.refreshed(decks, over: [window(5)], existing: [5])
        #expect(refreshed[0].members == [DeckMember(app: "com.example.code", title: "main.swift", windowID: 5)])
    }

    @Test func reusedNumberDoesNotClaimAnotherAppsWindow() {
        let member = DeckMatching.member(for: window(2))
        let decks = [deck([member])]
        let windows = [window(2, app: "other"), window(3)]
        #expect(DeckMatching.arrange(decks, over: windows).ungrouped.map(\.id) == [2])
        #expect(DeckMatching.refreshed(decks, over: windows, existing: [2, 3])[0].members
            == [DeckMatching.member(for: window(3))])
    }

    @Test func sameTitleDoesNotStealALiveMembersClaimDuringRefresh() {
        let decks = [deck([window(10), window(20)].map(DeckMatching.member(for:)))]
        let refreshed = DeckMatching.refreshed(decks, over: [window(20)], existing: [20])
        #expect(refreshed[0].members.map(\.windowID) == [nil, 20])
        #expect(refreshed[0].members[0].title == "main.swift")
    }

    @Test func refreshKeepsAWindowThatIsOnlyOffScreen() {
        let member = DeckMember(app: "com.example.code", title: nil, windowID: 7)
        let decks = [deck([member])]
        #expect(DeckMatching.refreshed(decks, over: [], existing: [7])[0].members == [member])
    }

    @Test func refreshForgetsAClosedWindowNothingCanFindAgain() {
        let decks = [deck([
            DeckMember(app: "com.example.code", title: nil, windowID: 7),
            DeckMember(app: "com.example.code", title: "kept.swift", windowID: 8)
        ])]
        let refreshed = DeckMatching.refreshed(decks, over: [], existing: [])
        #expect(refreshed[0].members == [DeckMember(app: "com.example.code", title: "kept.swift", windowID: nil)])
    }

    @Test func addingMovesAWindowOutOfItsOldDeck() {
        let first = deck([DeckMatching.member(for: window(1))], name: "A")
        let second = deck([], name: "B")
        let moved = DeckMatching.adding(window(1), to: second.id, in: [first, second])
        #expect(moved[0].members.isEmpty)
        #expect(moved[1].members.map(\.windowID) == [1])
    }

    @Test func groupingMakesTheNextNamedDeck() {
        let existing = Deck(name: "Deck 1", members: [DeckMatching.member(for: window(1))])
        let (decks, id) = DeckMatching.grouping([window(1), window(2)], in: [existing])
        #expect(decks.count == 2)
        #expect(decks[0].members.isEmpty)
        #expect(decks[1].id == id)
        #expect(decks[1].name == "Deck 2")
        #expect(decks[1].members.map(\.windowID) == [1, 2])
    }
}

@Suite struct TrayRuleTests {
    private let deck = UUID()
    private let other = UUID()

    @Test func aDeckOpensTheTrayOnIt() {
        #expect(TrayRule.step(showing: nil, pointerOn: .deck(deck), lastOn: nil) == .show(deck))
        #expect(TrayRule.step(showing: deck, pointerOn: .deck(other), lastOn: .deck(deck)) == .show(other))
    }

    @Test func anUngroupedWindowOrTheNewTileClosesItAtOnce() {
        #expect(TrayRule.step(showing: deck, pointerOn: .window(3), lastOn: .deck(deck)) == .close)
        #expect(TrayRule.step(showing: deck, pointerOn: .newDeck, lastOn: .deck(deck)) == .close)
    }

    @Test func leavingTheCardsWaitsBeforeClosing() {
        #expect(TrayRule.step(showing: deck, pointerOn: .grid, lastOn: .deck(deck)) == .closeAfter(.milliseconds(250)))
        #expect(TrayRule.step(showing: deck, pointerOn: nil, lastOn: .deck(deck)) == .closeAfter(.milliseconds(250)))
    }

    @Test func leavingTheTrayWaitsLonger() {
        #expect(TrayRule.step(showing: deck, pointerOn: nil, lastOn: .tray) == .closeAfter(.milliseconds(300)))
        let step = TrayRule.step(showing: deck, pointerOn: .grid, lastOn: .trayWindow(4))
        #expect(step == .closeAfter(.milliseconds(300)))
    }

    @Test func theTrayKeepsItselfOpen() {
        #expect(TrayRule.step(showing: deck, pointerOn: .tray, lastOn: nil) == .keep)
        #expect(TrayRule.step(showing: deck, pointerOn: .trayWindow(4), lastOn: .tray) == .keep)
    }

    @Test func aCardInTheTrayWinsOverTheTray() {
        let frames: [HoverTarget: CGRect] = [
            .tray: CGRect(x: 0, y: 300, width: 1000, height: 250),
            .trayWindow(4): CGRect(x: 100, y: 350, width: 200, height: 150),
            .grid: CGRect(x: 0, y: 0, width: 1000, height: 280),
            .deck(deck): CGRect(x: 10, y: 10, width: 190, height: 140)
        ]
        #expect(Hover.target(at: CGPoint(x: 150, y: 400), in: frames) == .trayWindow(4))
        #expect(Hover.target(at: CGPoint(x: 600, y: 400), in: frames) == .tray)
        #expect(Hover.target(at: CGPoint(x: 50, y: 50), in: frames) == .deck(deck))
        #expect(Hover.target(at: CGPoint(x: 600, y: 200), in: frames) == .grid)
        #expect(Hover.target(at: CGPoint(x: 600, y: 900), in: frames) == nil)
    }
}

@Suite struct DeckDropTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(
            id: id, pid: 1, bundleID: "com.example.app", appName: "App", title: "w\(id)",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    private let deck = Deck(name: "Deck 1", members: [
        DeckMember(app: "com.example.app", title: "w1", windowID: 1)
    ])

    private var windows: [WindowInfo] { [window(1), window(2), window(3)] }

    private func drop(_ id: CGWindowID, from source: DeckDrop.Source, on target: HoverTarget?) -> DeckDrop.Outcome {
        DeckDrop.drop(
            window(id), from: source, on: target, in: DeckMatching.arrange([deck], over: windows), decks: [deck]
        )
    }

    @Test func ontoAnotherWindowMakesADeckOfBoth() {
        guard case .changed(let decks, let show) = drop(2, from: .grid, on: .window(3)) else {
            Issue.record("unchanged")
            return
        }
        #expect(decks.count == 2)
        #expect(decks[1].members.map(\.windowID) == [3, 2])
        #expect(show == decks[1].id)
    }

    @Test func ontoADeckJoinsIt() {
        guard case .changed(let decks, _) = drop(2, from: .grid, on: .deck(deck.id)) else {
            Issue.record("unchanged")
            return
        }
        #expect(decks[0].members.map(\.windowID) == [1, 2])
    }

    @Test func ontoItsOwnDeckOrItselfChangesNothing() {
        #expect(drop(1, from: .grid, on: .deck(deck.id)) == .unchanged)
        #expect(drop(2, from: .grid, on: .window(2)) == .unchanged)
    }

    @Test func ontoTheNewTileMakesADeckOfOne() {
        guard case .changed(let decks, _) = drop(2, from: .grid, on: .newDeck) else {
            Issue.record("unchanged")
            return
        }
        #expect(decks[1].members.map(\.windowID) == [2])
    }

    @Test func outOfTheTrayLeavesTheDeck() {
        guard case .changed(let decks, let show) = drop(1, from: .tray(deck.id), on: nil) else {
            Issue.record("unchanged")
            return
        }
        #expect(decks[0].members.isEmpty)
        #expect(show == nil)
    }

    @Test func withinTheTrayOrFromTheGridToNowhereChangesNothing() {
        #expect(drop(1, from: .tray(deck.id), on: .tray) == .unchanged)
        #expect(drop(2, from: .grid, on: nil) == .unchanged)
    }
}

@MainActor
@Suite struct OverviewDragTests {
    private let first = CGRect(x: 20, y: 20, width: 190, height: 140)
    private let second = CGRect(x: 236, y: 20, width: 190, height: 140)
    private let tray = CGRect(x: 0, y: 200, width: 600, height: 250)

    private func center(_ frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    private func desktopOverview() -> Overview {
        let spaces = (1...2).map { index in
            SpaceInfo(id: UInt64(index), uuid: "d\(index)", kind: .desktop(number: index), isCurrent: index == 1,
                      windows: [])
        }
        let overview = Overview(windows: [], spaceItems: SpaceItems.items(for: spaces), decks: [], wallpaper: nil,
                                canRaise: true, canSeeTitles: true)
        overview.view = .spaces
        return overview
    }

    @Test func draggingOneDesktopOntoAnotherGroupsBoth() {
        let overview = desktopOverview()
        let items = overview.items
        overview.hoverFrames = [.desktop(items[0].id): first, .desktop(items[1].id): second]
        #expect(overview.press(at: center(first)))
        overview.dragged(to: center(second))
        overview.released(at: center(second))
        #expect(overview.decks.map(\.kind) == [.spaces])
        // The one dropped onto first, then the one dropped.
        #expect(overview.arrangement.decks.first?.windows == items.reversed())
    }

    @Test func draggingIntoAnOpenDeckTrayAddsTheItem() {
        for target in [HoverTarget.tray, .trayWindow(1)] {
            let overview = desktopOverview()
            let item = overview.items[0]
            let deck = Deck(name: "Work", kind: .spaces)
            overview.decks = [deck]
            overview.hoverFrames = [.desktop(item.id): first, .deck(deck.id): second, target: tray]
            #expect(overview.press(at: center(first)))
            overview.pointerMoved(to: center(second))
            overview.dragged(to: center(tray))
            overview.pointerMoved(to: center(tray))
            overview.released(at: center(tray))
            #expect(overview.arrangement.decks.first?.windows == [item])
        }
    }

    @Test func draggingOverADesktopTrayLeavesDecksAlone() {
        let overview = desktopOverview()
        let items = overview.items
        overview.hoverFrames = [.desktop(items[0].id): first, .desktop(items[1].id): second, .tray: tray]
        #expect(overview.press(at: center(first)))
        overview.pointerMoved(to: center(second))
        overview.dragged(to: center(tray))
        overview.released(at: center(tray))
        #expect(overview.decks.isEmpty)
    }
}

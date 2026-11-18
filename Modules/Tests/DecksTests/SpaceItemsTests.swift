import CoreGraphics
import Foundation
import Settings
import Testing

@testable import Decks

@Suite struct SpaceItemsTests {
    private func window(_ id: CGWindowID, app: String = "Code") -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: "com.example.\(app)", appName: app, title: "w\(id)", frame: .zero)
    }

    private var spaces: [SpaceInfo] {
        [
            SpaceInfo(id: 1, uuid: "d1", kind: .desktop(number: 1), isCurrent: true, windows: [window(10), window(11)]),
            SpaceInfo(id: 2, uuid: "fs", kind: .fullScreen, isCurrent: false, windows: [window(20, app: "Slack")]),
            SpaceInfo(id: 3, uuid: "d2", kind: .desktop(number: 2), isCurrent: false, windows: [])
        ]
    }

    @Test func standsADesktopInAsANumberedItemAndAFullScreenSpaceAsItsWindow() {
        let items = SpaceItems.items(for: spaces)
        #expect(items.map(\.item.id) == [SpaceItems.firstDesktopID, 20, SpaceItems.firstDesktopID + 1])
        #expect(items.map(\.item.label) == ["Desktop 1", "w20", "Desktop 2"])
        #expect(SpaceItems.isDesktop(items[2].item))
        #expect(!SpaceItems.isDesktop(items[1].item))
    }

    @Test func aDeckOfSpacesFindsItsDesktopsByIdentifierAndStoresThemSo() {
        let items = SpaceItems.items(for: spaces)
        let stored = [Deck(name: "Work", color: .blue, kind: .spaces, members: [
            DeckMember(app: "", title: nil, windowID: nil, space: "d2"),
            DeckMember(app: "com.example.Slack", title: "w20", windowID: 20)
        ])]
        let resolved = SpaceItems.resolved(stored, with: items)
        let arrangement = DeckMatching.arrange(resolved, over: items.map(\.item))
        #expect(arrangement.decks[0].windows.map(\.id) == [20, SpaceItems.firstDesktopID + 1])
        #expect(arrangement.ungrouped.map(\.id) == [SpaceItems.firstDesktopID])
        #expect(SpaceItems.stored(resolved, with: items) == stored)
    }

    @Test func groupingADesktopStoresItsIdentifier() {
        let items = SpaceItems.items(for: spaces)
        let grouped = DeckMatching.grouping([items[0].item, items[1].item], in: []).decks
        let stored = SpaceItems.stored(grouped, with: items)
        #expect(stored[0].members[0] == DeckMember(app: "", title: nil, windowID: nil, space: "d1"))
        #expect(stored[0].members[1].windowID == 20)
    }

    @Test func aRemovedDesktopIsKeptByIdentifierButMatchesNothing() {
        let stored = [Deck(name: "Work", color: .blue, kind: .spaces, members: [
            DeckMember(app: "", title: nil, windowID: nil, space: "gone")
        ])]
        let items = SpaceItems.items(for: spaces)
        let resolved = SpaceItems.resolved(stored, with: items)
        #expect(DeckMatching.arrange(resolved, over: items.map(\.item)).decks[0].windows.isEmpty)
        #expect(SpaceItems.stored(resolved, with: items) == stored)
    }
}

@Suite struct DeckRefreshTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: "com.example.app", appName: "App", title: "w\(id)", frame: .zero)
    }

    @Test func unavailableSpaceInventoryPreservesStoredMembership() {
        let deck = Deck(name: "Work", color: .blue, kind: .spaces, members: [
            DeckMember(app: "", title: nil, windowID: nil, space: "d1"),
            DeckMember(app: "com.example.app", title: nil, windowID: 9)
        ])
        let refreshed = SpaceItems.refreshed([deck], windows: [], items: nil, existing: [])
        #expect(SpaceItems.stored(refreshed, with: []) == [deck])
    }

    @Test func refreshesEachViewsDecksOverItsOwnItemsAndKeepsDesktopsByIdentifier() {
        let spaces = [SpaceInfo(id: 1, uuid: "d1", kind: .desktop(number: 1), isCurrent: true, windows: [window(10)])]
        let items = SpaceItems.items(for: spaces)
        let decks = [
            Deck(name: "W", color: .blue, kind: .windows, members: [
                DeckMember(app: "com.example.app", title: "w10", windowID: 99)
            ]),
            Deck(name: "S", color: .pink, kind: .spaces, members: [
                DeckMember(app: "", title: nil, windowID: nil, space: "d1")
            ])
        ]
        let refreshed = SpaceItems.refreshed(decks, windows: [window(10)], items: items, existing: [10])
        #expect(refreshed[0].members.map(\.windowID) == [10])
        #expect(refreshed[1].members.map(\.windowID) == [SpaceItems.firstDesktopID])
        #expect(SpaceItems.stored(refreshed, with: items)[1].members == decks[1].members)
    }
}

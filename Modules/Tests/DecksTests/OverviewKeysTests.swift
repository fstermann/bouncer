import CoreGraphics
import Foundation
import Settings
import Testing

@testable import Decks

private func window(_ id: CGWindowID, app: String = "Code", title: String? = nil) -> WindowInfo {
    WindowInfo(id: id, pid: 1, bundleID: "com.example.\(app)", appName: app, title: title ?? "w\(id)", frame: .zero)
}

@Suite struct SpaceDisplayTests {
    private func desktop(_ id: Int) -> [String: Any] {
        ["ManagedSpaceID": NSNumber(value: id), "uuid": "u\(id)", "type": NSNumber(value: 0)]
    }

    @Test func tagsEachSpaceWithItsDisplayAndKeepsOneDisplaysSpaces() {
        let displays: [[String: Any]] = [
            ["Display Identifier": "A", "Spaces": [desktop(1)]],
            ["Display Identifier": "B", "Spaces": [desktop(2)]]
        ]
        let spaces = SpaceList.assemble(displays: displays, windowsOnSpace: [:], windows: [])
        #expect(spaces.map(\.display) == ["A", "B"])
        #expect(SpaceList.on(display: "B", among: spaces).map(\.id) == [2])
        #expect(spaces[1].kind == .desktop(number: 1))
    }

    @Test func keepsEverySpaceWhileDisplaysShareThem() {
        let spaces = [
            SpaceInfo(id: 1, uuid: "u1", kind: .desktop(number: 1), isCurrent: true, windows: [], display: "Main")
        ]
        #expect(SpaceList.on(display: "A", among: spaces).map(\.id) == [1])
    }

    @Test func aCustomNameReplacesADesktopsNumberOnly() {
        var desktop = SpaceInfo(id: 1, uuid: "u1", kind: .desktop(number: 2), isCurrent: true, windows: [])
        desktop.customName = "Mail"
        var full = SpaceInfo(
            id: 2, uuid: "u2", kind: .fullScreen, isCurrent: false, windows: [window(5, app: "Slack")]
        )
        full.customName = "Chat"
        #expect(desktop.name == "Mail")
        #expect(full.name == "Slack")
    }
}

@Suite struct WallpaperTests {
    private func store(_ provider: String, url: String) throws -> [String: Any] {
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["type": "imageFile", "url": ["relative": url]], format: .binary, options: 0
        )
        let desktop: [String: Any] = [
            "Desktop": ["Content": ["Choices": [["Provider": provider, "Configuration": configuration]]]]
        ]
        return ["Spaces": ["s1": ["Default": desktop, "Displays": ["D": desktop]]]]
    }

    @Test func readsADesktopsImageFile() throws {
        let store = try store("com.apple.wallpaper.choice.image", url: "file:///Users/Shared/a.png")
        #expect(Wallpaper.imageURL(in: store, space: "s1", display: "D") == URL(string: "file:///Users/Shared/a.png"))
        let byDefault = Wallpaper.imageURL(in: store, space: "s1", display: "other")
        #expect(byDefault == URL(string: "file:///Users/Shared/a.png"))
        #expect(Wallpaper.imageURL(in: store, space: "s2", display: "D") == nil)
    }

    @Test func aSpaceWithoutItsOwnTakesThePictureForAllSpaces() throws {
        let all = try store("com.apple.wallpaper.choice.image", url: "file:///all.png")
        var store = try store("com.apple.wallpaper.choice.image", url: "file:///Users/Shared/a.png")
        store["AllSpacesAndDisplays"] = ((all["Spaces"] as? [String: Any])?["s1"] as? [String: Any])?["Default"]
        #expect(Wallpaper.imageURL(in: store, space: "s2", display: "D") == URL(string: "file:///all.png"))
        #expect(Wallpaper.imageURL(in: store, space: "s1", display: "D") == URL(string: "file:///Users/Shared/a.png"))
    }

    @Test func givesNoFileForAColour() throws {
        let store = try store("com.apple.wallpaper.choice.color", url: "file:///x.png")
        #expect(Wallpaper.imageURL(in: store, space: "s1", display: "D") == nil)
    }

    @Test func aFullScreenSpaceTakesItsDisplaysFirstDesktop() {
        let spaces = [
            SpaceInfo(id: 1, uuid: "fs0", kind: .fullScreen, isCurrent: false, windows: []),
            SpaceInfo(id: 2, uuid: "d1", kind: .desktop(number: 1), isCurrent: false, windows: []),
            SpaceInfo(id: 3, uuid: "d2", kind: .desktop(number: 2), isCurrent: false, windows: []),
            SpaceInfo(id: 4, uuid: "fs", kind: .fullScreen, isCurrent: true, windows: [])
        ]
        #expect(Wallpaper.fullScreenDesktop(among: spaces)?.uuid == "d1")
        #expect(Wallpaper.fullScreenDesktop(among: Array(spaces.prefix(3))) == nil)
        #expect(Wallpaper.shownDesktop(among: spaces)?.uuid == "d1")
        let onDesktop = spaces.map {
            SpaceInfo(id: $0.id, uuid: $0.uuid, kind: $0.kind, isCurrent: $0.uuid == "d2", windows: [])
        }
        #expect(Wallpaper.shownDesktop(among: onDesktop)?.uuid == "d2")
    }

    @Test func findsTheDocksWindowForADesktop() {
        func entry(_ owner: String, _ name: String, _ number: Int) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowName as String: name, kCGWindowNumber as String: number]
        }
        let entries = [
            entry("Dock", "Wallpaper-d1", 7), entry("Dock", "Wallpaper-d2", 9), entry("Finder", "Wallpaper-d3", 4)
        ]
        #expect(Wallpaper.dockWindow(of: "d2", in: entries) == 9)
        #expect(Wallpaper.dockWindow(of: "d3", in: entries) == nil)
    }
}

@Suite struct OverviewFilterTests {
    private let deck = Deck(name: "Work")

    @Test func keepsMatchingItemsAndDecksByNameOrWindow() {
        let arrangement = Arrangement(
            decks: [
                LiveDeck(deck: deck, windows: [window(1, title: "Inbox")]),
                LiveDeck(
                    deck: Deck(name: "Play"),
                    windows: [window(2, title: "Inbox"), window(3, title: "Game")]
                )
            ],
            ungrouped: [window(4, app: "Safari", title: "News"), window(5, title: "notes")]
        )
        let byWindow = OverviewFilter.filtered(arrangement, by: "game")
        #expect(byWindow.decks.map(\.deck.name) == ["Play"])
        #expect(byWindow.decks[0].windows.map(\.id) == [3])
        #expect(byWindow.ungrouped.isEmpty)
        let byName = OverviewFilter.filtered(arrangement, by: "wor")
        #expect(byName.decks.map(\.windows.count) == [1])
        #expect(OverviewFilter.filtered(arrangement, by: "safari").ungrouped.map(\.id) == [4])
        #expect(OverviewFilter.filtered(arrangement, by: "NÖTES").ungrouped.map(\.id) == [5])
        #expect(OverviewFilter.filtered(arrangement, by: " ") == arrangement)
    }

    @Test func aDesktopMatchesByItsWindows() {
        let desktop = window(SpaceItems.firstDesktopID, title: "Desktop 1")
        let arrangement = Arrangement(decks: [], ungrouped: [desktop])
        let filtered = OverviewFilter.filtered(arrangement, by: "mail") { _ in [window(9, app: "Mail")] }
        #expect(filtered.ungrouped == [desktop])
    }
}

@MainActor
@Suite struct OverviewKeysTests {
    private func overview() -> Overview {
        let spaces = [
            SpaceInfo(id: 1, uuid: "d1", kind: .desktop(number: 1), isCurrent: true, windows: [window(10)]),
            SpaceInfo(id: 2, uuid: "fs", kind: .fullScreen, isCurrent: false, windows: [window(20, app: "Slack")]),
            SpaceInfo(id: 3, uuid: "d2", kind: .desktop(number: 2), isCurrent: false, windows: [window(30)])
        ]
        let listed = SpaceList.windows(of: spaces)
        return Overview(
            windows: listed.map(\.window),
            spaces: Dictionary(uniqueKeysWithValues: listed.map { ($0.window.id, $0.space) }),
            spaceItems: SpaceItems.items(for: spaces), decks: [], wallpaper: nil, canRaise: true, canSeeTitles: true
        )
    }

    @Test func typingFiltersAndADigitFirstGoesToThatDesktop() {
        let overview = overview()
        var picked: [WindowInfo] = []
        overview.onPick = { picked = $0 }
        #expect(overview.key(.text("2")))
        #expect(picked.map(\.id) == [30])
        #expect(overview.query.isEmpty)
        #expect(overview.key(.text("w")))
        #expect(overview.key(.text("2")))
        #expect(overview.query == "w2")
        #expect(overview.arrangement.ungrouped.map(\.id) == [20])
        #expect(overview.key(.delete))
        #expect(overview.query == "w")
        #expect(overview.key(.escape))
        #expect(overview.query.isEmpty)
        #expect(!overview.key(.escape))
        _ = overview.key(.text(" "))
        #expect(overview.query.isEmpty)
    }

    @Test func returnPicksTheFirstCardLeft() {
        let overview = overview()
        var picked: [WindowInfo] = []
        overview.onPick = { picked = $0 }
        #expect(!overview.key(.enter))
        _ = overview.key(.text("w3"))
        #expect(overview.key(.enter))
        #expect(picked.map(\.id) == [30])
    }

    @Test func namingADesktopRenamesItsCardAndPlaceAndReportsIt() {
        let overview = overview()
        var named: [(String, String?)] = []
        overview.onSpaceRename = { named.append(($0, $1)) }
        let desktop = SpaceItems.firstDesktopID + 1
        overview.rename(Overview.trayID(of: desktop), to: " Mail ")
        #expect(overview.spaceItems.first { $0.item.id == desktop }?.item.label == "Mail")
        #expect(overview.place(of: window(30)) == "Mail")
        overview.rename(Overview.trayID(of: desktop), to: "")
        #expect(overview.spaceItems.first { $0.item.id == desktop }?.item.label == "Desktop 2")
        #expect(named.map(\.0) == ["d2", "d2"])
        #expect(named.map(\.1) == ["Mail", nil])
    }

    @Test func onlyTheCurrentSpacesWindowsChangeFullScreen() {
        let overview = overview()
        overview.view = .spaces
        func drag(_ item: WindowInfo, from source: DeckDrop.Source) -> Overview.Drag {
            Overview.Drag(window: item, source: source, start: .zero, point: .zero)
        }
        #expect(overview.fullScreenDrop(of: drag(window(10), from: .desktop)) == .enter)
        #expect(overview.fullScreenDrop(of: drag(window(30), from: .desktop)) == nil)
        #expect(overview.fullScreenDrop(of: drag(window(20, app: "Slack"), from: .grid)) == nil)
        #expect(overview.fullScreenDrop(of: drag(overview.spaceItems[0].item, from: .grid)) == nil)
    }

    @Test func theCurrentFullScreenSpaceLeaves() {
        let spaces = [
            SpaceInfo(id: 1, uuid: "d1", kind: .desktop(number: 1), isCurrent: false, windows: [window(10)]),
            SpaceInfo(id: 2, uuid: "fs", kind: .fullScreen, isCurrent: true, windows: [window(20, app: "Slack")])
        ]
        let listed = SpaceList.windows(of: spaces)
        let overview = Overview(
            windows: listed.map(\.window),
            spaces: Dictionary(uniqueKeysWithValues: listed.map { ($0.window.id, $0.space) }),
            spaceItems: SpaceItems.items(for: spaces), decks: [], wallpaper: nil, canRaise: true, canSeeTitles: true
        )
        overview.view = .spaces
        let drag = Overview.Drag(window: window(20, app: "Slack"), source: .grid, start: .zero, point: .zero)
        #expect(overview.fullScreenDrop(of: drag) == .leave)
    }
}

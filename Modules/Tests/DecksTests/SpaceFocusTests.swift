import CoreGraphics
import Foundation
import Testing

@testable import Decks

@Suite struct SpaceFocusTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: "app", appName: "App", title: nil, frame: .zero)
    }

    private func desktop(_ number: Int, windows: [WindowInfo]) -> SpaceInfo {
        SpaceInfo(id: UInt64(number), uuid: "d\(number)", kind: .desktop(number: number),
                  isCurrent: number == 1, windows: windows)
    }

    @Test func raisingAnInactiveDeckKeepsTheRequestedOrderOnItsDestination() {
        let requested = [window(1), window(2), window(3)]
        let destination = desktop(2, windows: [window(3), window(4), window(1)])
        #expect(SpaceFocus.members(requested, on: destination) == [window(1), window(3)])
    }

    @Test func staleWindowCannotMatchAnotherWindowByGeometry() {
        let ids: [CGWindowID?] = [11, 12]
        let match = WindowFocus.matching(10, among: Array(ids.indices), id: { ids[$0] }, fallback: { $0.first })
        #expect(match == nil)
    }

    @Test func unreadableWindowNumbersAllowFallbackButExactNumberWins() {
        let ids: [CGWindowID?] = [11, nil, 12]
        let indices = Array(ids.indices)
        #expect(WindowFocus.matching(10, among: indices, id: { ids[$0] }, fallback: { $0.first }) == 1)
        #expect(WindowFocus.matching(12, among: indices, id: { ids[$0] }, fallback: { $0.first }) == 2)
    }

    @MainActor @Test func selectingAnInactiveDesktopSkipsItsSharedFrontWindow() {
        let shared = window(1)
        let local = window(2)
        let desktops = [
            desktop(1, windows: [shared]), desktop(2, windows: [shared, local]), desktop(3, windows: [shared])
        ]
        let items = SpaceItems.items(for: desktops)
        let overview = Overview(windows: [shared, local], spaceItems: items, decks: [],
                                wallpaper: nil, canRaise: true, canSeeTitles: true)
        overview.view = .spaces
        #expect(overview.pickable(items[0].item) == [shared])
        #expect(overview.pickable(items[1].item) == [local])
        #expect(overview.pickable(items[2].item).isEmpty)
    }
}

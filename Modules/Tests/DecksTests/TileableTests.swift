import CoreGraphics
import Testing

@testable import Decks

@Suite struct TileableTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: nil, appName: "App", title: "w\(id)", frame: .zero)
    }

    private func space(_ id: UInt64, _ kind: SpaceInfo.Kind, current: Bool = false) -> SpaceInfo {
        SpaceInfo(id: id, uuid: "s\(id)", kind: kind, isCurrent: current, windows: [])
    }

    @Test func skipsFullScreenWindows() {
        let desktop = space(1, .desktop(number: 1), current: true)
        let spaces = [10: desktop, 11: desktop, 20: space(2, .fullScreen)] as [CGWindowID: SpaceInfo]
        #expect(Tiling.tileable([window(10), window(20), window(11)], spaces: spaces).map(\.id) == [10, 11])
    }

    @Test func prefersTheCurrentDesktop() {
        let other = space(2, .desktop(number: 2))
        let spaces = [10: space(1, .desktop(number: 1), current: true), 20: other, 21: other] as [CGWindowID: SpaceInfo]
        #expect(Tiling.tileable([window(20), window(21), window(10)], spaces: spaces).map(\.id) == [10])
    }

    @Test func elseTakesTheDesktopWithMost() {
        let two = space(2, .desktop(number: 2))
        let spaces = [10: space(1, .desktop(number: 1)), 20: two, 21: two] as [CGWindowID: SpaceInfo]
        #expect(Tiling.tileable([window(10), window(20), window(21)], spaces: spaces).map(\.id) == [20, 21])
    }

    @Test func noneWhenAllAreFullScreen() {
        let spaces = [20: space(2, .fullScreen)] as [CGWindowID: SpaceInfo]
        #expect(Tiling.tileable([window(20)], spaces: spaces).isEmpty)
    }

    @Test func everyWindowWithoutSpaces() {
        #expect(Tiling.tileable([window(1), window(2)], spaces: [:]).count == 2)
    }
}

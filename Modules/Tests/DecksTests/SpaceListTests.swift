import CoreGraphics
import Foundation
import Testing

@testable import Decks

@Suite struct SpaceListTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(
            id: id, pid: 1, bundleID: "com.example.app", appName: "App", title: "w\(id)",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    private func space(_ id: Int, type: Int) -> [String: Any] {
        ["ManagedSpaceID": NSNumber(value: id), "uuid": "uuid-\(id)", "type": NSNumber(value: type)]
    }

    @Test func numbersDesktopsAndKeepsFullScreenSpacesInOrder() {
        let displays: [[String: Any]] = [[
            "Current Space": ["ManagedSpaceID": NSNumber(value: 3)],
            "Spaces": [space(1, type: 4), space(2, type: 0), space(3, type: 4), space(4, type: 0)]
        ]]
        let spaces = SpaceList.assemble(
            displays: displays, windowsOnSpace: [1: [10], 2: [20, 21], 3: [30], 4: []],
            windows: [window(10), window(20), window(21), window(30)]
        )
        #expect(spaces.map(\.id) == [1, 2, 3, 4])
        #expect(spaces.map(\.kind) == [.fullScreen, .desktop(number: 1), .fullScreen, .desktop(number: 2)])
        #expect(spaces.map(\.isCurrent) == [false, false, true, false])
        #expect(spaces[1].windows.map(\.id) == [20, 21])
        #expect(spaces[1].uuid == "uuid-2")
    }

    @Test func dropsAFullScreenSpaceWithNoWindowAndUnknownWindows() {
        let displays: [[String: Any]] = [["Spaces": [space(1, type: 4), space(2, type: 0), space(5, type: 2)]]]
        let spaces = SpaceList.assemble(
            displays: displays, windowsOnSpace: [1: [99], 2: [20, 98]], windows: [window(20)]
        )
        #expect(spaces.map(\.id) == [2])
        #expect(spaces[0].windows.map(\.id) == [20])
    }

    @Test func findsASpacesPlaceAmongItsDisplaysSpacesFullScreenOnesCounted() {
        let displays: [[String: Any]] = [
            ["Spaces": [space(1, type: 0), space(2, type: 0)]],
            ["Spaces": [space(3, type: 0), space(4, type: 4), space(5, type: 0)]]
        ]
        #expect(SpaceList.position(of: 5, in: displays).map { [$0.index, $0.count] } == [2, 3])
        #expect(SpaceList.position(of: 2, in: displays).map { [$0.index, $0.count] } == [1, 2])
        #expect(SpaceList.position(of: 9, in: displays) == nil)
    }

    /// Bits read from real windows: a document window, a full screen app's toolbar, a hidden helper.
    @Test func tellsDocumentWindowsFromToolbarsAndHelpers() {
        #expect(SpaceList.isOrdinary(parent: 0, level: 0, attributes: 0x3, tags: 0x3_0004_0100_0824_01))
        #expect(SpaceList.isOrdinary(parent: 0, level: 0, attributes: 0x3, tags: 0x1_0048_2001))
        #expect(!SpaceList.isOrdinary(parent: 0, level: 0, attributes: 0x3, tags: 0x804_0401_400c_2080))
        #expect(!SpaceList.isOrdinary(parent: 0, level: 0, attributes: 0x3, tags: 0x1_400c_2282))
        #expect(!SpaceList.isOrdinary(parent: 0, level: 0, attributes: 0x2, tags: 0x10_00ca_082))
        #expect(!SpaceList.isOrdinary(parent: 7, level: 0, attributes: 0x3, tags: 0x3_0004_0100_0824_01))
    }
}

@Suite struct SpaceOrderTests {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: nil, appName: "App", title: nil, frame: .zero)
    }

    @Test func listsTheCurrentSpacesWindowsFirstAndEachWindowOnce() {
        let spaces = [
            SpaceInfo(id: 1, uuid: "a", kind: .desktop(number: 1), isCurrent: false, windows: [window(10), window(11)]),
            SpaceInfo(id: 2, uuid: "b", kind: .fullScreen, isCurrent: true, windows: [window(20)]),
            // A window on every Space is listed on each; it shows once, on the first.
            SpaceInfo(id: 3, uuid: "c", kind: .desktop(number: 2), isCurrent: false, windows: [window(30), window(10)])
        ]
        let listed = SpaceList.windows(of: spaces)
        #expect(listed.map(\.window.id) == [20, 10, 11, 30])
        #expect(listed.map(\.space.id) == [2, 1, 1, 3])
    }
}

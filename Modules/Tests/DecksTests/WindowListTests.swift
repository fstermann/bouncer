import CoreGraphics
import Testing

@testable import Decks

@Suite struct WindowListTests {
    private func entry(
        id: Int, pid: Int = 100, layer: Int = 0, alpha: Double = 1, name: String? = "Doc",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    ) -> [String: Any] {
        var entry: [String: Any] = [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowOwnerName as String: "App",
            kCGWindowBounds as String: frame.dictionaryRepresentation
        ]
        if let name { entry[kCGWindowName as String] = name }
        return entry
    }

    private func windows(_ entries: [[String: Any]], own: pid_t = 1) -> [WindowInfo] {
        WindowList.windows(in: entries, excluding: own) { _ in "com.example.app" }
    }

    @Test func keepsOrdinaryWindowsInOrder() {
        let found = windows([entry(id: 2), entry(id: 1)])
        #expect(found.map(\.id) == [2, 1])
        #expect(found.first?.bundleID == "com.example.app")
        #expect(found.first?.frame == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func dropsOtherLayersHiddenAndTinyWindows() {
        let found = windows([
            entry(id: 1, layer: 25),
            entry(id: 2, alpha: 0),
            entry(id: 3, frame: CGRect(x: 0, y: 0, width: 1512, height: 32)),
            entry(id: 4)
        ])
        #expect(found.map(\.id) == [4])
    }

    @Test func dropsBouncersOwnWindows() {
        #expect(windows([entry(id: 1, pid: 7), entry(id: 2)], own: 7).map(\.id) == [2])
    }

    @Test func labelFallsBackToTheAppName() {
        let found = windows([entry(id: 1, name: nil), entry(id: 2, name: ""), entry(id: 3)])
        #expect(found.map(\.label) == ["App", "App", "Doc"])
    }
}

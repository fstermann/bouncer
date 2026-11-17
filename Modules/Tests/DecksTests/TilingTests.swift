import CoreGraphics
import Testing

@testable import Decks

@Suite struct TilingTests {
    private let area = CGRect(x: 0, y: 25, width: 1512, height: 900)

    @Test func oneWindowFillsTheArea() {
        #expect(Tiling.frames(count: 1, in: area) == [area])
    }

    @Test func threeWindowsShareOneRow() {
        let frames = Tiling.frames(count: 3, in: area)
        #expect(frames.map(\.width) == [498, 498, 498])
        #expect(frames.map(\.minX) == [0, 506, 1012])
        #expect(frames.allSatisfy { $0.minY == 25 && $0.height == 900 })
    }

    @Test func fiveWindowsFillTwoRowsTheTopOneTakingThree() {
        let frames = Tiling.frames(count: 5, in: area)
        #expect(frames.count == 5)
        #expect(frames.prefix(3).allSatisfy { $0.minY == 25 })
        #expect(frames.suffix(2).allSatisfy { $0.minY == 25 + 446 + 8 })
        #expect(frames.suffix(2).map(\.width) == [752, 752])
    }

    @Test func framesStayInsideTheArea() {
        for count in 1...8 {
            #expect(Tiling.frames(count: count, in: area).allSatisfy { area.contains($0) })
        }
    }

    @Test func noWindowsNoFrames() {
        #expect(Tiling.frames(count: 0, in: area).isEmpty)
    }
}

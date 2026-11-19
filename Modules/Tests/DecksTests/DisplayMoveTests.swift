import CoreGraphics
import Testing

@testable import Decks

@Suite struct DisplayMoveTests {
    private let laptop = CGRect(x: 0, y: 25, width: 1512, height: 957)
    private let monitor = CGRect(x: -1209, y: -1080, width: 1920, height: 1055)

    @Test func keepsTheWindowsPlaceRelativeToTheDisplay() {
        let left = DisplayMove.frame(CGRect(x: 0, y: 25, width: 800, height: 600), from: laptop, to: monitor)
        #expect(left == CGRect(x: -1209, y: -1080, width: 800, height: 600))
        let right = DisplayMove.frame(CGRect(x: 712, y: 382, width: 800, height: 600), from: laptop, to: monitor)
        #expect(right == CGRect(x: -89, y: -625, width: 800, height: 600))
    }

    @Test func shrinksAWindowTooLargeForTheDisplay() {
        let moved = DisplayMove.frame(CGRect(x: 0, y: 0, width: 1920, height: 1055), from: monitor, to: laptop)
        #expect(moved == CGRect(x: 0, y: 25, width: 1512, height: 957))
    }

    @Test func centresAWindowThatFilledItsDisplay() {
        let moved = DisplayMove.frame(laptop, from: laptop, to: monitor)
        #expect(moved == CGRect(x: -1209 + 204, y: -1080 + 49, width: 1512, height: 957))
    }

    @Test func findsTheDisplayUnderAPoint() {
        #expect(DisplayMove.display(at: CGPoint(x: -5, y: -100), among: [laptop, monitor]) == 1)
        #expect(DisplayMove.display(at: CGPoint(x: 5, y: 100), among: [laptop, monitor]) == 0)
        #expect(DisplayMove.display(at: CGPoint(x: 5000, y: 100), among: [laptop, monitor]) == nil)
    }
}

@Suite struct SwipeDetectorTests {
    /// The swipe each frame completed, fed in turn to one detector.
    private func fired(_ frames: [[Double]]) -> [SwipeDetector.Direction?] {
        var detector = SwipeDetector()
        return frames.map { detector.feed($0) }
    }

    @Test func firesOnceWhenThreeFingersRise() {
        let frames = [[0.40, 0.45, 0.50], [0.45, 0.50, 0.55], [0.53, 0.58, 0.63], [0.60, 0.65, 0.70]]
        #expect(fired(frames) == [nil, nil, .up, nil])
    }

    @Test func firesOnceWhenThreeFingersFall() {
        let frames = [[0.60, 0.65, 0.70], [0.55, 0.60, 0.65], [0.47, 0.52, 0.57], [0.40, 0.45, 0.50]]
        #expect(fired(frames) == [nil, nil, .down, nil])
    }

    @Test func ignoresOtherFingerCountsAndSmallDrift() {
        let frames = [[0.2, 0.3], [0.2, 0.3, 0.4, 0.5], [0.74, 0.74, 0.74], [0.66, 0.66, 0.66]]
        #expect(fired(frames).allSatisfy { $0 == nil })
    }

    @Test func liftingTheFingersStartsAgain() {
        let frames = [[0.3, 0.3, 0.3], [0.45, 0.45, 0.45], [], [0.45, 0.45, 0.45], [0.3, 0.3, 0.3]]
        #expect(fired(frames) == [nil, .up, nil, nil, .down])
    }
}

@Suite struct BySpaceTests {
    @Test func currentSpaceFirstThenEachOtherSpace() {
        func window(_ id: CGWindowID) -> WindowInfo {
            WindowInfo(id: id, pid: 1, bundleID: nil, appName: "A", title: nil, frame: .zero)
        }
        let current = SpaceInfo(id: 1, uuid: "a", kind: .desktop(number: 1), isCurrent: true, windows: [])
        let other = SpaceInfo(id: 2, uuid: "b", kind: .desktop(number: 2), isCurrent: false, windows: [])
        let groups = DisplayMove.bySpace(
            [window(10), window(11), window(12)], spaces: [10: other, 11: current, 12: other]
        )
        #expect(groups.map { $0.windows.map(\.id) } == [[11], [10, 12]])
        #expect(groups.map(\.isElsewhere) == [false, true])
    }
}

@Suite struct SpaceSwitchTests {
    @Test func countsTheSpacesToCrossAndWhichWay() {
        let order: [UInt64] = [5, 1, 9, 3]
        #expect(SpaceSwitch.steps(from: 1, to: 3, in: order) == 2)
        #expect(SpaceSwitch.steps(from: 3, to: 5, in: order) == -3)
        #expect(SpaceSwitch.steps(from: 9, to: 9, in: order) == 0)
        #expect(SpaceSwitch.steps(from: 2, to: 9, in: order) == nil)
    }
}

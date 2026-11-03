import Foundation
import Testing

@testable import Todos

@Suite struct PresentationTimerTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func aCountdownWarnsInItsLastMinuteAndIsOverAtZero() {
        let timer = PresentationTimer(kind: .countdown(300), start: start)
        #expect(timer.phase(at: start) == .running)
        #expect(timer.phase(at: start + 239) == .running)
        #expect(timer.phase(at: start + 240) == .ending)
        #expect(timer.phase(at: start + 300) == .over)
        #expect(timer.phase(at: start + 900) == .over)
    }

    @Test func aCountdownChangesColourTwiceAndThenNoMore() {
        let timer = PresentationTimer(kind: .countdown(300), start: start)
        #expect(timer.nextChange(after: start) == start + 240)
        #expect(timer.nextChange(after: start + 240) == start + 300)
        #expect(timer.nextChange(after: start + 300) == nil)
    }

    @Test func aStopwatchRunsWithoutEnd() {
        let timer = PresentationTimer(kind: .stopwatch, start: start)
        #expect(timer.end == nil)
        #expect(timer.phase(at: start + 10_000) == .running)
        #expect(timer.nextChange(after: start) == nil)
    }
}

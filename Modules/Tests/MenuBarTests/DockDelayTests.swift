import Foundation
import Testing

@testable import MenuBar

@Suite struct DockDelayTests {
    @Test func aSetDelayIsTakenAsSeconds() {
        #expect(DockDelay.seconds(from: NSNumber(value: 0)) == 0)
        #expect(DockDelay.seconds(from: NSNumber(value: 1.5)) == 1.5)
    }

    @Test func noDelayIsTheDocksDefault() {
        #expect(DockDelay.seconds(from: nil) == DockDelay.standard)
        #expect(DockDelay.seconds(from: "fast") == DockDelay.standard)
    }

    @Test func aNegativeDelayIsNone() {
        #expect(DockDelay.seconds(from: NSNumber(value: -1)) == 0)
    }
}
